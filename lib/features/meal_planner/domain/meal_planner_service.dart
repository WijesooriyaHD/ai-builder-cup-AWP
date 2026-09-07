import 'meal_planner_models.dart';

/// Provider-agnostic contract for generating meal plans.
///
/// Implementations wrap a specific AI backend (e.g. Gemini 2.5 Flash via
/// Firebase Vertex AI, or a future provider). Presentation and repository
/// layers depend only on this interface, so the AI can be swapped freely.
abstract class MealPlannerService {
  /// Generates a single day's plan for [profile] in the given [dietMode].
  Future<MealPlan> generateDailyPlan(
    UserProfile profile, {
    DietMode dietMode = DietMode.standard,
    List<String> include = const [],
    List<String> exclude = const [],
  });

  /// Generates a multi-day plan (7 for weekly, 30 for monthly).
  Future<MealPlan> generatePlan(
    UserProfile profile, {
    PlanType planType = PlanType.daily,
    DietMode dietMode = DietMode.standard,
    List<String> include = const [],
    List<String> exclude = const [],
  });

  /// Returns 3 alternative meals for [current], staying within its nutritional
  /// targets and the plan's [dietMode].
  Future<MealSuggestion> replaceMeal(
    PlannedMeal current, {
    required UserProfile profile,
    required DietMode dietMode,
  });

  /// Generates a categorized grocery list from a plan's meals.
  Future<GroceryList> generateShoppingList(MealPlan plan);
}

/// Thrown when plan generation fails (network/AI/timeout).
class MealPlannerException implements Exception {
  final String message;
  const MealPlannerException(this.message);
  @override
  String toString() => 'MealPlannerException: $message';
}
