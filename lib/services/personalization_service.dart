import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/check_in.dart';
import '../models/user_behavior_profile.dart';
import '../models/wellness_enums.dart';

/// Service responsible for behavioral personalization of the wellness experience.
///
/// Handles loading/updating the user's behavior profile from Firestore,
/// computing the personalization tier, pre-filling check-in values based
/// on history, computing action category weights, and detecting recurring
/// patterns in check-in data.
class PersonalizationService {
  final FirebaseFirestore? _injectedDb;

  /// Creates a [PersonalizationService].
  ///
  /// If [firestore] is not provided, `FirebaseFirestore.instance` is used
  /// lazily on the first Firestore operation. This allows instantiation
  /// without an initialized Firebase app (useful for testing pure logic).
  PersonalizationService({FirebaseFirestore? firestore})
      : _injectedDb = firestore;

  FirebaseFirestore get _db => _injectedDb ?? FirebaseFirestore.instance;

  /// Loads the user's behavior profile from Firestore.
  ///
  /// Path: `users/{userId}/behavior_profile/{userId}`
  /// Returns `null` if the document does not exist or the read fails.
  Future<UserBehaviorProfile?> loadProfile(String userId) async {
    try {
      final doc = await _db
          .collection('users')
          .doc(userId)
          .collection('behavior_profile')
          .doc(userId)
          .get();

      if (!doc.exists || doc.data() == null) return null;
      return UserBehaviorProfile.fromMap(doc.data()!);
    } catch (e) {
      debugPrint('PersonalizationService.loadProfile error: $e');
      return null;
    }
  }

  /// Persists the user's behavior profile to Firestore.
  ///
  /// Path: `users/{userId}/behavior_profile/{userId}`
  Future<void> updateProfile(
      String userId, UserBehaviorProfile profile) async {
    try {
      await _db
          .collection('users')
          .doc(userId)
          .collection('behavior_profile')
          .doc(userId)
          .set(profile.toMap(), SetOptions(merge: true));
    } catch (e) {
      debugPrint('PersonalizationService.updateProfile error: $e');
      rethrow;
    }
  }

  /// Determines the personalization tier based on check-in count and premium status.
  ///
  /// Logic:
  /// - 1–13 check-ins: [PersonalizationTier.standard] (regardless of premium)
  /// - 14–27 check-ins + isPremium: [PersonalizationTier.prefill]
  /// - 14–27 check-ins + !isPremium: [PersonalizationTier.standard]
  /// - 28+ check-ins + isPremium: [PersonalizationTier.proactive]
  /// - 28+ check-ins + !isPremium: [PersonalizationTier.standard]
  PersonalizationTier computeTier(int completedCheckIns, bool isPremium) {
    if (completedCheckIns < 14) {
      return PersonalizationTier.standard;
    }
    if (!isPremium) {
      return PersonalizationTier.standard;
    }
    if (completedCheckIns < 28) {
      return PersonalizationTier.prefill;
    }
    return PersonalizationTier.proactive;
  }

  /// Computes pre-fill values for each check-in field based on the last 14 check-ins.
  ///
  /// For each field (energyScore, moodState, recoveryStatus, availableTime),
  /// finds the mode (most frequent value). Ties are broken by recency — the
  /// value that appears most recently among the tied values wins.
  ///
  /// Returns a [CheckIn] with the computed prefill values. Fields where all
  /// entries are null/skipped will have null values in the result.
  CheckIn computePrefill(List<CheckIn> last14CheckIns) {
    final energyScore = _computeFieldMode<int>(
      last14CheckIns,
      (c) => c.energyScore,
    );

    final moodState = _computeFieldMode<MoodState>(
      last14CheckIns,
      (c) => c.moodState,
    );

    final recoveryStatus = _computeFieldMode<RecoveryStatus>(
      last14CheckIns,
      (c) => c.recoveryStatus,
    );

    final availableTime = _computeFieldMode<AvailableTimeRange>(
      last14CheckIns,
      (c) => c.availableTime,
    );

    return CheckIn(
      id: 'prefill',
      date: DateTime.now(),
      energyScore: energyScore,
      moodState: moodState,
      recoveryStatus: recoveryStatus,
      availableTime: availableTime,
    );
  }

  /// Computes action category weights based on the user's behavior profile.
  ///
  /// For each category: weight = completeCount / (completeCount + skipCount).
  /// If no data exists for a category, defaults to 1.0.
  Map<String, double> computeActionWeights(UserBehaviorProfile profile) {
    final weights = <String, double>{};

    // Gather all known categories from both skip and complete maps
    final allCategories = <String>{
      ...profile.actionCategoryCompleteCounts.keys,
      ...profile.actionCategorySkipCounts.keys,
    };

    for (final category in allCategories) {
      final completeCount =
          profile.actionCategoryCompleteCounts[category] ?? 0;
      final skipCount = profile.actionCategorySkipCounts[category] ?? 0;
      final total = completeCount + skipCount;

      if (total == 0) {
        weights[category] = 1.0;
      } else {
        weights[category] = completeCount / total;
      }
    }

    return weights;
  }

  /// Checks whether a recurring pattern exists for the given field
  /// in the last 7 check-ins.
  ///
  /// Returns `true` if any single value appears 3 or more times.
  bool hasRecurringPattern(String fieldName, List<CheckIn> last7CheckIns) {
    final valueCounts = <String, int>{};

    for (final checkIn in last7CheckIns) {
      final value = _extractFieldValue(fieldName, checkIn);
      if (value != null) {
        valueCounts[value] = (valueCounts[value] ?? 0) + 1;
      }
    }

    return valueCounts.values.any((c) => c >= 3);
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Computes the mode for a single field across a list of check-ins.
  ///
  /// The list is assumed to be ordered most-recent-first (index 0 is newest).
  /// Ties are broken by recency: the value that appears most recently among
  /// the tied values wins.
  T? _computeFieldMode<T>(
    List<CheckIn> checkIns,
    T? Function(CheckIn) extractor,
  ) {
    final counts = <T, int>{};
    final recencyIndex = <T, int>{}; // lower index = more recent

    for (var i = 0; i < checkIns.length; i++) {
      final value = extractor(checkIns[i]);
      if (value != null) {
        counts[value] = (counts[value] ?? 0) + 1;
        // Only record the first (most recent) occurrence
        recencyIndex.putIfAbsent(value, () => i);
      }
    }

    if (counts.isEmpty) return null;

    // Find the maximum count
    final maxCount = counts.values.reduce((a, b) => a > b ? a : b);

    // Among values with maxCount, pick the one with the lowest recency index
    T? winner;
    int bestRecency = checkIns.length; // worst possible

    for (final entry in counts.entries) {
      if (entry.value == maxCount) {
        final recency = recencyIndex[entry.key] ?? checkIns.length;
        if (recency < bestRecency) {
          bestRecency = recency;
          winner = entry.key;
        }
      }
    }

    return winner;
  }

  /// Extracts a string representation of a field value from a check-in.
  String? _extractFieldValue(String fieldName, CheckIn checkIn) {
    switch (fieldName) {
      case 'energyScore':
        return checkIn.energyScore?.toString();
      case 'moodState':
        return checkIn.moodState?.name;
      case 'recoveryStatus':
        return checkIn.recoveryStatus?.name;
      case 'availableTime':
        return checkIn.availableTime?.name;
      default:
        return null;
    }
  }
}
