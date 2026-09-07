import 'calorie_budget_models.dart';

/// Provider-agnostic contract for calorie-budget intelligence.
///
/// Implementations wrap a specific AI backend (e.g. Gemini 2.5 Flash via
/// Firebase Vertex AI) but must always degrade gracefully to a deterministic
/// heuristic so the tool works offline / for free users.
abstract class CalorieBudgetService {
  /// Predicts the likely end-of-day intake and risk given the current day's
  /// [summary] and the hour of day (0–23), plus recent daily intakes for
  /// behavioral context.
  Future<CaloriePrediction> predictEndOfDay(
    CalorieSummary summary, {
    required int hourOfDay,
    List<int> recentIntakes = const [],
  });

  /// Generates a few short, proactive wellness insights/recommendations for the
  /// current [summary] and prediction.
  Future<List<String>> generateInsights(
    CalorieSummary summary,
    CaloriePrediction prediction, {
    required int hourOfDay,
  });
}
