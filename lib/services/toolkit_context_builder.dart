import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../features/nutrition/presentation/nutrition_state.dart';
import '../features/hydration/presentation/hydration_state.dart';
import '../features/sleep/presentation/sleep_state.dart';
import '../features/meditation/presentation/meditation_state.dart';
import '../features/calorie_budget/presentation/calorie_budget_state.dart';
import '../features/habit_builder/presentation/habit_builder_state.dart';

/// Builds a concise, summarized "Life Toolkit" context string for the AI
/// Today's Plan — PREMIUM ONLY.
///
/// This is intentionally a caller-side helper (invoked from screens where the
/// tool providers are in scope) because [WellnessPlanState] has no provider
/// access. It reads each tool's cheap summary getters (no heavy computation),
/// includes only signals that meaningfully help planning, and returns `null`
/// for Free users or when there is nothing useful to add.
///
/// Privacy: only summarized/structured signals are included — never raw logs
/// or unnecessary private data (per the Premium data-privacy requirement).
class ToolkitContextBuilder {
  /// Returns a Premium Life-Toolkit context string, or `null` when the user is
  /// not Premium or no meaningful data is available. Safe to call anywhere a
  /// [BuildContext] with the app providers is in scope.
  static String? build(BuildContext context) {
    final appState = context.read<AppState>();

    // HARD GATE: Free users get NO toolkit data in the AI request. The data is
    // excluded BEFORE the prompt is built — never sent-then-ignored.
    if (!appState.isPro) return null;

    final lines = <String>[];

    // --- Sleep: adjust intensity/recovery based on last night ---
    try {
      final sleep = context.read<SleepState>();
      final session = sleep.session;
      if (session != null && session.totalSleepMinutes > 0) {
        final hrs = (session.totalSleepMinutes / 60).toStringAsFixed(1);
        final scoreVal = sleep.score?.value;
        final scoreText = scoreVal != null ? ', sleep score $scoreVal/100' : '';
        lines.add('Sleep: about $hrs h last night$scoreText.');
        if (session.totalSleepMinutes < 360) {
          lines.add(
              'Sleep was on the low side — prefer gentle, restorative options '
              'and reduce unnecessary intensity.');
        }
      }
    } catch (_) {/* provider not available/loaded — skip */}

    // --- Hydration: nudge a water break / light movement if behind ---
    try {
      final hydration = context.read<HydrationState>();
      if (hydration.goalMl > 0 && hydration.consumedMl > 0) {
        final pct = hydration.completionPercentage;
        lines.add('Hydration: at $pct% of today\'s goal '
            '(${hydration.remainingMl} ml remaining).');
        if (pct < 60) {
          lines.add(
              'Hydration is behind target — a hydration break or light '
              'movement + water could help.');
        }
      }
    } catch (_) {}

    // --- Nutrition / energy support ---
    try {
      final nutrition = context.read<NutritionState>();
      if (nutrition.todaysTotals.mealCount > 0) {
        lines.add('Nutrition: ${nutrition.caloriesRemaining} kcal remaining '
            'against goal, ${nutrition.todaysTotals.mealCount} meals logged.');
      }
    } catch (_) {}

    // --- Calorie budget ---
    try {
      final calorie = context.read<CalorieBudgetState>();
      if (calorie.dailyBudget > 0 && calorie.consumed > 0) {
        lines.add('Calorie budget: ${calorie.remaining} kcal remaining '
            '(goal: ${calorie.goalMode.name}).');
      }
    } catch (_) {}

    // --- Meditation / mindfulness ---
    try {
      final meditation = context.read<MeditationState>();
      final stats = meditation.stats;
      if (stats.minutesThisWeek > 0 || stats.currentStreak > 0) {
        lines.add('Mindfulness: ${stats.minutesThisWeek} min this week, '
            '${stats.currentStreak}-day streak.');
      }
    } catch (_) {}

    // --- Habit builder: reinforce active habits ---
    try {
      final habits = context.read<HabitBuilderState>();
      final todays = habits.todaysHabits;
      if (todays.isNotEmpty) {
        lines.add(
            'Habits: ${habits.completedTodayCount}/${todays.length} of today\'s '
            'habits done. Reinforce active habits where it fits naturally.');
      }
    } catch (_) {}

    if (lines.isEmpty) return null;
    return lines.join('\n');
  }
}
