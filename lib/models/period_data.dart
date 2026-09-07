import 'dart:convert';

/// The phase of the menstrual cycle a user is currently in.
enum CyclePhase {
  menstrual,
  follicular,
  ovulation,
  luteal,
  unknown,
}

extension CyclePhaseInfo on CyclePhase {
  String get label {
    switch (this) {
      case CyclePhase.menstrual:
        return 'Menstrual';
      case CyclePhase.follicular:
        return 'Follicular';
      case CyclePhase.ovulation:
        return 'Ovulation';
      case CyclePhase.luteal:
        return 'Luteal';
      case CyclePhase.unknown:
        return 'Unknown';
    }
  }

  String get emoji {
    switch (this) {
      case CyclePhase.menstrual:
        return '🌸';
      case CyclePhase.follicular:
        return '🌱';
      case CyclePhase.ovulation:
        return '🌼';
      case CyclePhase.luteal:
        return '🌙';
      case CyclePhase.unknown:
        return '💧';
    }
  }

  /// Short, supportive wellness guidance for this phase (non-clinical).
  String get wellnessTip {
    switch (this) {
      case CyclePhase.menstrual:
        return 'Rest and be gentle with yourself. Light movement, warmth, and '
            'hydration can feel supportive right now.';
      case CyclePhase.follicular:
        return 'Energy tends to rise. A good window for movement, new goals, '
            'and creative focus.';
      case CyclePhase.ovulation:
        return 'You may feel your most energetic and social. Great time for '
            'higher-intensity activity and connection.';
      case CyclePhase.luteal:
        return 'Energy may start to dip. Prioritize steady routines, calming '
            'practices, and good sleep.';
      case CyclePhase.unknown:
        return 'Log a period to get personalized cycle insights.';
    }
  }
}

/// Holds all period-tracking data for a user and derives cycle predictions.
///
/// [loggedPeriodStarts] is a list of dates the user marked as the *first day*
/// of a period. [cycleLength] and [periodLength] are user-configurable and
/// used to predict the next period, fertile window, and current phase.
class PeriodData {
  /// First-day-of-period dates the user has logged (newest handling done here).
  final List<DateTime> loggedPeriodStarts;

  /// Average cycle length in days (first day of one period to the next).
  final int cycleLength;

  /// Average period (bleeding) length in days.
  final int periodLength;

  const PeriodData({
    this.loggedPeriodStarts = const [],
    this.cycleLength = 28,
    this.periodLength = 5,
  });

  /// Sorted (ascending) copy of the logged period start dates, normalized to
  /// midnight so date math is stable.
  List<DateTime> get _sortedStarts {
    final list = loggedPeriodStarts
        .map((d) => DateTime(d.year, d.month, d.day))
        .toList()
      ..sort();
    return list;
  }

  /// The most recent logged period start date, or null if none.
  DateTime? get lastPeriodStart {
    final s = _sortedStarts;
    return s.isEmpty ? null : s.last;
  }

  bool get hasData => loggedPeriodStarts.isNotEmpty;

  /// Estimated average cycle length derived from the user's own logged data
  /// when at least two periods exist; otherwise falls back to [cycleLength].
  int get effectiveCycleLength {
    final s = _sortedStarts;
    if (s.length < 2) return cycleLength;
    final gaps = <int>[];
    for (var i = 1; i < s.length; i++) {
      final diff = s[i].difference(s[i - 1]).inDays;
      // Ignore implausible gaps (mis-logs) outside 15–60 days.
      if (diff >= 15 && diff <= 60) gaps.add(diff);
    }
    if (gaps.isEmpty) return cycleLength;
    final avg = gaps.reduce((a, b) => a + b) / gaps.length;
    return avg.round().clamp(15, 60);
  }

  /// Predicted start date of the next period.
  DateTime? get nextPeriodDate {
    final last = lastPeriodStart;
    if (last == null) return null;
    return last.add(Duration(days: effectiveCycleLength));
  }

  /// Days remaining until the predicted next period (can be negative if late).
  int? get daysUntilNextPeriod {
    final next = nextPeriodDate;
    if (next == null) return null;
    final today = _today();
    return next.difference(today).inDays;
  }

  /// The current day within the cycle (1-based). Day 1 = last period start.
  int? get currentCycleDay {
    final last = lastPeriodStart;
    if (last == null) return null;
    final diff = _today().difference(last).inDays;
    // Wrap within the cycle length so a stale last-start still gives a phase.
    final len = effectiveCycleLength;
    return (diff % len) + 1;
  }

  /// Predicted ovulation date (~14 days before the next period).
  DateTime? get ovulationDate {
    final next = nextPeriodDate;
    if (next == null) return null;
    return next.subtract(const Duration(days: 14));
  }

  /// The fertile window: roughly 5 days before ovulation through 1 day after.
  ({DateTime start, DateTime end})? get fertileWindow {
    final ov = ovulationDate;
    if (ov == null) return null;
    return (
      start: ov.subtract(const Duration(days: 5)),
      end: ov.add(const Duration(days: 1)),
    );
  }

  /// The current cycle phase based on [currentCycleDay].
  CyclePhase get currentPhase {
    final day = currentCycleDay;
    if (day == null) return CyclePhase.unknown;
    final len = effectiveCycleLength;

    // Menstrual: bleeding days.
    if (day <= periodLength) return CyclePhase.menstrual;

    // Ovulation window centered ~14 days before next period.
    final ovDay = len - 14;
    if ((day - ovDay).abs() <= 1) return CyclePhase.ovulation;

    // Follicular: after period, before ovulation.
    if (day < ovDay) return CyclePhase.follicular;

    // Luteal: after ovulation until next period.
    return CyclePhase.luteal;
  }

  /// Whether the given [date] falls on a predicted or logged period day.
  bool isPredictedPeriodDay(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    final next = nextPeriodDate;
    if (next == null) return false;
    for (var i = 0; i < periodLength; i++) {
      if (next.add(Duration(days: i)) == d) return true;
    }
    return false;
  }

  /// Whether [date] falls within the current predicted fertile window.
  bool isFertileDay(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    final fw = fertileWindow;
    if (fw == null) return false;
    return !d.isBefore(fw.start) && !d.isAfter(fw.end);
  }

  /// Whether [date] was logged (or falls within [periodLength] of a logged
  /// start) as an actual period day.
  bool isLoggedPeriodDay(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    for (final start in _sortedStarts) {
      for (var i = 0; i < periodLength; i++) {
        if (start.add(Duration(days: i)) == d) return true;
      }
    }
    return false;
  }

  /// A concise, non-clinical description of cycle context for the AI planner.
  /// Returns null when there is no data to share.
  String? get aiCycleContext {
    if (!hasData) return null;
    final day = currentCycleDay;
    final phase = currentPhase;
    final until = daysUntilNextPeriod;
    final buffer = StringBuffer();
    buffer.write('Menstrual cycle: day ${day ?? '?'} of $effectiveCycleLength, '
        '${phase.label.toLowerCase()} phase.');
    if (until != null) {
      if (until >= 0) {
        buffer.write(' Next period in $until day${until == 1 ? '' : 's'}.');
      } else {
        buffer.write(' Period is ${-until} day${until == -1 ? '' : 's'} late.');
      }
    }
    return buffer.toString();
  }

  PeriodData copyWith({
    List<DateTime>? loggedPeriodStarts,
    int? cycleLength,
    int? periodLength,
  }) {
    return PeriodData(
      loggedPeriodStarts: loggedPeriodStarts ?? this.loggedPeriodStarts,
      cycleLength: cycleLength ?? this.cycleLength,
      periodLength: periodLength ?? this.periodLength,
    );
  }

  /// Adds a logged period start date (de-duplicated), returning a new instance.
  PeriodData addPeriodStart(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    if (loggedPeriodStarts.any((e) =>
        e.year == d.year && e.month == d.month && e.day == d.day)) {
      return this;
    }
    return copyWith(loggedPeriodStarts: [...loggedPeriodStarts, d]);
  }

  /// Removes a logged period start date, returning a new instance.
  PeriodData removePeriodStart(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    return copyWith(
      loggedPeriodStarts: loggedPeriodStarts
          .where((e) =>
              !(e.year == d.year && e.month == d.month && e.day == d.day))
          .toList(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'loggedPeriodStarts':
          _sortedStarts.map((d) => d.toIso8601String()).toList(),
      'cycleLength': cycleLength,
      'periodLength': periodLength,
    };
  }

  String toJson() => jsonEncode(toMap());

  factory PeriodData.fromMap(Map<String, dynamic> map) {
    final rawDates = (map['loggedPeriodStarts'] as List<dynamic>?) ?? const [];
    final dates = rawDates
        .map((e) => DateTime.tryParse(e.toString()))
        .whereType<DateTime>()
        .map((d) => DateTime(d.year, d.month, d.day))
        .toList();
    return PeriodData(
      loggedPeriodStarts: dates,
      cycleLength: (map['cycleLength'] as num?)?.toInt() ?? 28,
      periodLength: (map['periodLength'] as num?)?.toInt() ?? 5,
    );
  }

  factory PeriodData.fromJson(String source) =>
      PeriodData.fromMap(jsonDecode(source) as Map<String, dynamic>);

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }
}
