import 'package:aiwellnesspal/features/sleep/data/sleep_factors_analyzer.dart';
import 'package:aiwellnesspal/features/sleep/domain/sleep_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const analyzer = SleepFactorsAnalyzer();

  SleepFactor factor(List<SleepFactor> fs, String key) =>
      fs.firstWhere((f) => f.key == key);

  test('no data → noData status for each factor', () {
    final fs = analyzer.analyze(const SleepFactorInputs());
    expect(factor(fs, 'hydration').status, FactorStatus.noData);
    expect(factor(fs, 'exercise').status, FactorStatus.noData);
    expect(factor(fs, 'dinner_timing').status, FactorStatus.noData);
    expect(factor(fs, 'caffeine').status, FactorStatus.noData);
  });

  test('hydration within range → good, below → belowTarget', () {
    final good = analyzer.analyze(const SleepFactorInputs(hydrationMl: 2400));
    expect(factor(good, 'hydration').status, FactorStatus.good);
    expect(factor(good, 'hydration').value, '2.4 L');

    final low = analyzer.analyze(const SleepFactorInputs(hydrationMl: 1200));
    expect(factor(low, 'hydration').status, FactorStatus.belowTarget);
  });

  test('exercise in optimal band → excellent, too little → needsAttention', () {
    final ex = analyzer.analyze(const SleepFactorInputs(exerciseMinutes: 42));
    expect(factor(ex, 'exercise').status, FactorStatus.excellent);

    final low = analyzer.analyze(const SleepFactorInputs(exerciseMinutes: 10));
    expect(factor(low, 'exercise').status, FactorStatus.needsAttention);
  });

  test('late dinner → needsAttention; early dinner → good', () {
    final late = analyzer.analyze(SleepFactorInputs(
      dinnerTime: DateTime(2026, 8, 30, 21, 12),
    ));
    expect(factor(late, 'dinner_timing').status, FactorStatus.needsAttention);

    final early = analyzer.analyze(SleepFactorInputs(
      dinnerTime: DateTime(2026, 8, 30, 19, 30),
    ));
    expect(factor(early, 'dinner_timing').status, FactorStatus.good);
  });

  test('heavy dinner (even if early) flags needsAttention', () {
    final heavy = analyzer.analyze(SleepFactorInputs(
      dinnerTime: DateTime(2026, 8, 30, 19, 0),
      dinnerCalories: 1100,
    ));
    expect(factor(heavy, 'dinner_timing').status, FactorStatus.needsAttention);
  });

  test('late caffeine flags needsAttention', () {
    final caf = analyzer.analyze(const SleepFactorInputs(lateCaffeine: true));
    expect(factor(caf, 'caffeine').status, FactorStatus.needsAttention);
    final noCaf =
        analyzer.analyze(const SleepFactorInputs(lateCaffeine: false));
    expect(factor(noCaf, 'caffeine').status, FactorStatus.good);
  });
}
