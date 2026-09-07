import 'dart:math';

import '../domain/sleep_data_provider.dart';
import '../domain/sleep_models.dart';

/// A realistic DEMO sleep data source used until Apple Health / Health Connect
/// is connected. It lives behind [SleepDataProvider] so swapping in a real
/// health source later requires no UI changes.
///
/// Values are generated deterministically per date (seeded) so the same day
/// always shows the same session — never hardcoded inside widgets.
class DemoSleepDataProvider implements SleepDataProvider {
  const DemoSleepDataProvider();

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<SleepSession?> getSession(DateTime date) async {
    // No data for future dates.
    final today = _dateOnly(DateTime.now());
    final d = _dateOnly(date);
    if (d.isAfter(today)) return null;
    return _generate(d);
  }

  @override
  Future<List<SleepSession>> getRecentSessions({int days = 7}) async {
    final today = _dateOnly(DateTime.now());
    return List.generate(days, (i) {
      final d = today.subtract(Duration(days: i));
      return _generate(d);
    });
  }

  SleepSession _generate(DateTime date) {
    // Seed from the date so a day is stable across rebuilds.
    final seed = date.year * 10000 + date.month * 100 + date.day;
    final rng = Random(seed);

    // Total sleep 6h10m–8h10m.
    final totalSleep = 370 + rng.nextInt(120); // minutes
    final awake = 8 + rng.nextInt(22); // 8–30m

    // Stage split (of total sleep): deep 11–18%, rem 20–27%, rest core.
    final deep = (totalSleep * (0.11 + rng.nextDouble() * 0.07)).round();
    final rem = (totalSleep * (0.20 + rng.nextDouble() * 0.07)).round();
    final core = (totalSleep - deep - rem).clamp(60, totalSleep);

    // Bedtime ~22:30–00:15, wake = bedtime + inBed.
    final bedHour = 22 + rng.nextInt(2);
    final bedMinute = rng.nextInt(60);
    final bedtime = DateTime(
        date.year, date.month, date.day - 1, bedHour, bedMinute);
    final inBed = totalSleep + awake;
    final wakeTime = bedtime.add(Duration(minutes: inBed));

    return SleepSession(
      id: 'demo_${date.toIso8601String().split("T").first}',
      date: date,
      bedtime: bedtime,
      wakeTime: wakeTime,
      stages: [
        SleepStage(type: SleepStageType.awake, minutes: awake),
        SleepStage(type: SleepStageType.rem, minutes: rem),
        SleepStage(type: SleepStageType.core, minutes: core),
        SleepStage(type: SleepStageType.deep, minutes: deep),
      ],
      interruptions: 1 + rng.nextInt(3),
      source: 'demo',
    );
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}
