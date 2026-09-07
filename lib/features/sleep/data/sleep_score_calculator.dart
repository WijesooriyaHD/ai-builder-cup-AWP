import '../domain/sleep_models.dart';

/// Computes a 0–100 sleep score from a [SleepSession].
///
/// Kept as a standalone, pure, testable unit so the algorithm can be improved
/// independently of the UI. Weights are configurable constants (no magic
/// numbers scattered elsewhere).
class SleepScoreCalculator {
  const SleepScoreCalculator();

  // Component weights (sum = 100).
  static const int _durationWeight = 40;
  static const int _deepRemWeight = 25;
  static const int _efficiencyWeight = 20;
  static const int _consistencyWeight = 15;

  // Duration targets (minutes).
  static const int _idealSleepMin = 420; // 7h
  static const int _idealSleepMax = 540; // 9h

  /// Calculates the score. [previous] is the prior night (for a light
  /// consistency component) and may be null.
  SleepScore calculate(SleepSession session, {SleepSession? previous}) {
    final duration = _durationScore(session.totalSleepMinutes);
    final architecture = _architectureScore(session);
    final efficiency = (session.efficiency * _efficiencyWeight).round();
    final consistency = _consistencyScore(session, previous);

    final total =
        (duration + architecture + efficiency + consistency).clamp(0, 100);
    return SleepScore(total);
  }

  int _durationScore(int minutes) {
    if (minutes >= _idealSleepMin && minutes <= _idealSleepMax) {
      return _durationWeight;
    }
    // Linear falloff outside the ideal band.
    final target = minutes < _idealSleepMin ? _idealSleepMin : _idealSleepMax;
    final diff = (minutes - target).abs();
    final penalty = (diff / 60) * (_durationWeight * 0.25); // 25% per hour off
    return (_durationWeight - penalty).clamp(0, _durationWeight).round();
  }

  /// Rewards a healthy amount of deep + REM sleep (~35–55% combined).
  int _architectureScore(SleepSession s) {
    final asleep = s.totalSleepMinutes;
    if (asleep <= 0) return 0;
    final deepRem =
        s.minutesFor(SleepStageType.deep) + s.minutesFor(SleepStageType.rem);
    final pct = deepRem / asleep;
    if (pct >= 0.35 && pct <= 0.55) return _deepRemWeight;
    final edge = pct < 0.35 ? 0.35 : 0.55;
    final penalty = ((pct - edge).abs() / 0.35) * _deepRemWeight;
    return (_deepRemWeight - penalty).clamp(0, _deepRemWeight).round();
  }

  int _consistencyScore(SleepSession s, SleepSession? previous) {
    if (previous == null) {
      // No baseline — award a neutral partial score.
      return (_consistencyWeight * 0.7).round();
    }
    final diff = (s.totalSleepMinutes - previous.totalSleepMinutes).abs();
    // Within 45 min of the previous night → full marks.
    if (diff <= 45) return _consistencyWeight;
    final penalty = ((diff - 45) / 60) * (_consistencyWeight * 0.5);
    return (_consistencyWeight - penalty)
        .clamp(0, _consistencyWeight)
        .round();
  }
}
