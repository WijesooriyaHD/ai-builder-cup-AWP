import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

import '../domain/sleep_data_provider.dart';
import '../domain/sleep_models.dart';

/// [SleepDataProvider] backed by Apple HealthKit (iOS) and Google Health
/// Connect (Android) via the `health` package.
///
/// Reads sleep stage samples and maps them into the app's provider-agnostic
/// [SleepSession] / [SleepStage] models, so the dashboard is unchanged. Health
/// stage names are normalized to the app's four buckets:
///   deep            -> Deep
///   rem             -> REM
///   light / asleep  -> Core
///   awake / in-bed  -> Awake
///
/// Requesting the health permission is the caller's responsibility (via the
/// "Connect Sleep Data" flow) so the prompt appears only when the user asks.
class HealthSleepDataProvider implements SleepDataProvider {
  final Health _health;

  HealthSleepDataProvider({Health? health}) : _health = health ?? Health();

  bool _configured = false;

  /// The sleep-related types we read (never write).
  static const List<HealthDataType> sleepTypes = [
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.SLEEP_AWAKE,
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_REM,
    HealthDataType.SLEEP_LIGHT,
    HealthDataType.SLEEP_IN_BED,
  ];

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  /// Whether the platform's health store is available at all (Health Connect
  /// may be missing on Android).
  Future<bool> isHealthAvailable() async {
    try {
      await _ensureConfigured();
      return await _health.isHealthConnectAvailable();
    } catch (e) {
      debugPrint('❌ HealthSleepDataProvider.isHealthAvailable: $e');
      return false;
    }
  }

  /// Requests READ authorization for the sleep types. Returns true if granted.
  Future<bool> requestPermission() async {
    try {
      await _ensureConfigured();
      final granted = await _health.requestAuthorization(
        sleepTypes,
        permissions:
            List.filled(sleepTypes.length, HealthDataAccess.READ),
      );
      return granted;
    } catch (e) {
      debugPrint('❌ HealthSleepDataProvider.requestPermission: $e');
      return false;
    }
  }

  /// Whether we currently hold read permission (best-effort; HealthKit hides
  /// read grants, so this may be null → treated as "unknown/false").
  Future<bool> hasPermission() async {
    try {
      await _ensureConfigured();
      final has = await _health.hasPermissions(
        sleepTypes,
        permissions:
            List.filled(sleepTypes.length, HealthDataAccess.READ),
      );
      return has ?? false;
    } catch (e) {
      debugPrint('❌ HealthSleepDataProvider.hasPermission: $e');
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // SleepDataProvider
  // ---------------------------------------------------------------------------
  @override
  Future<bool> isAvailable() => hasPermission();

  @override
  Future<SleepSession?> getSession(DateTime date) async {
    final day = DateTime(date.year, date.month, date.day);
    // A "night" for [date] spans roughly noon the previous day → noon of [date]
    // so evening bedtimes are captured with the wake-up morning.
    final start = day.subtract(const Duration(hours: 12));
    final end = day.add(const Duration(hours: 12));
    final points = await _fetch(start, end);
    if (points.isEmpty) return null;
    return _sessionFromPoints(day, points);
  }

  @override
  Future<List<SleepSession>> getRecentSessions({int days = 7}) async {
    final today = DateTime.now();
    final sessions = <SleepSession>[];
    for (var i = 0; i < days; i++) {
      final d = DateTime(today.year, today.month, today.day)
          .subtract(Duration(days: i));
      final s = await getSession(d);
      if (s != null) sessions.add(s);
    }
    return sessions;
  }

  // ---------------------------------------------------------------------------
  // Fetch + mapping
  // ---------------------------------------------------------------------------
  Future<List<HealthDataPoint>> _fetch(DateTime start, DateTime end) async {
    try {
      await _ensureConfigured();
      final raw = await _health.getHealthDataFromTypes(
        types: sleepTypes,
        startTime: start,
        endTime: end,
      );
      return _health.removeDuplicates(raw);
    } catch (e) {
      debugPrint('❌ HealthSleepDataProvider._fetch: $e');
      throw SleepDataException("We couldn't read your sleep data.");
    }
  }

  SleepSession? _sessionFromPoints(DateTime date, List<HealthDataPoint> points) {
    final stageMinutes = <SleepStageType, int>{
      SleepStageType.awake: 0,
      SleepStageType.rem: 0,
      SleepStageType.core: 0,
      SleepStageType.deep: 0,
    };

    DateTime? bedtime;
    DateTime? wakeTime;
    var interruptions = 0;

    for (final p in points) {
      final mins = p.dateTo.difference(p.dateFrom).inMinutes;
      if (mins <= 0) continue;
      final stage = _mapStage(p.type);
      if (stage == null) continue; // e.g. SLEEP_IN_BED, counted only for span

      stageMinutes[stage] = (stageMinutes[stage] ?? 0) + mins;
      if (stage == SleepStageType.awake) interruptions++;

      // Track the full span for bed/wake times.
      if (bedtime == null || p.dateFrom.isBefore(bedtime)) bedtime = p.dateFrom;
      if (wakeTime == null || p.dateTo.isAfter(wakeTime)) wakeTime = p.dateTo;
    }

    final asleep = stageMinutes[SleepStageType.rem]! +
        stageMinutes[SleepStageType.core]! +
        stageMinutes[SleepStageType.deep]!;
    if (asleep <= 0 || bedtime == null || wakeTime == null) {
      return null;
    }

    return SleepSession(
      id: 'health_${date.toIso8601String().split("T").first}',
      date: date,
      bedtime: bedtime,
      wakeTime: wakeTime,
      stages: [
        SleepStage(
            type: SleepStageType.awake,
            minutes: stageMinutes[SleepStageType.awake]!),
        SleepStage(
            type: SleepStageType.rem,
            minutes: stageMinutes[SleepStageType.rem]!),
        SleepStage(
            type: SleepStageType.core,
            minutes: stageMinutes[SleepStageType.core]!),
        SleepStage(
            type: SleepStageType.deep,
            minutes: stageMinutes[SleepStageType.deep]!),
      ],
      interruptions: interruptions,
      source: 'health',
    );
  }

  /// Maps a health sleep type into one of the app's four buckets, or null when
  /// the sample shouldn't count as a stage (e.g. in-bed spans).
  SleepStageType? _mapStage(HealthDataType type) {
    switch (type) {
      case HealthDataType.SLEEP_DEEP:
        return SleepStageType.deep;
      case HealthDataType.SLEEP_REM:
        return SleepStageType.rem;
      case HealthDataType.SLEEP_LIGHT:
      case HealthDataType.SLEEP_ASLEEP:
        return SleepStageType.core;
      case HealthDataType.SLEEP_AWAKE:
        return SleepStageType.awake;
      default:
        return null; // SLEEP_IN_BED / SLEEP_SESSION etc.
    }
  }
}
