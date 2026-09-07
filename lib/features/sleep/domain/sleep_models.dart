import 'dart:convert';

/// The stages of a sleep session.
enum SleepStageType { awake, rem, core, deep }

extension SleepStageTypeInfo on SleepStageType {
  String get label {
    switch (this) {
      case SleepStageType.awake:
        return 'Awake';
      case SleepStageType.rem:
        return 'REM';
      case SleepStageType.core:
        return 'Core';
      case SleepStageType.deep:
        return 'Deep';
    }
  }

  /// A plain-language explanation for the education sheet.
  String get explanation {
    switch (this) {
      case SleepStageType.awake:
        return 'Brief wake-ups during the night. A little is completely normal.';
      case SleepStageType.rem:
        return 'Dreaming sleep that supports memory, learning, and mood.';
      case SleepStageType.core:
        return 'Lighter sleep that makes up most of the night and aids recovery.';
      case SleepStageType.deep:
        return 'The most restorative sleep, important for physical repair.';
    }
  }

  static SleepStageType fromName(String? n) => SleepStageType.values.firstWhere(
        (s) => s.name == n,
        orElse: () => SleepStageType.core,
      );
}

/// Minutes spent in a given sleep stage.
class SleepStage {
  final SleepStageType type;
  final int minutes;

  const SleepStage({required this.type, required this.minutes});

  Map<String, dynamic> toMap() => {'type': type.name, 'minutes': minutes};

  factory SleepStage.fromMap(Map<String, dynamic> m) => SleepStage(
        type: SleepStageTypeInfo.fromName(m['type'] as String?),
        minutes: (m['minutes'] as num?)?.round() ?? 0,
      );
}

/// A single night's sleep session (provider-agnostic).
class SleepSession {
  final String id;

  /// The calendar date the sleep is attributed to (the wake-up morning).
  final DateTime date;
  final DateTime bedtime;
  final DateTime wakeTime;
  final List<SleepStage> stages;

  /// Number of times the user woke during the night.
  final int interruptions;

  /// Where the data came from: 'demo', 'apple_health', 'health_connect', etc.
  final String source;

  const SleepSession({
    required this.id,
    required this.date,
    required this.bedtime,
    required this.wakeTime,
    required this.stages,
    this.interruptions = 0,
    this.source = 'demo',
  });

  /// Total time asleep (excludes the awake stage).
  int get totalSleepMinutes => stages
      .where((s) => s.type != SleepStageType.awake)
      .fold(0, (sum, s) => sum + s.minutes);

  /// Total time in bed (all stages incl. awake).
  int get timeInBedMinutes => stages.fold(0, (sum, s) => sum + s.minutes);

  int minutesFor(SleepStageType type) => stages
      .firstWhere((s) => s.type == type,
          orElse: () => SleepStage(type: type, minutes: 0))
      .minutes;

  /// Fraction of total sleep (0–1) spent in [type] (awake uses time-in-bed).
  double fractionFor(SleepStageType type) {
    final base = type == SleepStageType.awake
        ? timeInBedMinutes
        : totalSleepMinutes;
    if (base <= 0) return 0;
    return (minutesFor(type) / base).clamp(0.0, 1.0);
  }

  /// Sleep efficiency: asleep vs. in bed (0–1).
  double get efficiency {
    if (timeInBedMinutes <= 0) return 0;
    return (totalSleepMinutes / timeInBedMinutes).clamp(0.0, 1.0);
  }

  static String formatDuration(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h <= 0) return '${m}m';
    return '${h}h ${m}m';
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'date': date.toIso8601String(),
        'bedtime': bedtime.toIso8601String(),
        'wakeTime': wakeTime.toIso8601String(),
        'stages': stages.map((s) => s.toMap()).toList(),
        'interruptions': interruptions,
        'source': source,
      };

  factory SleepSession.fromMap(Map<String, dynamic> m) => SleepSession(
        id: m['id'] as String? ?? 's',
        date: DateTime.tryParse(m['date']?.toString() ?? '') ?? DateTime.now(),
        bedtime: DateTime.tryParse(m['bedtime']?.toString() ?? '') ??
            DateTime.now(),
        wakeTime: DateTime.tryParse(m['wakeTime']?.toString() ?? '') ??
            DateTime.now(),
        stages: (m['stages'] as List<dynamic>?)
                ?.map((s) => SleepStage.fromMap(Map<String, dynamic>.from(s as Map)))
                .toList() ??
            const [],
        interruptions: (m['interruptions'] as num?)?.round() ?? 0,
        source: m['source'] as String? ?? 'demo',
      );

  String toJson() => jsonEncode(toMap());
  factory SleepSession.fromJson(String s) =>
      SleepSession.fromMap(jsonDecode(s) as Map<String, dynamic>);
}

/// A computed 0–100 sleep score with a qualitative band.
class SleepScore {
  final int value;

  const SleepScore(this.value);

  String get band {
    if (value >= 85) return 'Great';
    if (value >= 70) return 'Good';
    if (value >= 50) return 'Fair';
    return 'Needs work';
  }

  String get emoji {
    if (value >= 85) return '😊';
    if (value >= 70) return '🙂';
    if (value >= 50) return '😐';
    return '😴';
  }
}

/// The status of a single sleep-influencing factor.
enum FactorStatus { excellent, good, needsAttention, belowTarget, aboveTarget, noData }

extension FactorStatusInfo on FactorStatus {
  String get label {
    switch (this) {
      case FactorStatus.excellent:
        return 'Excellent';
      case FactorStatus.good:
        return 'Good';
      case FactorStatus.needsAttention:
        return 'Needs attention';
      case FactorStatus.belowTarget:
        return 'Below target';
      case FactorStatus.aboveTarget:
        return 'Above target';
      case FactorStatus.noData:
        return 'No data';
    }
  }

  bool get isPositive =>
      this == FactorStatus.excellent || this == FactorStatus.good;
}

/// A wellness behavior that may relate to sleep.
class SleepFactor {
  final String key; // hydration / exercise / dinner_timing / caffeine / screen_time
  final String label;
  final String emoji;
  final FactorStatus status;

  /// The user's actual value, formatted (e.g. "2.4 L", "9:12 PM").
  final String? value;

  /// The optimal range/target text (e.g. "2.0–3.5 L", "before 8:30 PM").
  final String? optimal;

  const SleepFactor({
    required this.key,
    required this.label,
    required this.emoji,
    required this.status,
    this.value,
    this.optimal,
  });
}

/// The AI (or heuristic) narrative insight about a night's sleep.
class SleepInsight {
  final String summary; // "What happened"
  final List<String> contributingFactors; // "Why"
  final String confidence; // low / medium / high
  final SleepRecommendation recommendation; // "What to do tonight"

  const SleepInsight({
    required this.summary,
    this.contributingFactors = const [],
    this.confidence = 'medium',
    required this.recommendation,
  });
}

/// A specific, actionable recommendation the user can add to their routine.
class SleepRecommendation {
  final String title; // short, e.g. "Dinner before 8:30 PM"
  final String detail; // one sentence of context

  const SleepRecommendation({required this.title, required this.detail});
}

/// A compact point for the sleep-history trend.
class SleepHistoryPoint {
  final DateTime date;
  final int totalSleepMinutes;
  final int score;

  const SleepHistoryPoint({
    required this.date,
    required this.totalSleepMinutes,
    required this.score,
  });
}

/// Structured, privacy-safe context sent to the AI. Contains NO identifiers.
class SleepAnalysisRequest {
  final int sleepMinutes;
  final int score;
  final Map<String, int> stageMinutes; // stage name -> minutes
  final int? previousSleepMinutes;
  final List<SleepFactor> factors;

  const SleepAnalysisRequest({
    required this.sleepMinutes,
    required this.score,
    required this.stageMinutes,
    this.previousSleepMinutes,
    this.factors = const [],
  });

  Map<String, dynamic> toContext() => {
        'sleepMinutes': sleepMinutes,
        'score': score,
        'stages': stageMinutes,
        if (previousSleepMinutes != null)
          'previousSleepMinutes': previousSleepMinutes,
        'factors': factors
            .map((f) => {
                  'name': f.key,
                  'status': f.status.name,
                  if (f.value != null) 'value': f.value,
                  if (f.optimal != null) 'optimal': f.optimal,
                })
            .toList(),
      };
}
