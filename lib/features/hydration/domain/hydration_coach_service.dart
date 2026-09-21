import 'hydration_models.dart';

/// Provider-agnostic contract for hydration intelligence.
///
/// Implementations may use an AI backend (e.g. Gemini Flash via Firebase
/// Vertex AI) but MUST degrade gracefully to a deterministic heuristic so the
/// tool works offline / for free users.
abstract class HydrationCoachService {
  /// Computes a personalized daily hydration goal from the [profile] and an
  /// optional [weather] adjustment.
  Future<HydrationGoal> calculateGoal(
    HydrationProfile profile, {
    WeatherAdjustment weather = const WeatherAdjustment(),
  });

  /// Generates short, personalized hydration insights for the day so far.
  ///
  /// [weatherContext] is an optional structured, factual weather map (from the
  /// weather provider) so the AI can give weather-aware coaching without ever
  /// fetching weather itself.
  Future<List<String>> generateInsights({
    required int goalMl,
    required int consumedMl,
    required int hourOfDay,
    required List<HydrationEntry> entries,
    List<HydrationTrendPoint> recent = const [],
    Map<String, dynamic>? weatherContext,
  });

  /// Predicts whether the user will hit their goal by end of day.
  Future<HydrationPrediction> predictCompletion({
    required int goalMl,
    required int consumedMl,
    required int hourOfDay,
  });

  /// Produces behavior-based reminders (not fixed repeating alarms).
  Future<List<Reminder>> generateReminders({
    required int goalMl,
    required int consumedMl,
    required int hourOfDay,
    required List<HydrationEntry> entries,
  });
}
