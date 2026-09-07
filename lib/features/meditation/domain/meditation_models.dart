import 'dart:convert';

/// The high-level type of a mindfulness session (drives tracking + analytics).
enum SessionType {
  breathing,
  guided,
  bodyScan,
  stressRelief,
  sleep,
  focus,
}

extension SessionTypeInfo on SessionType {
  String get label {
    switch (this) {
      case SessionType.breathing:
        return 'Breathing';
      case SessionType.guided:
        return 'Guided';
      case SessionType.bodyScan:
        return 'Body Scan';
      case SessionType.stressRelief:
        return 'Stress Relief';
      case SessionType.sleep:
        return 'Sleep';
      case SessionType.focus:
        return 'Focus';
    }
  }

  String get emoji {
    switch (this) {
      case SessionType.breathing:
        return '🌬️';
      case SessionType.guided:
        return '🧘';
      case SessionType.bodyScan:
        return '💆';
      case SessionType.stressRelief:
        return '😌';
      case SessionType.sleep:
        return '😴';
      case SessionType.focus:
        return '🎯';
    }
  }

  static SessionType fromName(String? n) => SessionType.values.firstWhere(
        (t) => t.name == n,
        orElse: () => SessionType.guided,
      );
}

enum Difficulty { beginner, intermediate, advanced }

extension DifficultyInfo on Difficulty {
  String get label {
    switch (this) {
      case Difficulty.beginner:
        return 'Beginner';
      case Difficulty.intermediate:
        return 'Intermediate';
      case Difficulty.advanced:
        return 'Advanced';
    }
  }
}

/// A guided meditation entry in the catalog.
class GuidedMeditation {
  final String id;
  final String title;
  final String description;
  final String category;
  final int durationMinutes;
  final Difficulty difficulty;
  final String emoji;

  const GuidedMeditation({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.durationMinutes,
    required this.difficulty,
    required this.emoji,
  });
}

/// A breathing pattern (each phase in seconds; 0 = skip that phase).
class BreathingPattern {
  final String id;
  final String name;
  final String description;
  final int inhale;
  final int hold1;
  final int exhale;
  final int hold2;

  const BreathingPattern({
    required this.id,
    required this.name,
    required this.description,
    required this.inhale,
    this.hold1 = 0,
    required this.exhale,
    this.hold2 = 0,
  });

  int get cycleSeconds => inhale + hold1 + exhale + hold2;
}

/// A body-scan session type.
class BodyScanSession {
  final String id;
  final String title;
  final int durationMinutes;
  final String description;

  const BodyScanSession({
    required this.id,
    required this.title,
    required this.durationMinutes,
    required this.description,
  });
}

/// A quick stress-relief exercise.
class StressExercise {
  final String id;
  final String title;
  final int durationMinutes;
  final String benefits;
  final List<String> steps;
  final String emoji;

  const StressExercise({
    required this.id,
    required this.title,
    required this.durationMinutes,
    required this.benefits,
    required this.steps,
    required this.emoji,
  });
}

/// A sleep-meditation session in the catalog.
class SleepMeditation {
  final String id;
  final String title;
  final String description;
  final int durationMinutes;
  final String emoji;

  const SleepMeditation({
    required this.id,
    required this.title,
    required this.description,
    required this.durationMinutes,
    required this.emoji,
  });
}

/// A completed (or logged) mindfulness session — the unit of tracking.
class MeditationSessionRecord {
  final String id;
  final SessionType type;
  final String title;
  final int minutes;
  final DateTime completedAt;

  const MeditationSessionRecord({
    required this.id,
    required this.type,
    required this.title,
    required this.minutes,
    required this.completedAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type.name,
        'title': title,
        'minutes': minutes,
        'completedAt': completedAt.toIso8601String(),
      };

  factory MeditationSessionRecord.fromMap(Map<String, dynamic> m) =>
      MeditationSessionRecord(
        id: m['id'] as String? ?? 'm',
        type: SessionTypeInfo.fromName(m['type'] as String?),
        title: m['title'] as String? ?? '',
        minutes: (m['minutes'] as num?)?.round() ?? 0,
        completedAt:
            DateTime.tryParse(m['completedAt']?.toString() ?? '') ??
                DateTime.now(),
      );
}

/// Aggregated mindfulness statistics.
class MindfulnessStats {
  final int currentStreak;
  final int longestStreak;
  final int totalSessions;
  final int totalMinutes;
  final int minutesThisWeek;

  const MindfulnessStats({
    this.currentStreak = 0,
    this.longestStreak = 0,
    this.totalSessions = 0,
    this.totalMinutes = 0,
    this.minutesThisWeek = 0,
  });
}

/// A mindfulness achievement badge.
class MindfulnessAchievement {
  final String id;
  final String title;
  final String description;
  final String emoji;

  const MindfulnessAchievement({
    required this.id,
    required this.title,
    required this.description,
    required this.emoji,
  });
}

/// A local mindfulness reminder.
class MindfulnessReminder {
  final String id;
  final String label; // Morning Mindfulness / Afternoon Reset / ...
  final int hour;
  final int minute;

  /// Weekday numbers (1=Mon … 7=Sun) the reminder is active.
  final List<int> days;
  final bool enabled;

  const MindfulnessReminder({
    required this.id,
    required this.label,
    required this.hour,
    required this.minute,
    this.days = const [1, 2, 3, 4, 5, 6, 7],
    this.enabled = true,
  });

  MindfulnessReminder copyWith({
    String? label,
    int? hour,
    int? minute,
    List<int>? days,
    bool? enabled,
  }) =>
      MindfulnessReminder(
        id: id,
        label: label ?? this.label,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
        days: days ?? this.days,
        enabled: enabled ?? this.enabled,
      );

  String get timeLabel {
    final h = hour % 12 == 0 ? 12 : hour % 12;
    final m = minute.toString().padLeft(2, '0');
    final ap = hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ap';
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'label': label,
        'hour': hour,
        'minute': minute,
        'days': days,
        'enabled': enabled,
      };

  factory MindfulnessReminder.fromMap(Map<String, dynamic> m) =>
      MindfulnessReminder(
        id: m['id'] as String? ?? 'r',
        label: m['label'] as String? ?? 'Reminder',
        hour: (m['hour'] as num?)?.toInt() ?? 8,
        minute: (m['minute'] as num?)?.toInt() ?? 0,
        days: (m['days'] as List<dynamic>?)
                ?.map((e) => (e as num).toInt())
                .toList() ??
            const [1, 2, 3, 4, 5, 6, 7],
        enabled: m['enabled'] as bool? ?? true,
      );

  static String encodeList(List<MindfulnessReminder> list) =>
      jsonEncode(list.map((r) => r.toMap()).toList());

  static List<MindfulnessReminder> decodeList(String s) {
    final raw = jsonDecode(s) as List<dynamic>;
    return raw
        .map((e) => MindfulnessReminder.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }
}
