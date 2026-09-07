import 'dart:convert';

/// Which wellness tool this habit is linked to.
enum HabitTool {
  nutrition,
  mealPlanner,
  calorieBudget,
  hydration,
  sleep,
  meditation,
  periodTracker,
  weightTracker,
  mindfulTravel,
  custom,
}

extension HabitToolInfo on HabitTool {
  String get label {
    switch (this) {
      case HabitTool.nutrition:
        return 'Nutrition Coach';
      case HabitTool.mealPlanner:
        return 'Meal Planner';
      case HabitTool.calorieBudget:
        return 'Calorie Budget';
      case HabitTool.hydration:
        return 'Hydration Coach';
      case HabitTool.sleep:
        return 'Sleep Coach';
      case HabitTool.meditation:
        return 'Meditation Pal';
      case HabitTool.periodTracker:
        return 'Period Tracker';
      case HabitTool.weightTracker:
        return 'Body Weight';
      case HabitTool.mindfulTravel:
        return 'Mindful Travel';
      case HabitTool.custom:
        return 'Custom';
    }
  }

  String get emoji {
    switch (this) {
      case HabitTool.nutrition:
        return '🥗';
      case HabitTool.mealPlanner:
        return '🍽️';
      case HabitTool.calorieBudget:
        return '🔥';
      case HabitTool.hydration:
        return '💧';
      case HabitTool.sleep:
        return '🌙';
      case HabitTool.meditation:
        return '🧘';
      case HabitTool.periodTracker:
        return '🌸';
      case HabitTool.weightTracker:
        return '⚖️';
      case HabitTool.mindfulTravel:
        return '✈️';
      case HabitTool.custom:
        return '⭐';
    }
  }
}

/// How often the habit repeats.
enum HabitFrequency { daily, weekdays, weekends, custom }

extension HabitFrequencyLabel on HabitFrequency {
  String get label {
    switch (this) {
      case HabitFrequency.daily:
        return 'Every day';
      case HabitFrequency.weekdays:
        return 'Weekdays';
      case HabitFrequency.weekends:
        return 'Weekends';
      case HabitFrequency.custom:
        return 'Custom days';
    }
  }
}

/// A single user habit. Immutable value — mutations return new instances.
class Habit {
  final String id;
  final String title;
  final String? description;
  final HabitTool tool;
  final HabitFrequency frequency;

  /// ISO weekday numbers (1=Mon … 7=Sun) active for this habit.
  final List<int> activeDays;

  /// Target value (e.g. 8000 for steps, 2.5 for litres). Null = binary done/not.
  final double? targetValue;
  final String? targetUnit; // "steps", "litres", "mins", "kcal", …

  final bool isActive;

  /// Optional daily reminder time (local). Null = no reminder set.
  final int? reminderHour;
  final int? reminderMinute;

  /// Map of "yyyy-MM-dd" → value (or 1.0 for binary). Completion log.
  final Map<String, double> log;

  const Habit({
    required this.id,
    required this.title,
    this.description,
    required this.tool,
    this.frequency = HabitFrequency.daily,
    this.activeDays = const [1, 2, 3, 4, 5, 6, 7],
    this.targetValue,
    this.targetUnit,
    this.isActive = true,
    this.reminderHour,
    this.reminderMinute,
    this.log = const {},
  });

  /// Whether a reminder time is configured.
  bool get hasReminder => reminderHour != null && reminderMinute != null;

  /// The reminder time formatted as "h:mm AM/PM", or null.
  String? get reminderLabel {
    if (!hasReminder) return null;
    final h = reminderHour!;
    final m = reminderMinute!;
    final period = h >= 12 ? 'PM' : 'AM';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:${m.toString().padLeft(2, '0')} $period';
  }

  // ---------------------------------------------------------------------------
  // Computed helpers
  // ---------------------------------------------------------------------------

  String get _todayKey {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-'
        '${n.day.toString().padLeft(2, '0')}';
  }

  bool get isCompletedToday => log.containsKey(_todayKey);

  double get todayProgress => log[_todayKey] ?? 0.0;

  /// Streak = consecutive days with a log entry up to and including today.
  int get currentStreak {
    var streak = 0;
    final today = DateTime.now();
    for (var i = 0; i < 365; i++) {
      final d = today.subtract(Duration(days: i));
      final key = '${d.year}-${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
      if (log.containsKey(key)) {
        streak++;
      } else {
        break;
      }
    }
    return streak;
  }

  /// Whether this habit is scheduled for today.
  bool get isScheduledToday {
    switch (frequency) {
      case HabitFrequency.daily:
        return true;
      case HabitFrequency.weekdays:
        return DateTime.now().weekday <= 5;
      case HabitFrequency.weekends:
        return DateTime.now().weekday >= 6;
      case HabitFrequency.custom:
        return activeDays.contains(DateTime.now().weekday);
    }
  }

  Habit copyWith({
    String? title,
    String? description,
    HabitTool? tool,
    HabitFrequency? frequency,
    List<int>? activeDays,
    double? targetValue,
    String? targetUnit,
    bool? isActive,
    int? reminderHour,
    int? reminderMinute,
    bool clearReminder = false,
    Map<String, double>? log,
  }) =>
      Habit(
        id: id,
        title: title ?? this.title,
        description: description ?? this.description,
        tool: tool ?? this.tool,
        frequency: frequency ?? this.frequency,
        activeDays: activeDays ?? this.activeDays,
        targetValue: targetValue ?? this.targetValue,
        targetUnit: targetUnit ?? this.targetUnit,
        isActive: isActive ?? this.isActive,
        reminderHour:
            clearReminder ? null : (reminderHour ?? this.reminderHour),
        reminderMinute:
            clearReminder ? null : (reminderMinute ?? this.reminderMinute),
        log: log ?? this.log,
      );

  // ---------------------------------------------------------------------------
  // Serialisation
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'description': description,
        'tool': tool.name,
        'frequency': frequency.name,
        'activeDays': activeDays,
        'targetValue': targetValue,
        'targetUnit': targetUnit,
        'isActive': isActive,
        'reminderHour': reminderHour,
        'reminderMinute': reminderMinute,
        'log': log.map((k, v) => MapEntry(k, v)),
      };

  factory Habit.fromMap(Map<String, dynamic> m) => Habit(
        id: m['id'] as String? ?? '',
        title: m['title'] as String? ?? '',
        description: m['description'] as String?,
        tool: HabitTool.values.firstWhere(
          (t) => t.name == m['tool'],
          orElse: () => HabitTool.custom,
        ),
        frequency: HabitFrequency.values.firstWhere(
          (f) => f.name == m['frequency'],
          orElse: () => HabitFrequency.daily,
        ),
        activeDays: List<int>.from(m['activeDays'] ?? [1, 2, 3, 4, 5, 6, 7]),
        targetValue: (m['targetValue'] as num?)?.toDouble(),
        targetUnit: m['targetUnit'] as String?,
        isActive: m['isActive'] as bool? ?? true,
        reminderHour: (m['reminderHour'] as num?)?.toInt(),
        reminderMinute: (m['reminderMinute'] as num?)?.toInt(),
        log: (m['log'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, (v as num).toDouble()),
        ),
      );

  static String encodeList(List<Habit> habits) =>
      jsonEncode(habits.map((h) => h.toMap()).toList());

  static List<Habit> decodeList(String s) {
    final raw = jsonDecode(s) as List<dynamic>;
    return raw
        .map((e) => Habit.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }
}
