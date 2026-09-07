import '../domain/sleep_models.dart';

/// Privacy-safe, decoupled inputs the analyzer needs from other tools. The
/// SleepState populates these from HydrationState / NutritionState /
/// CalorieBudgetState so this analyzer never imports those modules directly.
class SleepFactorInputs {
  /// Water consumed on the day before the night (ml). Null = no data.
  final int? hydrationMl;
  final int? hydrationGoalMl;

  /// Exercise minutes on the day before the night. Null = no data.
  final int? exerciseMinutes;

  /// The last meal's logged time the evening before. Null = no data.
  final DateTime? dinnerTime;

  /// The last meal's calories (to flag heavy late meals). Null = no data.
  final int? dinnerCalories;

  /// Whether caffeine was likely consumed late (heuristic from meal names).
  final bool? lateCaffeine;

  const SleepFactorInputs({
    this.hydrationMl,
    this.hydrationGoalMl,
    this.exerciseMinutes,
    this.dinnerTime,
    this.dinnerCalories,
    this.lateCaffeine,
  });
}

/// Evaluates sleep-influencing factors into [SleepFactor]s with statuses,
/// actual values, and optimal ranges. Pure and testable.
class SleepFactorsAnalyzer {
  const SleepFactorsAnalyzer();

  // Configurable thresholds (no magic numbers scattered in the UI).
  static const int _hydrationLowMl = 2000;
  static const int _hydrationHighMl = 3500;
  static const int _exerciseMinMin = 30;
  static const int _exerciseMaxMin = 60;
  static const int _dinnerCutoffHour = 20; // 8:xx
  static const int _dinnerCutoffMinute = 30; // 8:30 PM
  static const int _heavyDinnerCalories = 800;

  List<SleepFactor> analyze(SleepFactorInputs input) {
    return [
      _hydration(input),
      _exercise(input),
      _dinnerTiming(input),
      _caffeine(input),
    ];
  }

  SleepFactor _hydration(SleepFactorInputs i) {
    final ml = i.hydrationMl;
    if (ml == null || ml == 0) {
      return const SleepFactor(
        key: 'hydration',
        label: 'Hydration',
        emoji: '💧',
        status: FactorStatus.noData,
      );
    }
    final FactorStatus status;
    if (ml < _hydrationLowMl) {
      status = FactorStatus.belowTarget;
    } else if (ml > _hydrationHighMl) {
      status = FactorStatus.aboveTarget;
    } else {
      status = FactorStatus.good;
    }
    return SleepFactor(
      key: 'hydration',
      label: 'Hydration',
      emoji: '💧',
      status: status,
      value: '${(ml / 1000).toStringAsFixed(1)} L',
      optimal: '2.0–3.5 L',
    );
  }

  SleepFactor _exercise(SleepFactorInputs i) {
    final min = i.exerciseMinutes;
    if (min == null) {
      return const SleepFactor(
        key: 'exercise',
        label: 'Exercise',
        emoji: '🏃',
        status: FactorStatus.noData,
      );
    }
    final FactorStatus status;
    if (min < _exerciseMinMin) {
      status = FactorStatus.needsAttention;
    } else if (min > _exerciseMaxMin * 2) {
      status = FactorStatus.aboveTarget;
    } else {
      status = min >= _exerciseMinMin && min <= _exerciseMaxMin
          ? FactorStatus.excellent
          : FactorStatus.good;
    }
    return SleepFactor(
      key: 'exercise',
      label: 'Exercise',
      emoji: '🏃',
      status: status,
      value: '$min min',
      optimal: '30–60 min',
    );
  }

  SleepFactor _dinnerTiming(SleepFactorInputs i) {
    final t = i.dinnerTime;
    if (t == null) {
      return const SleepFactor(
        key: 'dinner_timing',
        label: 'Dinner timing',
        emoji: '🍽️',
        status: FactorStatus.noData,
      );
    }
    final late = t.hour > _dinnerCutoffHour ||
        (t.hour == _dinnerCutoffHour && t.minute > _dinnerCutoffMinute);
    final heavy = (i.dinnerCalories ?? 0) >= _heavyDinnerCalories;
    final status = (late || heavy)
        ? FactorStatus.needsAttention
        : FactorStatus.good;
    return SleepFactor(
      key: 'dinner_timing',
      label: 'Dinner timing',
      emoji: '🍽️',
      status: status,
      value: _formatTime(t),
      optimal: 'before 8:30 PM',
    );
  }

  SleepFactor _caffeine(SleepFactorInputs i) {
    final late = i.lateCaffeine;
    if (late == null) {
      return const SleepFactor(
        key: 'caffeine',
        label: 'Caffeine',
        emoji: '☕',
        status: FactorStatus.noData,
      );
    }
    return SleepFactor(
      key: 'caffeine',
      label: 'Caffeine',
      emoji: '☕',
      status: late ? FactorStatus.needsAttention : FactorStatus.good,
      value: late ? 'Late intake' : 'Low',
      optimal: 'none after 2 PM',
    );
  }

  static String _formatTime(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    final ap = t.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ap';
  }
}
