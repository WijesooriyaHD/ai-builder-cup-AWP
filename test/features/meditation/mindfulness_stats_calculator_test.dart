import 'package:aiwellnesspal/features/meditation/data/mindfulness_stats_calculator.dart';
import 'package:aiwellnesspal/features/meditation/domain/meditation_models.dart';
import 'package:flutter_test/flutter_test.dart';

MeditationSessionRecord _rec({
  required DateTime at,
  SessionType type = SessionType.guided,
  int minutes = 10,
  String title = 'Session',
}) =>
    MeditationSessionRecord(
      id: 'id-${at.microsecondsSinceEpoch}-$type',
      type: type,
      title: title,
      minutes: minutes,
      completedAt: at,
    );

void main() {
  const calc = MindfulnessStatsCalculator();
  final today = DateTime.now();
  DateTime daysAgo(int n) => today.subtract(Duration(days: n));

  group('currentStreak', () {
    test('empty history is zero', () {
      expect(calc.currentStreak([]), 0);
    });

    test('session today counts as a 1-day streak', () {
      expect(calc.currentStreak([_rec(at: today)]), 1);
    });

    test('consecutive days accumulate', () {
      final history = [
        _rec(at: today),
        _rec(at: daysAgo(1)),
        _rec(at: daysAgo(2)),
      ];
      expect(calc.currentStreak(history), 3);
    });

    test('multiple sessions on the same day count once', () {
      final history = [
        _rec(at: today),
        _rec(at: today),
        _rec(at: daysAgo(1)),
      ];
      expect(calc.currentStreak(history), 2);
    });

    test('a gap breaks the streak', () {
      final history = [
        _rec(at: today),
        _rec(at: daysAgo(2)), // missed yesterday
      ];
      expect(calc.currentStreak(history), 1);
    });

    test('streak still valid if last session was yesterday', () {
      final history = [
        _rec(at: daysAgo(1)),
        _rec(at: daysAgo(2)),
      ];
      expect(calc.currentStreak(history), 2);
    });

    test('no streak if last session older than yesterday', () {
      expect(calc.currentStreak([_rec(at: daysAgo(3))]), 0);
    });
  });

  group('stats', () {
    test('totals and weekly minutes', () {
      final history = [
        _rec(at: today, minutes: 10),
        _rec(at: daysAgo(1), minutes: 5),
      ];
      final s = calc.stats(history);
      expect(s.totalSessions, 2);
      expect(s.totalMinutes, 15);
      expect(s.minutesThisWeek, greaterThanOrEqualTo(10));
    });

    test('longestStored is preserved when current streak is smaller', () {
      final s = calc.stats([_rec(at: today)], longestStored: 12);
      expect(s.longestStreak, 12);
      expect(s.currentStreak, 1);
    });
  });

  group('weeklyMinutes', () {
    test('returns 7 buckets with today last', () {
      final history = [_rec(at: today, minutes: 8)];
      final week = calc.weeklyMinutes(history);
      expect(week.length, 7);
      expect(week.last, 8);
    });
  });

  group('minutesByType', () {
    test('aggregates minutes per type', () {
      final history = [
        _rec(at: today, type: SessionType.breathing, minutes: 3),
        _rec(at: today, type: SessionType.breathing, minutes: 2),
        _rec(at: today, type: SessionType.sleep, minutes: 20),
      ];
      final map = calc.minutesByType(history);
      expect(map[SessionType.breathing], 5);
      expect(map[SessionType.sleep], 20);
    });
  });

  group('evaluateAchievements', () {
    test('first session unlocks med_first_session', () {
      final history = [_rec(at: today)];
      final stats = calc.stats(history);
      final unlocked = calc.evaluateAchievements(history, stats);
      expect(unlocked, contains('med_first_session'));
    });

    test('100 total minutes unlocks med_minutes_100', () {
      final history = [_rec(at: today, minutes: 100)];
      final stats = calc.stats(history);
      expect(calc.evaluateAchievements(history, stats),
          contains('med_minutes_100'));
    });

    test('10 breathing sessions unlocks med_breathing_master', () {
      final history = List.generate(
        10,
        (i) => _rec(at: daysAgo(i), type: SessionType.breathing, minutes: 2),
      );
      final stats = calc.stats(history);
      expect(calc.evaluateAchievements(history, stats),
          contains('med_breathing_master'));
    });

    test('4 distinct types unlocks med_explorer', () {
      final history = [
        _rec(at: today, type: SessionType.breathing),
        _rec(at: today, type: SessionType.guided),
        _rec(at: today, type: SessionType.sleep),
        _rec(at: today, type: SessionType.bodyScan),
      ];
      final stats = calc.stats(history);
      expect(
          calc.evaluateAchievements(history, stats), contains('med_explorer'));
    });
  });

  group('newlyUnlocked', () {
    test('returns only achievements not already earned', () {
      final newly = calc.newlyUnlocked(
        {'med_first_session', 'med_minutes_100'},
        {'med_first_session'},
      );
      expect(newly.map((a) => a.id), ['med_minutes_100']);
    });
  });
}
