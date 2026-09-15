import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/daily_plan.dart';
import '../models/wellness_enums.dart';
import '../models/wellness_method.dart';

/// Service responsible for loading, saving, and managing Daily Wellness Plans.
///
/// Handles Firestore persistence at `users/{uid}/daily_plans/{YYYY-MM-DD}`,
/// local caching via SharedPreferences, and fallback plan selection from
/// the bundled asset `assets/data/fallback_plans.json`.
class WellnessPlanService {
  final FirebaseFirestore _firestore;
  final Random _random;

  static const String _dailyPlanCacheKey = 'wellness_daily_plan';

  /// Cached fallback plans loaded from the asset bundle. Populated lazily
  /// on the first call to [selectFallbackPlan].
  List<Map<String, dynamic>>? _fallbackPlansCache;

  WellnessPlanService({
    FirebaseFirestore? firestore,
    Random? random,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _random = random ?? Random();

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Loads the [DailyPlan] for the given [date] from Firestore.
  ///
  /// Returns `null` if no plan exists for that date.
  /// Firestore path: `users/{uid}/daily_plans/{YYYY-MM-DD}`
  Future<DailyPlan?> loadPlanForDate(String userId, DateTime date) async {
    final dateKey = _formatDateKey(date);
    final docRef = _firestore
        .collection('users')
        .doc(userId)
        .collection('daily_plans')
        .doc(dateKey);

    final snapshot = await docRef.get();
    if (!snapshot.exists || snapshot.data() == null) {
      return null;
    }

    return DailyPlan.fromMap(snapshot.data()!);
  }

  /// Persists a [DailyPlan] to Firestore and caches it locally in
  /// SharedPreferences under the [_dailyPlanCacheKey] key.
  ///
  /// The document is keyed by date string (YYYY-MM-DD) so there is
  /// exactly one plan per user per calendar day.
  Future<void> savePlan(String userId, DailyPlan plan) async {
    final dateKey = _formatDateKey(plan.date);
    final docRef = _firestore
        .collection('users')
        .doc(userId)
        .collection('daily_plans')
        .doc(dateKey);

    final planMap = plan.toMap();
    await docRef.set(planMap);

    // Cache locally
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dailyPlanCacheKey, jsonEncode(planMap));
  }

  /// Updates the completion status of a single action within a plan.
  ///
  /// Performs a partial Firestore update to avoid overwriting the entire
  /// plan document. Must complete within 2 seconds per Requirement 3.6.
  Future<void> updateActionCompletion(
    String userId,
    String planId,
    String actionId,
    bool completed,
  ) async {
    final docRef = _firestore
        .collection('users')
        .doc(userId)
        .collection('daily_plans')
        .doc(planId);

    final snapshot = await docRef.get();
    if (!snapshot.exists || snapshot.data() == null) {
      return;
    }

    final data = snapshot.data()!;
    final actions = List<Map<String, dynamic>>.from(
      (data['actions'] as List<dynamic>).map((a) => Map<String, dynamic>.from(a as Map)),
    );

    // Find and update the matching action
    for (int i = 0; i < actions.length; i++) {
      if (actions[i]['id'] == actionId) {
        actions[i]['isCompleted'] = completed;
        break;
      }
    }

    await docRef.update({'actions': actions});
  }

  /// Marks a plan as completed by setting `isCompleted: true` on the
  /// plan document in Firestore.
  ///
  /// This fulfills the "write plan_completed record" requirement by
  /// updating the plan document directly (Requirement 3.8).
  Future<void> markPlanComplete(String userId, String planId) async {
    final docRef = _firestore
        .collection('users')
        .doc(userId)
        .collection('daily_plans')
        .doc(planId);

    await docRef.update({'isCompleted': true});
  }

  /// Loads the last [days] days of plans for a user, ordered by date
  /// descending. Used to provide plan history context to the AI Engine.
  ///
  /// Returns an empty list if no plans exist in the given range.
  Future<List<DailyPlan>> loadRecentPlans(String userId, {int days = 30}) async {
    final now = DateTime.now();
    final startDate = now.subtract(Duration(days: days));

    final querySnapshot = await _firestore
        .collection('users')
        .doc(userId)
        .collection('daily_plans')
        .where('date', isGreaterThanOrEqualTo: startDate.toIso8601String())
        .orderBy('date', descending: true)
        .get();

    return querySnapshot.docs
        .where((doc) => doc.data().isNotEmpty)
        .map((doc) => DailyPlan.fromMap(doc.data()))
        .toList();
  }

  /// Selects a fallback plan from `assets/data/fallback_plans.json` using
  /// the following algorithm:
  ///
  /// 1. Load and parse the JSON asset (cached after first load).
  /// 2. Filter by [energyTier] exact match.
  /// 3. Filter by [timeRange] — prefer exact match, else use nearest range.
  /// 4. From remaining candidates, select randomly for variety.
  /// 5. Convert to a [DailyPlan] model and return.
  ///
  /// The [energyTier] maps to: 1 = energyScore 1–2, 2 = energyScore 3,
  /// 3 = energyScore 4–5.
  ///
  /// The [timeRange] should be one of the [AvailableTimeRange] enum `.name`
  /// values (e.g., "under10", "range10_20", etc.).
  Future<DailyPlan> selectFallbackPlan(
    int energyTier,
    String timeRange, {
    String? excludeId,
    List<String> preferredMethods = const [],
  }) async {
    final plans = await _loadFallbackPlans();

    // Step 1: Filter by energy tier
    final tierMatches = plans
        .where((p) => p['energyTier'] == energyTier)
        .toList();

    // If no tier matches (shouldn't happen with proper data), use all plans
    final candidates = tierMatches.isNotEmpty ? tierMatches : plans;

    // Step 2: Filter by time range — exact match preferred
    final exactTimeMatches = candidates
        .where((p) => p['timeRange'] == timeRange)
        .toList();

    List<Map<String, dynamic>> finalCandidates;
    if (exactTimeMatches.isNotEmpty) {
      finalCandidates = exactTimeMatches;
    } else {
      // Find nearest time range
      finalCandidates = _findNearestTimeRange(candidates, timeRange);
    }

    // Step 3: Exclude the current plan if possible
    if (excludeId != null) {
      final filtered = finalCandidates
          .where((p) => p['id'] != excludeId)
          .toList();
      if (filtered.isNotEmpty) {
        finalCandidates = filtered;
      } else {
        // All candidates in this time range are the current plan.
        // Expand to ALL plans in this tier to guarantee a different plan.
        final expandedFiltered = candidates
            .where((p) => p['id'] != excludeId)
            .toList();
        if (expandedFiltered.isNotEmpty) {
          finalCandidates = expandedFiltered;
        }
      }
    }

    // Step 3b: Prefer plans whose actions match the user's preferred wellness
    // methods (by keyword). Only narrows when at least one candidate matches,
    // so behavior is unchanged when no method-matching plan exists.
    if (preferredMethods.isNotEmpty) {
      final keywords = <String>[];
      for (final id in preferredMethods) {
        final method = wellnessMethodById(id);
        if (method != null) keywords.addAll(method.keywords);
      }
      if (keywords.isNotEmpty) {
        final methodMatches = finalCandidates.where((p) {
          final actions = (p['actions'] as List?) ?? const [];
          for (final a in actions) {
            final title =
                (a is Map ? (a['title']?.toString() ?? '') : '').toLowerCase();
            if (keywords.any((k) => title.contains(k))) return true;
          }
          return false;
        }).toList();
        if (methodMatches.isNotEmpty) {
          finalCandidates = methodMatches;
        }
      }
    }

    // Step 4: Random selection among candidates
    final selected = finalCandidates[_random.nextInt(finalCandidates.length)];

    // Step 5: Convert to DailyPlan
    return _fallbackMapToDailyPlan(selected);
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Formats a [DateTime] as 'YYYY-MM-DD' for use as Firestore document ID.
  String _formatDateKey(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  /// Loads fallback plans from the bundled asset, caching them after
  /// the first load to avoid repeated I/O.
  Future<List<Map<String, dynamic>>> _loadFallbackPlans() async {
    if (_fallbackPlansCache != null) {
      return _fallbackPlansCache!;
    }

    final jsonString =
        await rootBundle.loadString('assets/data/fallback_plans.json');
    final List<dynamic> decoded = jsonDecode(jsonString) as List<dynamic>;
    _fallbackPlansCache = decoded
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    return _fallbackPlansCache!;
  }

  /// Finds candidates with the nearest time range to [targetRange] from
  /// the [candidates] list.
  ///
  /// Uses the [AvailableTimeRange] enum ordering to determine distance.
  List<Map<String, dynamic>> _findNearestTimeRange(
    List<Map<String, dynamic>> candidates,
    String targetRange,
  ) {
    final timeRangeOrder = AvailableTimeRange.values.map((e) => e.name).toList();
    final targetIndex = timeRangeOrder.indexOf(targetRange);

    // If the target isn't in our known ranges, return all candidates
    if (targetIndex == -1) {
      return candidates;
    }

    // Calculate distance for each candidate's time range and find minimum
    int minDistance = timeRangeOrder.length;
    for (final candidate in candidates) {
      final candidateRange = candidate['timeRange'] as String;
      final candidateIndex = timeRangeOrder.indexOf(candidateRange);
      if (candidateIndex != -1) {
        final distance = (candidateIndex - targetIndex).abs();
        if (distance < minDistance) {
          minDistance = distance;
        }
      }
    }

    // Return all candidates at the minimum distance
    return candidates.where((candidate) {
      final candidateRange = candidate['timeRange'] as String;
      final candidateIndex = timeRangeOrder.indexOf(candidateRange);
      if (candidateIndex == -1) return false;
      return (candidateIndex - targetIndex).abs() == minDistance;
    }).toList();
  }

  /// Converts a raw fallback plan JSON map into a [DailyPlan] instance.
  ///
  /// Sets `isFallback: true` and uses today's date since the fallback is
  /// being used as today's plan.
  DailyPlan _fallbackMapToDailyPlan(Map<String, dynamic> map) {
    return DailyPlan.fromMap({
      'id': map['id'] as String,
      'date': DateTime.now().toIso8601String(),
      'todaysFocus': map['todaysFocus'] as String,
      'actions': map['actions'],
      'totalTime': map['totalTime'] as int,
      'aiInsight': null,
      'isFallback': true,
      'isCompleted': false,
      'checkInId': null,
      'energyTier': map['energyTier'] as int?,
    });
  }
}
