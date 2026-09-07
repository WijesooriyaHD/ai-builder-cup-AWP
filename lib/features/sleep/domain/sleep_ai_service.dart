import 'sleep_models.dart';

/// Provider-agnostic contract for generating sleep insights.
///
/// Implementations may use Gemini (Firebase Vertex AI) but MUST degrade
/// gracefully to a deterministic heuristic so the dashboard works without AI.
/// Language must stay cautious and non-medical.
abstract class SleepAIService {
  /// Produces a [SleepInsight] from structured, privacy-safe context.
  Future<SleepInsight> analyze(SleepAnalysisRequest request);
}
