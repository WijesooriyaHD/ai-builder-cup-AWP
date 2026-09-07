import 'sleep_models.dart';

/// Provider-agnostic source of sleep sessions.
///
/// The UI depends only on this interface, so a demo provider can be swapped for
/// Apple HealthKit or Android Health Connect later without touching the
/// dashboard. Implementations must NOT require location; health permissions (if
/// any) are the concern of a concrete health-backed implementation only.
abstract class SleepDataProvider {
  /// Whether this provider currently has access to real data (e.g. health
  /// permission granted). Demo providers return true.
  Future<bool> isAvailable();

  /// Returns the sleep session for the given [date] (the wake-up morning), or
  /// null when no data exists for that day.
  Future<SleepSession?> getSession(DateTime date);

  /// Returns recent sessions (newest first) for the history/trend view.
  Future<List<SleepSession>> getRecentSessions({int days = 7});
}

/// Thrown when sleep data can't be read (e.g. permission denied).
class SleepDataException implements Exception {
  final String message;
  const SleepDataException(this.message);
  @override
  String toString() => 'SleepDataException: $message';
}
