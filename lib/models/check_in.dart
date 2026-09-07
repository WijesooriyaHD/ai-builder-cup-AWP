import 'wellness_enums.dart';

/// Represents a user's daily wellness check-in.
///
/// All scored fields are nullable — the user may skip any question during
/// the check-in flow. Skipped field names are tracked in [skippedFields].
class CheckIn {
  final String id;
  final DateTime date;
  final int? energyScore; // 1–5, nullable if skipped
  final MoodState? moodState;
  final RecoveryStatus? recoveryStatus;
  final AvailableTimeRange? availableTime;
  final List<String> skippedFields;

  CheckIn({
    required this.id,
    required this.date,
    this.energyScore,
    this.moodState,
    this.recoveryStatus,
    this.availableTime,
    this.skippedFields = const [],
  });

  /// Returns a copy of this check-in with the given fields replaced.
  CheckIn copyWith({
    String? id,
    DateTime? date,
    int? energyScore,
    MoodState? moodState,
    RecoveryStatus? recoveryStatus,
    AvailableTimeRange? availableTime,
    List<String>? skippedFields,
  }) {
    return CheckIn(
      id: id ?? this.id,
      date: date ?? this.date,
      energyScore: energyScore ?? this.energyScore,
      moodState: moodState ?? this.moodState,
      recoveryStatus: recoveryStatus ?? this.recoveryStatus,
      availableTime: availableTime ?? this.availableTime,
      skippedFields: skippedFields ?? this.skippedFields,
    );
  }

  /// Maps energy score to a plan-selection tier.
  ///
  /// - null → 2 (balanced default)
  /// - 1–2  → 1 (restorative, no high-intensity)
  /// - 3    → 2 (balanced)
  /// - 4–5  → 3 (active)
  int get energyTier {
    if (energyScore == null) return 2;
    if (energyScore! <= 2) return 1;
    if (energyScore! <= 3) return 2;
    return 3;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'energyScore': energyScore,
      'moodState': moodState?.name,
      'recoveryStatus': recoveryStatus?.name,
      'availableTime': availableTime?.name,
      'skippedFields': skippedFields,
    };
  }

  factory CheckIn.fromMap(Map<String, dynamic> map) {
    return CheckIn(
      id: map['id'] as String,
      date: DateTime.parse(map['date'] as String),
      energyScore: map['energyScore'] as int?,
      moodState: map['moodState'] != null
          ? MoodState.values.firstWhere(
              (e) => e.name == map['moodState'],
              orElse: () => MoodState.calm,
            )
          : null,
      recoveryStatus: map['recoveryStatus'] != null
          ? RecoveryStatus.values.firstWhere(
              (e) => e.name == map['recoveryStatus'],
              orElse: () => RecoveryStatus.wellRested,
            )
          : null,
      availableTime: map['availableTime'] != null
          ? AvailableTimeRange.values.firstWhere(
              (e) => e.name == map['availableTime'],
              orElse: () => AvailableTimeRange.range20_40,
            )
          : null,
      skippedFields: List<String>.from(map['skippedFields'] ?? []),
    );
  }
}
