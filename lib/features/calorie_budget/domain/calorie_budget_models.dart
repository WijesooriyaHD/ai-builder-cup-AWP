import 'dart:convert';

/// The energy-balance objective driving the daily budget.
enum GoalMode { weightLoss, maintenance, weightGain, muscleBuilding, custom }

extension GoalModeInfo on GoalMode {
  String get label {
    switch (this) {
      case GoalMode.weightLoss:
        return 'Weight Loss';
      case GoalMode.maintenance:
        return 'Maintenance';
      case GoalMode.weightGain:
        return 'Weight Gain';
      case GoalMode.muscleBuilding:
        return 'Muscle Building';
      case GoalMode.custom:
        return 'Custom';
    }
  }

  String get emoji {
    switch (this) {
      case GoalMode.weightLoss:
        return '🔥';
      case GoalMode.maintenance:
        return '⚖️';
      case GoalMode.weightGain:
        return '📈';
      case GoalMode.muscleBuilding:
        return '💪';
      case GoalMode.custom:
        return '⚙️';
    }
  }

  /// Typical daily calorie adjustment applied to a maintenance baseline.
  /// (Used only when deriving a suggested budget; a stored/custom value wins.)
  int get calorieAdjustment {
    switch (this) {
      case GoalMode.weightLoss:
        return -500;
      case GoalMode.maintenance:
        return 0;
      case GoalMode.weightGain:
        return 400;
      case GoalMode.muscleBuilding:
        return 300;
      case GoalMode.custom:
        return 0;
    }
  }

  static GoalMode fromName(String? n) => GoalMode.values.firstWhere(
        (g) => g.name == n,
        orElse: () => GoalMode.maintenance,
      );
}

/// A single burned-calorie exercise entry.
enum ExerciseType {
  walking,
  running,
  cycling,
  yoga,
  pilates,
  strength,
  other,
}

extension ExerciseTypeInfo on ExerciseType {
  String get label {
    switch (this) {
      case ExerciseType.walking:
        return 'Walking';
      case ExerciseType.running:
        return 'Running';
      case ExerciseType.cycling:
        return 'Cycling';
      case ExerciseType.yoga:
        return 'Yoga';
      case ExerciseType.pilates:
        return 'Pilates';
      case ExerciseType.strength:
        return 'Strength Training';
      case ExerciseType.other:
        return 'Other';
    }
  }

  /// Approx calories burned per minute (moderate effort) — used to estimate
  /// burn when the user enters a duration instead of a calorie value.
  double get kcalPerMinute {
    switch (this) {
      case ExerciseType.walking:
        return 4.0;
      case ExerciseType.running:
        return 10.0;
      case ExerciseType.cycling:
        return 8.0;
      case ExerciseType.yoga:
        return 3.0;
      case ExerciseType.pilates:
        return 4.0;
      case ExerciseType.strength:
        return 6.0;
      case ExerciseType.other:
        return 5.0;
    }
  }

  static ExerciseType fromName(String? n) => ExerciseType.values.firstWhere(
        (e) => e.name == n,
        orElse: () => ExerciseType.other,
      );
}

class ExerciseEntry {
  final String id;
  final ExerciseType type;
  final int minutes;
  final int calories; // burned
  final DateTime time;

  const ExerciseEntry({
    required this.id,
    required this.type,
    required this.minutes,
    required this.calories,
    required this.time,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type.name,
        'minutes': minutes,
        'calories': calories,
        'time': time.toIso8601String(),
      };

  factory ExerciseEntry.fromMap(Map<String, dynamic> m) => ExerciseEntry(
        id: m['id'] as String? ?? 'ex',
        type: ExerciseTypeInfo.fromName(m['type'] as String?),
        minutes: (m['minutes'] as num?)?.toInt() ?? 0,
        calories: (m['calories'] as num?)?.round() ?? 0,
        time: DateTime.tryParse(m['time']?.toString() ?? '') ?? DateTime.now(),
      );
}

/// Whether a timeline event adds (food) or subtracts (exercise) calories.
enum CalorieEventKind { food, exercise }

/// A single event on the daily timeline (a meal or an exercise).
class CalorieEvent {
  final String id;
  final CalorieEventKind kind;
  final String label;

  /// Signed calories: positive for food (intake), negative for exercise (burn).
  final int calories;
  final DateTime time;

  const CalorieEvent({
    required this.id,
    required this.kind,
    required this.label,
    required this.calories,
    required this.time,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'kind': kind.name,
        'label': label,
        'calories': calories,
        'time': time.toIso8601String(),
      };

  factory CalorieEvent.fromMap(Map<String, dynamic> m) => CalorieEvent(
        id: m['id'] as String? ?? 'ev',
        kind: (m['kind'] == 'exercise')
            ? CalorieEventKind.exercise
            : CalorieEventKind.food,
        label: m['label'] as String? ?? '',
        calories: (m['calories'] as num?)?.round() ?? 0,
        time: DateTime.tryParse(m['time']?.toString() ?? '') ?? DateTime.now(),
      );
}

/// The four core metrics for a day.
class CalorieSummary {
  final int dailyBudget;
  final int consumed;
  final int burned;
  final GoalMode goalMode;

  const CalorieSummary({
    required this.dailyBudget,
    required this.consumed,
    required this.burned,
    this.goalMode = GoalMode.maintenance,
  });

  /// Remaining = Daily Budget - Consumed + Burned.
  int get remaining => dailyBudget - consumed + burned;

  /// Consumed as a fraction of the (budget + burned) allowance, clamped 0–1.
  double get consumedFraction {
    final allowance = dailyBudget + burned;
    if (allowance <= 0) return 0;
    return (consumed / allowance).clamp(0.0, 1.0);
  }

  bool get isOverBudget => remaining < 0;
}

/// The predicted end-of-day outcome.
enum RiskLevel { low, medium, high }

extension RiskLevelInfo on RiskLevel {
  String get label {
    switch (this) {
      case RiskLevel.low:
        return 'Low';
      case RiskLevel.medium:
        return 'Medium';
      case RiskLevel.high:
        return 'High';
    }
  }

  static RiskLevel fromName(String? n) {
    switch ((n ?? '').toLowerCase()) {
      case 'high':
        return RiskLevel.high;
      case 'medium':
      case 'moderate':
        return RiskLevel.medium;
      default:
        return RiskLevel.low;
    }
  }
}

class CaloriePrediction {
  /// Expected total intake by end of day.
  final int predictedIntake;
  final int dailyGoal;
  final RiskLevel risk;
  final String recommendation;

  const CaloriePrediction({
    required this.predictedIntake,
    required this.dailyGoal,
    required this.risk,
    required this.recommendation,
  });

  int get predictedRemaining => dailyGoal - predictedIntake;

  /// 0–100 probability of hitting the goal (heuristic).
  int get goalProbability {
    final over = predictedIntake - dailyGoal;
    if (over <= 0) return 92;
    if (over < dailyGoal * 0.05) return 70;
    if (over < dailyGoal * 0.12) return 45;
    return 20;
  }
}

/// A full day's calorie budget record (Firestore document).
class DailyCalorieBudget {
  final String date; // yyyy-MM-dd
  final int dailyBudget;
  final int consumed;
  final int burned;
  final int predictedEndOfDay;
  final GoalMode goalMode;
  final List<String> aiInsights;
  final List<CalorieEvent> timeline;
  final DateTime createdAt;

  const DailyCalorieBudget({
    required this.date,
    required this.dailyBudget,
    required this.consumed,
    required this.burned,
    this.predictedEndOfDay = 0,
    this.goalMode = GoalMode.maintenance,
    this.aiInsights = const [],
    this.timeline = const [],
    required this.createdAt,
  });

  int get remaining => dailyBudget - consumed + burned;

  Map<String, dynamic> toMap() => {
        'date': date,
        'dailyBudget': dailyBudget,
        'consumed': consumed,
        'burned': burned,
        'remaining': remaining,
        'predictedEndOfDay': predictedEndOfDay,
        'goalMode': goalMode.name,
        'aiInsights': aiInsights,
        'timeline': timeline.map((e) => e.toMap()).toList(),
        'createdAt': createdAt.toIso8601String(),
      };

  factory DailyCalorieBudget.fromMap(Map<String, dynamic> m) =>
      DailyCalorieBudget(
        date: m['date'] as String? ?? '',
        dailyBudget: (m['dailyBudget'] as num?)?.round() ?? 2000,
        consumed: (m['consumed'] as num?)?.round() ?? 0,
        burned: (m['burned'] as num?)?.round() ?? 0,
        predictedEndOfDay: (m['predictedEndOfDay'] as num?)?.round() ?? 0,
        goalMode: GoalModeInfo.fromName(m['goalMode'] as String?),
        aiInsights: (m['aiInsights'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        timeline: (m['timeline'] as List<dynamic>?)
                ?.map((e) =>
                    CalorieEvent.fromMap(Map<String, dynamic>.from(e as Map)))
                .toList() ??
            const [],
        createdAt: DateTime.tryParse(m['createdAt']?.toString() ?? '') ??
            DateTime.now(),
      );

  String toJson() => jsonEncode(toMap());
  factory DailyCalorieBudget.fromJson(String s) =>
      DailyCalorieBudget.fromMap(jsonDecode(s) as Map<String, dynamic>);
}

/// A single day's data point for trend charts.
class CalorieTrendPoint {
  final DateTime date;
  final int consumed;
  final int burned;
  final int budget;

  const CalorieTrendPoint({
    required this.date,
    required this.consumed,
    required this.burned,
    required this.budget,
  });

  int get remaining => budget - consumed + burned;
  bool get metGoal => consumed <= budget + burned;
}
