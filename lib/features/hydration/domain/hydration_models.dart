import 'dart:convert';

/// A single water-intake log entry.
class HydrationEntry {
  final String id;
  final int amountMl;
  final DateTime timestamp;
  final String source; // manual / quick_add / reminder

  const HydrationEntry({
    required this.id,
    required this.amountMl,
    required this.timestamp,
    this.source = 'manual',
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'amountMl': amountMl,
        'timestamp': timestamp.toIso8601String(),
        'source': source,
      };

  factory HydrationEntry.fromMap(Map<String, dynamic> m) => HydrationEntry(
        id: m['id'] as String? ?? 'h',
        amountMl: (m['amountMl'] as num?)?.round() ?? 0,
        timestamp:
            DateTime.tryParse(m['timestamp']?.toString() ?? '') ?? DateTime.now(),
        source: m['source'] as String? ?? 'manual',
      );
}

/// Weather-driven adjustment to the hydration target (future: live weather API).
class WeatherAdjustment {
  final int extraMl;
  final String description; // e.g. "High temperature today"

  const WeatherAdjustment({this.extraMl = 0, this.description = ''});

  bool get isActive => extraMl > 0;

  Map<String, dynamic> toMap() =>
      {'extraMl': extraMl, 'description': description};

  factory WeatherAdjustment.fromMap(Map<String, dynamic> m) => WeatherAdjustment(
        extraMl: (m['extraMl'] as num?)?.round() ?? 0,
        description: m['description'] as String? ?? '',
      );
}

/// The computed hydration goal with its contributing adjustments.
class HydrationGoal {
  final int baseMl;
  final int exerciseAdjustmentMl;
  final int weatherAdjustmentMl;

  const HydrationGoal({
    required this.baseMl,
    this.exerciseAdjustmentMl = 0,
    this.weatherAdjustmentMl = 0,
  });

  int get totalMl => baseMl + exerciseAdjustmentMl + weatherAdjustmentMl;

  Map<String, dynamic> toMap() => {
        'baseMl': baseMl,
        'exerciseAdjustmentMl': exerciseAdjustmentMl,
        'weatherAdjustmentMl': weatherAdjustmentMl,
      };

  factory HydrationGoal.fromMap(Map<String, dynamic> m) => HydrationGoal(
        baseMl: (m['baseMl'] as num?)?.round() ?? 2500,
        exerciseAdjustmentMl:
            (m['exerciseAdjustmentMl'] as num?)?.round() ?? 0,
        weatherAdjustmentMl: (m['weatherAdjustmentMl'] as num?)?.round() ?? 0,
      );
}

enum HydrationRisk { onTrack, behind, ahead }

extension HydrationRiskInfo on HydrationRisk {
  String get label {
    switch (this) {
      case HydrationRisk.onTrack:
        return 'On track';
      case HydrationRisk.behind:
        return 'Behind';
      case HydrationRisk.ahead:
        return 'Ahead';
    }
  }
}

/// Predicted end-of-day hydration outcome.
class HydrationPrediction {
  final int predictedMl; // expected total by end of day
  final int goalMl;
  final HydrationRisk risk;
  final String recommendation;

  const HydrationPrediction({
    required this.predictedMl,
    required this.goalMl,
    required this.risk,
    required this.recommendation,
  });

  int get predictedShortfall => goalMl - predictedMl;
}

/// A behavior-based reminder (not a fixed repeating alarm).
class Reminder {
  final String message;
  final String tone; // gentle / celebratory / nudge

  const Reminder({required this.message, this.tone = 'gentle'});
}

/// 0–100 hydration score with a short explanation.
class HydrationScore {
  final int score;
  final String explanation;

  const HydrationScore({required this.score, required this.explanation});
}

/// A full day's hydration record (Firestore document).
class DailyHydration {
  final String date; // yyyy-MM-dd
  final int goalMl;
  final int consumedMl;
  final int weatherAdjustmentMl;
  final int hydrationScore;
  final List<String> aiInsights;
  final List<HydrationEntry> entries;
  final DateTime createdAt;

  const DailyHydration({
    required this.date,
    required this.goalMl,
    required this.consumedMl,
    this.weatherAdjustmentMl = 0,
    this.hydrationScore = 0,
    this.aiInsights = const [],
    this.entries = const [],
    required this.createdAt,
  });

  int get remainingMl => (goalMl - consumedMl).clamp(0, 999999);

  int get completionPercentage =>
      goalMl <= 0 ? 0 : ((consumedMl / goalMl) * 100).round().clamp(0, 999);

  bool get metGoal => consumedMl >= goalMl;

  Map<String, dynamic> toMap() => {
        'date': date,
        'goalMl': goalMl,
        'consumedMl': consumedMl,
        'remainingMl': remainingMl,
        'completionPercentage': completionPercentage,
        'hydrationScore': hydrationScore,
        'weatherAdjustment': weatherAdjustmentMl,
        'aiInsights': aiInsights,
        'entries': entries.map((e) => e.toMap()).toList(),
        'createdAt': createdAt.toIso8601String(),
      };

  factory DailyHydration.fromMap(Map<String, dynamic> m) => DailyHydration(
        date: m['date'] as String? ?? '',
        goalMl: (m['goalMl'] as num?)?.round() ?? 2500,
        consumedMl: (m['consumedMl'] as num?)?.round() ?? 0,
        weatherAdjustmentMl: (m['weatherAdjustment'] as num?)?.round() ?? 0,
        hydrationScore: (m['hydrationScore'] as num?)?.round() ?? 0,
        aiInsights: (m['aiInsights'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        entries: (m['entries'] as List<dynamic>?)
                ?.map((e) =>
                    HydrationEntry.fromMap(Map<String, dynamic>.from(e as Map)))
                .toList() ??
            const [],
        createdAt: DateTime.tryParse(m['createdAt']?.toString() ?? '') ??
            DateTime.now(),
      );

  String toJson() => jsonEncode(toMap());
  factory DailyHydration.fromJson(String s) =>
      DailyHydration.fromMap(jsonDecode(s) as Map<String, dynamic>);
}

/// A day's data point for weekly/monthly analytics.
class HydrationTrendPoint {
  final DateTime date;
  final int consumedMl;
  final int goalMl;

  const HydrationTrendPoint({
    required this.date,
    required this.consumedMl,
    required this.goalMl,
  });

  bool get metGoal => consumedMl >= goalMl;
  double get completion =>
      goalMl <= 0 ? 0 : (consumedMl / goalMl).clamp(0.0, 1.5);
}

/// Inputs used to compute a personalized hydration goal.
class HydrationProfile {
  final int? age;
  final String? gender;
  final double? weightKg;
  final String activityLevel; // sedentary/light/moderate/active/very_active
  final int exerciseMinutesToday;

  const HydrationProfile({
    this.age,
    this.gender,
    this.weightKg,
    this.activityLevel = 'moderate',
    this.exerciseMinutesToday = 0,
  });
}
