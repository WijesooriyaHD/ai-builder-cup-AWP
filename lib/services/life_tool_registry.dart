import 'package:flutter/material.dart';

// Tool screens (the 9 Life-toolkit destinations, mirroring the
// "Jump to tool" grid in habit_builder_screen.dart).
import '../features/calorie_budget/presentation/calorie_budget_screen.dart';
import '../features/hydration/presentation/hydration_coach_screen.dart';
import '../features/meal_planner/presentation/meal_planner_screen.dart';
import '../features/meditation/presentation/meditation_home_screen.dart';
import '../features/nutrition/presentation/nutrition_coach_screen.dart';
import '../features/sleep/presentation/sleep_coach_screen.dart';
import '../screens/period_tracker_screen.dart';
import '../screens/travel_screen.dart';
import '../screens/weight_tracker_screen.dart';

/// A single Life-toolkit tool that can be surfaced as a home-screen widget.
///
/// [id] is the stable identifier used in widget deep links
/// (`aiwellnesspal://open?homeWidget=1&screen=tool_<id>`) and in the native
/// widget assets. [emoji] and [label] mirror the "Jump to tool" grid, and
/// [builder] returns the destination screen to push when the widget is tapped.
class LifeTool {
  final String id;
  final String emoji;
  final String label;
  final Color color;
  final WidgetBuilder builder;

  const LifeTool({
    required this.id,
    required this.emoji,
    required this.label,
    required this.color,
    required this.builder,
  });
}

/// Central registry of the 9 Life-toolkit tools, in the same order as the
/// "Jump to tool" grid. This is the single source of truth used by the
/// home-widget deep-link handler to open the right tool screen.
const List<LifeTool> kLifeTools = [
  LifeTool(
    id: 'nutrition',
    emoji: '🥗',
    label: 'Nutrition Coach',
    color: Color(0xFF57B894),
    builder: _buildNutrition,
  ),
  LifeTool(
    id: 'meal_planner',
    emoji: '🍽️',
    label: 'Meal Planner',
    color: Color(0xFFEF8354),
    builder: _buildMealPlanner,
  ),
  LifeTool(
    id: 'calorie_budget',
    emoji: '🔥',
    label: 'Calorie Budget',
    color: Color(0xFFF5A623),
    builder: _buildCalorieBudget,
  ),
  LifeTool(
    id: 'hydration',
    emoji: '💧',
    label: 'Hydration Coach',
    color: Color(0xFF3FA9F5),
    builder: _buildHydration,
  ),
  LifeTool(
    id: 'sleep',
    emoji: '🌙',
    label: 'Sleep Coach',
    color: Color(0xFF6C63FF),
    builder: _buildSleep,
  ),
  LifeTool(
    id: 'meditation',
    emoji: '🧘',
    label: 'Meditation Pal',
    color: Color(0xFF9B59B6),
    builder: _buildMeditation,
  ),
  LifeTool(
    id: 'period_tracker',
    emoji: '🌸',
    label: 'Period Tracker',
    color: Color(0xFFE9506E),
    builder: _buildPeriodTracker,
  ),
  LifeTool(
    id: 'weight_tracker',
    emoji: '⚖️',
    label: 'Body Weight',
    color: Color(0xFF2ECC71),
    builder: _buildWeightTracker,
  ),
  LifeTool(
    id: 'mindful_travel',
    emoji: '✈️',
    label: 'Mindful Travel',
    color: Color(0xFF3A7BD5),
    builder: _buildTravel,
  ),
];

/// Looks up a [LifeTool] by its [id], or null if unknown.
LifeTool? lifeToolById(String id) {
  for (final t in kLifeTools) {
    if (t.id == id) return t;
  }
  return null;
}

// Top-level builders (const-compatible tear-offs for the registry).
Widget _buildNutrition(BuildContext _) => const NutritionCoachScreen();
Widget _buildMealPlanner(BuildContext _) => const MealPlannerScreen();
Widget _buildCalorieBudget(BuildContext _) => const CalorieBudgetScreen();
Widget _buildHydration(BuildContext _) => const HydrationCoachScreen();
Widget _buildSleep(BuildContext _) => const SleepCoachEntry();
Widget _buildMeditation(BuildContext _) => const MeditationHomeScreen();
Widget _buildPeriodTracker(BuildContext _) => const PeriodTrackerScreen();
Widget _buildWeightTracker(BuildContext _) => const WeightTrackerScreen();
Widget _buildTravel(BuildContext _) => const TravelScreen();
