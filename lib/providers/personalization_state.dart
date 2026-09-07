import 'package:flutter/foundation.dart';

import '../models/check_in.dart';
import '../models/user_behavior_profile.dart';
import '../models/wellness_action.dart';
import '../models/wellness_enums.dart';
import '../services/personalization_service.dart';

/// Provider that manages the user's personalization state.
///
/// Wraps [PersonalizationService] to load/update the [UserBehaviorProfile]
/// and expose the current [PersonalizationTier]. Also provides a plain-language
/// summary of learned preferences for the Settings AI Insights section.
class PersonalizationState extends ChangeNotifier {
  final PersonalizationService _service;

  UserBehaviorProfile? _profile;
  PersonalizationTier _tier = PersonalizationTier.standard;

  /// Creates a [PersonalizationState] with an optional injected service.
  ///
  /// If [service] is not provided, a default [PersonalizationService] is used.
  PersonalizationState({PersonalizationService? service})
      : _service = service ?? PersonalizationService();

  /// The user's current behavior profile, or null if not yet loaded.
  UserBehaviorProfile? get profile => _profile;

  /// The current personalization tier based on check-in count and premium status.
  PersonalizationTier get tier => _tier;

  /// Loads the user's behavior profile from Firestore via [PersonalizationService].
  ///
  /// If the profile does not exist, initializes a default empty profile.
  /// After loading, recalculates the personalization tier.
  Future<void> loadProfile(String userId, {bool isPremium = false}) async {
    final loaded = await _service.loadProfile(userId);
    _profile = loaded ??
        UserBehaviorProfile(
          userId: userId,
          totalCheckIns: 0,
        );
    _tier = _service.computeTier(_profile!.totalCheckIns, isPremium);
    notifyListeners();
  }

  /// Updates the behavior profile with new check-in data and completed actions.
  ///
  /// Increments totalCheckIns, updates field value counts from the check-in,
  /// updates action category completion counts, recalculates action weights
  /// and deprioritized categories, then persists to Firestore.
  Future<void> updateProfile(
    CheckIn checkIn,
    List<WellnessAction> completedActions, {
    bool isPremium = false,
  }) async {
    if (_profile == null) return;

    // Increment total check-ins
    final newTotalCheckIns = _profile!.totalCheckIns + 1;

    // Update field value counts
    final updatedFieldValueCounts =
        Map<String, Map<String, int>>.from(_profile!.fieldValueCounts.map(
      (key, value) => MapEntry(key, Map<String, int>.from(value)),
    ));

    if (checkIn.energyScore != null) {
      final energyCounts = Map<String, int>.from(
          updatedFieldValueCounts['energyScore'] ?? {});
      final key = checkIn.energyScore.toString();
      energyCounts[key] = (energyCounts[key] ?? 0) + 1;
      updatedFieldValueCounts['energyScore'] = energyCounts;
    }

    if (checkIn.moodState != null) {
      final moodCounts = Map<String, int>.from(
          updatedFieldValueCounts['moodState'] ?? {});
      final key = checkIn.moodState!.name;
      moodCounts[key] = (moodCounts[key] ?? 0) + 1;
      updatedFieldValueCounts['moodState'] = moodCounts;
    }

    if (checkIn.recoveryStatus != null) {
      final recoveryCounts = Map<String, int>.from(
          updatedFieldValueCounts['recoveryStatus'] ?? {});
      final key = checkIn.recoveryStatus!.name;
      recoveryCounts[key] = (recoveryCounts[key] ?? 0) + 1;
      updatedFieldValueCounts['recoveryStatus'] = recoveryCounts;
    }

    if (checkIn.availableTime != null) {
      final timeCounts = Map<String, int>.from(
          updatedFieldValueCounts['availableTime'] ?? {});
      final key = checkIn.availableTime!.name;
      timeCounts[key] = (timeCounts[key] ?? 0) + 1;
      updatedFieldValueCounts['availableTime'] = timeCounts;
    }

    // Update action category completion counts
    final updatedCompleteCounts =
        Map<String, int>.from(_profile!.actionCategoryCompleteCounts);
    for (final action in completedActions) {
      final cat = action.category.name;
      updatedCompleteCounts[cat] = (updatedCompleteCounts[cat] ?? 0) + 1;
    }

    // Compute new action weights and deprioritized categories
    final updatedProfile = UserBehaviorProfile(
      userId: _profile!.userId,
      totalCheckIns: newTotalCheckIns,
      fieldValueCounts: updatedFieldValueCounts,
      actionCategorySkipCounts: _profile!.actionCategorySkipCounts,
      actionCategoryCompleteCounts: updatedCompleteCounts,
      actionCategoryWeights: _profile!.actionCategoryWeights,
      deprioritizedCategories: _profile!.deprioritizedCategories,
      lastUpdated: DateTime.now(),
    );

    // Recompute weights
    final newWeights = _service.computeActionWeights(updatedProfile);

    // Determine deprioritized categories: skip count >= 3 in rolling 14-day window
    final deprioritized = <String>[];
    for (final entry in updatedProfile.actionCategorySkipCounts.entries) {
      if (entry.value >= 3) {
        // Only deprioritize if completions haven't restored it
        final completes = updatedCompleteCounts[entry.key] ?? 0;
        if (completes < 3) {
          deprioritized.add(entry.key);
        }
      }
    }

    _profile = UserBehaviorProfile(
      userId: updatedProfile.userId,
      totalCheckIns: newTotalCheckIns,
      fieldValueCounts: updatedFieldValueCounts,
      actionCategorySkipCounts: updatedProfile.actionCategorySkipCounts,
      actionCategoryCompleteCounts: updatedCompleteCounts,
      actionCategoryWeights: newWeights,
      deprioritizedCategories: deprioritized,
      lastUpdated: DateTime.now(),
    );

    _tier = _service.computeTier(newTotalCheckIns, isPremium);
    notifyListeners();

    // Persist to Firestore
    try {
      await _service.updateProfile(_profile!.userId, _profile!);
    } catch (e) {
      debugPrint('PersonalizationState.updateProfile persistence error: $e');
    }
  }

  /// Returns a plain-language summary of the user's learned preferences.
  ///
  /// Used in the Settings AI Insights section. Regenerated each time the
  /// section is opened. Returns a sensible default if no profile data exists.
  String summarizePreferences() {
    if (_profile == null || _profile!.totalCheckIns == 0) {
      return 'Not enough data yet. Complete a few check-ins to see your patterns.';
    }

    final parts = <String>[];

    // Typical energy range
    final energyCounts = _profile!.fieldValueCounts['energyScore'];
    if (energyCounts != null && energyCounts.isNotEmpty) {
      final energyRange = _computeTypicalRange(energyCounts);
      parts.add('Typical energy: $energyRange');
    }

    // Most common mood
    final moodCounts = _profile!.fieldValueCounts['moodState'];
    if (moodCounts != null && moodCounts.isNotEmpty) {
      final topMood = _findMode(moodCounts);
      parts.add('Most common mood: $topMood');
    }

    // Preferred time
    final timeCounts = _profile!.fieldValueCounts['availableTime'];
    if (timeCounts != null && timeCounts.isNotEmpty) {
      final topTime = _findMode(timeCounts);
      final label = _formatTimeRange(topTime);
      parts.add('Preferred time: $label');
    }

    // Deprioritized categories
    if (_profile!.deprioritizedCategories.isNotEmpty) {
      final categories = _profile!.deprioritizedCategories
          .map((c) => c)
          .toList();
      parts.add('Categories you tend to skip: [${categories.join(', ')}]');
    }

    if (parts.isEmpty) {
      return 'Not enough data yet. Complete a few check-ins to see your patterns.';
    }

    return '${parts.join('. ')}.';
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Computes a typical range string from energy score counts.
  ///
  /// Finds the two most common energy scores and formats them as "X-Y"
  /// or just "X" if only one score dominates.
  String _computeTypicalRange(Map<String, int> energyCounts) {
    // Sort entries by count descending
    final sorted = energyCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (sorted.length == 1) {
      return sorted.first.key;
    }

    // Take the top 2 scores that form a range
    final topScores = sorted.take(2).map((e) => int.tryParse(e.key) ?? 0).toList()
      ..sort();

    if (topScores[0] == topScores[1]) {
      return '${topScores[0]}';
    }
    return '${topScores[0]}-${topScores[1]}';
  }

  /// Finds the mode (most frequent value) from a count map.
  String _findMode(Map<String, int> counts) {
    String? mode;
    int maxCount = 0;
    for (final entry in counts.entries) {
      if (entry.value > maxCount) {
        maxCount = entry.value;
        mode = entry.key;
      }
    }
    return mode ?? '';
  }

  /// Formats an AvailableTimeRange enum name into a human-readable string.
  String _formatTimeRange(String enumName) {
    switch (enumName) {
      case 'under10':
        return 'under 10 minutes';
      case 'range10_20':
        return '10-20 minutes';
      case 'range20_40':
        return '20-40 minutes';
      case 'range40_60':
        return '40-60 minutes';
      case 'over60':
        return 'over 60 minutes';
      default:
        return enumName;
    }
  }
}
