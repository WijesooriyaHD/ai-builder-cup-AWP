import 'package:aiwellnesspal/features/sleep/data/sleep_score_calculator.dart';
import 'package:aiwellnesspal/features/sleep/domain/sleep_models.dart';
import 'package:flutter_test/flutter_test.dart';

SleepSession _session({
  required int rem,
  required int core,
  required int deep,
  int awake = 15,
}) {
  final date = DateTime(2026, 8, 31);
  return SleepSession(
    id: 't',
    date: date,
    bedtime: DateTime(2026, 8, 30, 23),
    wakeTime: DateTime(2026, 8, 31, 7),
    stages: [
      SleepStage(type: SleepStageType.awake, minutes: awake),
      SleepStage(type: SleepStageType.rem, minutes: rem),
      SleepStage(type: SleepStageType.core, minutes: core),
      SleepStage(type: SleepStageType.deep, minutes: deep),
    ],
  );
}

void main() {
  const calc = SleepScoreCalculator();

  group('duration + stage calculations', () {
    test('totalSleepMinutes excludes awake', () {
      final s = _session(rem: 100, core: 260, deep: 60, awake: 20);
      expect(s.totalSleepMinutes, 420);
      expect(s.timeInBedMinutes, 440);
    });

    test('fractionFor computes stage share of sleep', () {
      final s = _session(rem: 100, core: 300, deep: 100, awake: 0);
      expect(s.fractionFor(SleepStageType.deep), closeTo(0.2, 0.001));
    });

    test('formatDuration', () {
      expect(SleepSession.formatDuration(462), '7h 42m');
      expect(SleepSession.formatDuration(45), '45m');
    });

    test('efficiency = asleep / in bed', () {
      final s = _session(rem: 100, core: 260, deep: 60, awake: 60);
      expect(s.efficiency, closeTo(420 / 480, 0.001));
    });
  });

  group('score calculation', () {
    test('a healthy night scores high', () {
      // 7h42m, good deep+rem, few awakenings.
      final s = _session(rem: 102, core: 291, deep: 51, awake: 18);
      final score = calc.calculate(s);
      expect(score.value, greaterThanOrEqualTo(75));
      expect(score.band, anyOf('Good', 'Great'));
    });

    test('a very short night scores lower', () {
      final short = _session(rem: 40, core: 120, deep: 20, awake: 20);
      final good = _session(rem: 102, core: 291, deep: 51, awake: 18);
      expect(calc.calculate(short).value,
          lessThan(calc.calculate(good).value));
    });

    test('score is clamped to 0-100', () {
      final s = _session(rem: 120, core: 300, deep: 60, awake: 0);
      final v = calc.calculate(s).value;
      expect(v, inInclusiveRange(0, 100));
    });

    test('consistency: similar to previous night keeps score up', () {
      final prev = _session(rem: 100, core: 290, deep: 50);
      final same = _session(rem: 100, core: 290, deep: 50);
      final erratic = _session(rem: 40, core: 120, deep: 20);
      final withPrevSame = calc.calculate(same, previous: prev).value;
      final withPrevErratic = calc.calculate(erratic, previous: prev).value;
      expect(withPrevSame, greaterThan(withPrevErratic));
    });

    test('score bands map correctly', () {
      expect(const SleepScore(90).band, 'Great');
      expect(const SleepScore(75).band, 'Good');
      expect(const SleepScore(55).band, 'Fair');
      expect(const SleepScore(30).band, 'Needs work');
    });
  });
}
