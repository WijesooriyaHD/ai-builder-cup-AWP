/// Stores a user's behavioral patterns over time for the personalization engine.
///
/// Tracks check-in frequencies, action category preferences, and computed
/// weights used by the AI engine to tailor plan generation and reduce
/// decision fatigue over time.
class UserBehaviorProfile {
  final String userId;
  final int totalCheckIns;

  /// Maps field names to their value frequency counts.
  /// e.g. {'moodState': {'calm': 5, 'stressed': 3}, 'energyScore': {'3': 7}}
  final Map<String, Map<String, int>> fieldValueCounts;

  /// Rolling 14-day skip counts per action category.
  final Map<String, int> actionCategorySkipCounts;

  /// Rolling 14-day completion counts per action category.
  final Map<String, int> actionCategoryCompleteCounts;

  /// Computed frequency multiplier per category used by the AI engine.
  final Map<String, double> actionCategoryWeights;

  /// Categories the user has consistently skipped or deprioritized.
  final List<String> deprioritizedCategories;

  /// Timestamp of the last profile update.
  final DateTime? lastUpdated;

  UserBehaviorProfile({
    required this.userId,
    this.totalCheckIns = 0,
    this.fieldValueCounts = const {},
    this.actionCategorySkipCounts = const {},
    this.actionCategoryCompleteCounts = const {},
    this.actionCategoryWeights = const {},
    this.deprioritizedCategories = const [],
    this.lastUpdated,
  });

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'totalCheckIns': totalCheckIns,
      'fieldValueCounts': fieldValueCounts,
      'actionCategorySkipCounts': actionCategorySkipCounts,
      'actionCategoryCompleteCounts': actionCategoryCompleteCounts,
      'actionCategoryWeights': actionCategoryWeights,
      'deprioritizedCategories': deprioritizedCategories,
      'lastUpdated': lastUpdated?.toIso8601String(),
    };
  }

  factory UserBehaviorProfile.fromMap(Map<String, dynamic> map) {
    return UserBehaviorProfile(
      userId: map['userId'] as String,
      totalCheckIns: map['totalCheckIns'] as int? ?? 0,
      fieldValueCounts: _parseFieldValueCounts(map['fieldValueCounts']),
      actionCategorySkipCounts:
          Map<String, int>.from(map['actionCategorySkipCounts'] ?? {}),
      actionCategoryCompleteCounts:
          Map<String, int>.from(map['actionCategoryCompleteCounts'] ?? {}),
      actionCategoryWeights:
          Map<String, double>.from(
            (map['actionCategoryWeights'] as Map?)?.map(
              (key, value) => MapEntry(key as String, (value as num).toDouble()),
            ) ?? {},
          ),
      deprioritizedCategories:
          List<String>.from(map['deprioritizedCategories'] ?? []),
      lastUpdated: map['lastUpdated'] != null
          ? DateTime.parse(map['lastUpdated'] as String)
          : null,
    );
  }

  /// Parses the nested fieldValueCounts map, handling dynamic Firestore types.
  static Map<String, Map<String, int>> _parseFieldValueCounts(dynamic raw) {
    if (raw == null) return {};
    final outerMap = raw as Map;
    return outerMap.map(
      (key, value) => MapEntry(
        key as String,
        Map<String, int>.from(value as Map),
      ),
    );
  }
}
