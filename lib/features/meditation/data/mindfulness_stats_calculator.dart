import '../domain/meditation_catalog.dart';
import '../domain/meditation_models.dart';

/// Pure, testable computations over session history: stats, streaks, and
/// achievement unlocking. No I/O — the repository/state handle persistence.
class MindfulnessStatsCalculator {
  const MindfulnessStatsCalculator();

  /// Computes aggregate stats. [longestStored] lets a previously-recorded
  /// longest streak survive a currently-broken one.
  MindfulnessStats stats(
    List<MeditationSessionRecord> history, {
    int longestStored = 0,
  }) {
    final totalSessions = history.length;
    final totalMinutes = history.fold<int>(0, (s, r) => s + r.minutes);

    final now = DateTime.now();
    final weekStart = _dateOnly(now).subtract(Duration(days: now.weekday - 1));
    final minutesThisWeek = history
        .where((r) => !_dateOnly(r.completedAt).isBefore(weekStart))
        .fold<int>(0, (s, r) => s + r.minutes);

    final current = currentStreak(history);
    final longest = current > longestStored ? current : longestStored;

    return MindfulnessStats(
      currentStreak: current,
      longestStreak: longest,
      totalSessions: totalSessions,
      totalMinutes: totalMinutes,
      minutesThisWeek: minutesThisWeek,
    );
  }

  /// Consecutive-day streak ending today or yesterday.
  int currentStreak(List<MeditationSessionRecord> history) {
    if (history.isEmpty) return 0;
    final days = history.map((r) => _dateOnly(r.completedAt)).toSet();
    final today = _dateOnly(DateTime.now());

    // Streak counts only if there's a session today or yesterday.
    DateTime cursor;
    if (days.contains(today)) {
      cursor = today;
    } else if (days.contains(today.subtract(const Duration(days: 1)))) {
      cursor = today.subtract(const Duration(days: 1));
    } else {
      return 0;
    }

    var streak = 0;
    while (days.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  /// Minutes practiced per day for the last 7 days (oldest → newest).
  List<int> weeklyMinutes(List<MeditationSessionRecord> history) {
    final today = _dateOnly(DateTime.now());
    return List.generate(7, (i) {
      final day = today.subtract(Duration(days: 6 - i));
      return history
          .where((r) => _dateOnly(r.completedAt) == day)
          .fold<int>(0, (s, r) => s + r.minutes);
    });
  }

  /// Minutes per session type (for the "session types" chart).
  Map<SessionType, int> minutesByType(List<MeditationSessionRecord> history) {
    final map = <SessionType, int>{};
    for (final r in history) {
      map[r.type] = (map[r.type] ?? 0) + r.minutes;
    }
    return map;
  }

  /// Evaluates which achievement ids should be unlocked given [history] +
  /// [stats]. Returns the full set (union with anything already unlocked is the
  /// caller's job).
  Set<String> evaluateAchievements(
    List<MeditationSessionRecord> history,
    MindfulnessStats stats,
  ) {
    final unlocked = <String>{};
    if (stats.totalSessions >= 1) unlocked.add('med_first_session');
    if (stats.longestStreak >= 7) unlocked.add('med_streak_7');
    if (stats.longestStreak >= 30) unlocked.add('med_streak_30');
    if (stats.totalMinutes >= 100) unlocked.add('med_minutes_100');

    final breathingCount =
        history.where((r) => r.type == SessionType.breathing).length;
    if (breathingCount >= 10) unlocked.add('med_breathing_master');

    final distinctTypes = history.map((r) => r.type).toSet().length;
    if (distinctTypes >= 4) unlocked.add('med_explorer');

    if (stats.totalSessions >= 50) unlocked.add('med_champion');
    return unlocked;
  }

  /// Which of the [candidate] achievements are newly unlocked vs [existing].
  List<MindfulnessAchievement> newlyUnlocked(
    Set<String> candidate,
    Set<String> existing,
  ) {
    final newIds = candidate.difference(existing);
    return MeditationCatalog.achievements
        .where((a) => newIds.contains(a.id))
        .toList();
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}
