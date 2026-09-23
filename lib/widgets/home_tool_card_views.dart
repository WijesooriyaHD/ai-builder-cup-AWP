import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features/calorie_budget/presentation/calorie_budget_screen.dart';
import '../features/calorie_budget/presentation/calorie_budget_state.dart';
import '../features/calorie_budget/presentation/widgets/calorie_budget_cards.dart';
import '../features/hydration/presentation/hydration_coach_screen.dart';
import '../features/hydration/presentation/hydration_state.dart';
import '../features/hydration/presentation/widgets/hydration_cards.dart';
import '../features/meal_planner/domain/meal_planner_models.dart';
import '../features/meal_planner/presentation/meal_planner_screen.dart';
import '../features/meal_planner/presentation/meal_planner_state.dart';
import '../features/meal_planner/presentation/widgets/meal_plan_cards.dart'
    show
        DailyNutritionSummaryCard,
        GroceryListCard,
        WeeklyPlanOverviewCard,
        kMealPlanAccent;
import '../features/nutrition/domain/nutrition_models.dart' show MealTypeInfo;
import '../features/nutrition/presentation/nutrition_coach_screen.dart';
import '../features/nutrition/presentation/nutrition_state.dart';
import '../features/nutrition/presentation/widgets/nutrition_cards.dart';
import '../models/period_data.dart';
import '../models/weight_data.dart';
import '../providers/app_state.dart';
import '../screens/period_tracker_screen.dart';
import '../screens/weight_tracker_screen.dart';
import '../services/home_tool_cards_service.dart';

/// Builds the Home-embeddable view for a given tool-card id, watching the
/// relevant provider so it stays live. Returns null when the tool has no data
/// worth showing (the Home screen then skips that card).
Widget? buildHomeToolCard(BuildContext context, String toolCardId) {
  final Widget? body;
  switch (toolCardId) {
    case HomeToolCard.nutrition:
      final s = context.watch<NutritionState>();
      body = DailyProgressCard(
        totals: s.todaysTotals,
        goals: s.goals,
        titleHeader: toolCardTitleHeader(context, HomeToolCard.nutrition),
      );
      break;
    case HomeToolCard.mealPlanner:
      final day = context.watch<MealPlannerState>().todayPlan;
      if (day == null) return null;
      body = _HomeMealCard(day: day);
      break;
    case HomeToolCard.calorieBudget:
      final s = context.watch<CalorieBudgetState>();
      body = CalorieBudgetCard(
        summary: s.summary,
        titleHeader: toolCardTitleHeader(context, HomeToolCard.calorieBudget),
      );
      break;
    case HomeToolCard.hydration:
      final s = context.watch<HydrationState>();
      body = HydrationProgressCard(
        goalMl: s.goalMl,
        consumedMl: s.consumedMl,
        isManualGoal: s.isManualTarget,
        titleHeader: toolCardTitleHeader(context, HomeToolCard.hydration),
      );
      break;
    case HomeToolCard.periodTracker:
      final data = context.watch<AppState>().periodData;
      body = HomePeriodRingCard(data: data);
      break;
    case HomeToolCard.bodyWeight:
      final data = context.watch<AppState>().weightData;
      body = HomeBodyWeightCard(data: data);
      break;

    // ----- Nutrition Coach -----
    case HomeToolCard.nutritionCoach:
      final s = context.watch<NutritionState>();
      body = _HomeInsightsCard(
        toolCardId: HomeToolCard.nutritionCoach,
        accent: kNutritionAccent,
        bullets: s.dailyFeedback,
        emptyText: 'Log a meal to see coaching insights.',
      );
      break;
    case HomeToolCard.nutritionRecentMeals:
      final s = context.watch<NutritionState>();
      final meals = s.recentMeals();
      if (meals.isEmpty) return null;
      body = RecentMealsCard(
        meals: meals,
        titleHeader:
            toolCardTitleHeader(context, HomeToolCard.nutritionRecentMeals),
      );
      break;

    // ----- Meal Planner -----
    case HomeToolCard.mealNutritionSummary:
      final s = context.watch<MealPlannerState>();
      final day = s.todayPlan;
      final plan = s.activePlan;
      if (day == null || plan == null) return null;
      body = DailyNutritionSummaryCard(
        day: day,
        calorieTarget: plan.dailyCalories,
        titleHeader:
            toolCardTitleHeader(context, HomeToolCard.mealNutritionSummary),
      );
      break;
    case HomeToolCard.mealInsights:
      final plan = context.watch<MealPlannerState>().activePlan;
      if (plan == null || plan.aiInsights.isEmpty) return null;
      body = _HomeInsightsCard(
        toolCardId: HomeToolCard.mealInsights,
        accent: kMealPlanAccent,
        bullets: plan.aiInsights,
      );
      break;
    case HomeToolCard.mealWeeklyOverview:
      final plan = context.watch<MealPlannerState>().activePlan;
      if (plan == null ||
          plan.planType == PlanType.daily ||
          plan.days.length <= 1) {
        return null;
      }
      body = WeeklyPlanOverviewCard(
        plan: plan,
        titleHeader:
            toolCardTitleHeader(context, HomeToolCard.mealWeeklyOverview),
      );
      break;
    case HomeToolCard.mealGrocery:
      final plan = context.watch<MealPlannerState>().activePlan;
      if (plan == null) return null;
      body = GroceryListCard(
        list: plan.groceryList,
        // Read-only on Home: no generate/toggle actions.
        titleHeader: toolCardTitleHeader(context, HomeToolCard.mealGrocery),
      );
      break;

    // ----- Calorie Budget -----
    case HomeToolCard.calorieInsight:
      final s = context.watch<CalorieBudgetState>();
      body = AiInsightCard(
        prediction: s.prediction,
        insights: s.insights,
        isAnalyzing: s.isAnalyzing,
        titleHeader: toolCardTitleHeader(context, HomeToolCard.calorieInsight),
      );
      break;
    case HomeToolCard.calorieStreak:
      final s = context.watch<CalorieBudgetState>();
      body = GoalStreakCard(
        currentStreak: s.currentStreak,
        bestStreak: s.bestStreak,
        titleHeader: toolCardTitleHeader(context, HomeToolCard.calorieStreak),
      );
      break;
    case HomeToolCard.calorieTimeline:
      final s = context.watch<CalorieBudgetState>();
      body = DailyTimelineCard(
        events: s.timeline,
        // Read-only on Home: no tap-to-edit.
        titleHeader: toolCardTitleHeader(context, HomeToolCard.calorieTimeline),
      );
      break;
    case HomeToolCard.calorieWeekly:
      final s = context.watch<CalorieBudgetState>();
      body = WeeklyProgressCard(
        points: s.trendPoints,
        titleHeader: toolCardTitleHeader(context, HomeToolCard.calorieWeekly),
      );
      break;

    // ----- Period Tracker -----
    case HomeToolCard.periodPrediction:
      final data = context.watch<AppState>().periodData;
      body = HomePeriodPredictionCard(data: data);
      break;
    case HomeToolCard.periodPhase:
      final data = context.watch<AppState>().periodData;
      body = HomePeriodPhaseCard(data: data);
      break;

    // ----- Hydration Coach -----
    case HomeToolCard.hydrationInsights:
      final s = context.watch<HydrationState>();
      body = SmartInsightsCard(
        prediction: s.prediction,
        insights: s.insights,
        reminders: s.reminders,
        isAnalyzing: s.isAnalyzing,
        titleHeader:
            toolCardTitleHeader(context, HomeToolCard.hydrationInsights),
      );
      break;
    case HomeToolCard.hydrationScore:
      final s = context.watch<HydrationState>();
      body = HydrationScoreCard(
        score: s.score,
        titleHeader: toolCardTitleHeader(context, HomeToolCard.hydrationScore),
      );
      break;
    case HomeToolCard.hydrationStreak:
      final s = context.watch<HydrationState>();
      body = HydrationStreakCard(
        currentStreak: s.currentStreak,
        bestStreak: s.bestStreak,
        titleHeader:
            toolCardTitleHeader(context, HomeToolCard.hydrationStreak),
      );
      break;
    case HomeToolCard.hydrationTimeline:
      final s = context.watch<HydrationState>();
      body = HydrationTimelineCard(
        entries: s.timeline,
        // Read-only on Home: no tap-to-delete.
        titleHeader:
            toolCardTitleHeader(context, HomeToolCard.hydrationTimeline),
      );
      break;
    case HomeToolCard.hydrationWeekly:
      final s = context.watch<HydrationState>();
      body = WeeklyAnalyticsCard(
        points: s.trendPoints,
        titleHeader:
            toolCardTitleHeader(context, HomeToolCard.hydrationWeekly),
      );
      break;

    // ----- Body Weight -----
    case HomeToolCard.bodyWeightChart:
      final data = context.watch<AppState>().weightData;
      body = HomeWeightChartCard(data: data);
      break;
    case HomeToolCard.bodyWeightBmi:
      final data = context.watch<AppState>().weightData;
      body = HomeBmiCard(data: data);
      break;
    case HomeToolCard.bodyWeightHistory:
      final data = context.watch<AppState>().weightData;
      body = HomeWeightHistoryCard(data: data);
      break;

    default:
      return null;
  }
  // Each card renders its own title header INSIDE its NutritionCard, so no
  // outer wrapper is needed here.
  return body;
}

/// The tool screen a Home tool-card belongs to, so a short tap on the card can
/// open its originating Life Tool. Returns null for non-tool ids (default Home
/// cards, which have no tool screen).
Widget? screenForToolCard(String toolCardId) {
  switch (toolCardId) {
    case HomeToolCard.nutrition:
    case HomeToolCard.nutritionCoach:
    case HomeToolCard.nutritionRecentMeals:
      return const NutritionCoachScreen();
    case HomeToolCard.mealPlanner:
    case HomeToolCard.mealNutritionSummary:
    case HomeToolCard.mealInsights:
    case HomeToolCard.mealWeeklyOverview:
    case HomeToolCard.mealGrocery:
      return const MealPlannerScreen();
    case HomeToolCard.calorieBudget:
    case HomeToolCard.calorieInsight:
    case HomeToolCard.calorieStreak:
    case HomeToolCard.calorieTimeline:
    case HomeToolCard.calorieWeekly:
      return const CalorieBudgetScreen();
    case HomeToolCard.periodTracker:
    case HomeToolCard.periodPrediction:
    case HomeToolCard.periodPhase:
      return const PeriodTrackerScreen();
    case HomeToolCard.hydration:
    case HomeToolCard.hydrationInsights:
    case HomeToolCard.hydrationScore:
    case HomeToolCard.hydrationStreak:
    case HomeToolCard.hydrationTimeline:
    case HomeToolCard.hydrationWeekly:
      return const HydrationCoachScreen();
    case HomeToolCard.bodyWeight:
    case HomeToolCard.bodyWeightChart:
    case HomeToolCard.bodyWeightBmi:
    case HomeToolCard.bodyWeightHistory:
      return const WeightTrackerScreen();
    default:
      return null;
  }
}

/// A default-style in-card title header (icon + label) for tool cards on Home.
/// Styling mirrors the built-in Home cards (e.g. "Today's Wellness Focus"):
/// titleSmall / w600 / 70% onSurface, with a 22px primary-colored icon.
///
/// Place this as the first child inside a card's Column, followed by spacing.
Widget toolCardTitleHeader(BuildContext context, String toolCardId) {
  final theme = Theme.of(context);
  return Row(
    children: [
      Icon(HomeToolCard.iconFor(toolCardId),
          color: theme.colorScheme.primary, size: 22),
      const SizedBox(width: 10),
      Text(
        HomeToolCard.titleFor(toolCardId),
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurface.withOpacity(0.7),
        ),
      ),
    ],
  );
}

// ---------------------------------------------------------------------------
// Meal Planner: one meal at a time with up/down arrows
// ---------------------------------------------------------------------------

const Color _mealAccent = Color(0xFFEF8354);

class _HomeMealCard extends StatefulWidget {
  const _HomeMealCard({required this.day});
  final DayPlan day;

  @override
  State<_HomeMealCard> createState() => _HomeMealCardState();
}

class _HomeMealCardState extends State<_HomeMealCard> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meals = widget.day.allMeals;
    if (meals.isEmpty) {
      return NutritionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            toolCardTitleHeader(context, HomeToolCard.mealPlanner),
            const SizedBox(height: 12),
            Text('No meals planned for today yet.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      );
    }
    // Keep the cursor valid if the plan changed underneath us.
    final index = _index.clamp(0, meals.length - 1);
    final m = meals[index];

    return NutritionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: toolCardTitleHeader(context, HomeToolCard.mealPlanner)),
              Text('${index + 1}/${meals.length}',
                  style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(m.type.emoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.type.label.toUpperCase(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: _mealAccent,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        )),
                    const SizedBox(height: 2),
                    Text(m.name,
                        style: theme.textTheme.bodyLarge
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      '${m.calories} kcal · P ${m.macros.protein.round()} · '
                      'C ${m.macros.carbs.round()} · F ${m.macros.fat.round()}',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              // Up / down arrows to cycle through the day's meals.
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _arrow(
                    context,
                    Icons.keyboard_arrow_up_rounded,
                    onTap: index > 0
                        ? () => setState(() => _index = index - 1)
                        : null,
                  ),
                  _arrow(
                    context,
                    Icons.keyboard_arrow_down_rounded,
                    onTap: index < meals.length - 1
                        ? () => setState(() => _index = index + 1)
                        : null,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _arrow(BuildContext context, IconData icon, {VoidCallback? onTap}) {
    final enabled = onTap != null;
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: enabled
              ? _mealAccent.withOpacity(0.12)
              : theme.colorScheme.onSurface.withOpacity(0.04),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon,
            size: 22,
            color: enabled
                ? _mealAccent
                : theme.colorScheme.onSurface.withOpacity(0.25)),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Period Tracker: compact cycle ring (reusable extraction of the screen ring)
// ---------------------------------------------------------------------------

class HomePeriodRingCard extends StatelessWidget {
  const HomePeriodRingCard({super.key, required this.data});
  final PeriodData data;

  static const Color _periodColor = Color(0xFFE9506E);
  static const Color _ovulationColor = Color(0xFF7E57C2);

  Color _phaseColor(CyclePhase phase) {
    switch (phase) {
      case CyclePhase.menstrual:
        return _periodColor;
      case CyclePhase.follicular:
        return const Color(0xFF66BB6A);
      case CyclePhase.ovulation:
        return _ovulationColor;
      case CyclePhase.luteal:
        return const Color(0xFF5C6BC0);
      case CyclePhase.unknown:
        return const Color(0xFF9E9E9E);
    }
  }

  IconData _phaseIcon(CyclePhase phase) {
    switch (phase) {
      case CyclePhase.menstrual:
        return Icons.water_drop_rounded;
      case CyclePhase.follicular:
        return Icons.spa_rounded;
      case CyclePhase.ovulation:
        return Icons.wb_sunny_rounded;
      case CyclePhase.luteal:
        return Icons.nightlight_round;
      case CyclePhase.unknown:
        return Icons.woman_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phase = data.currentPhase;
    final day = data.currentCycleDay;
    final len = data.effectiveCycleLength;
    final progress = (day != null) ? (day / len).clamp(0.0, 1.0) : 0.0;
    final color = _phaseColor(phase);

    return NutritionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          toolCardTitleHeader(context, HomeToolCard.periodTracker),
          const SizedBox(height: 12),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 170,
                  height: 170,
                  child: CustomPaint(
                    painter: _CycleRingPainter(
                      progress: progress.toDouble(),
                      phaseColor: color,
                      trackColor:
                          theme.colorScheme.onSurface.withOpacity(0.08),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_phaseIcon(phase), size: 26, color: color),
                          const SizedBox(height: 4),
                          Text(
                            data.hasData ? 'Day $day' : '—',
                            style: theme.textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            data.hasData ? 'of $len' : 'No data yet',
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('${phase.label} phase',
                      style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 12)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CycleRingPainter extends CustomPainter {
  final double progress;
  final Color phaseColor;
  final Color trackColor;

  _CycleRingPainter({
    required this.progress,
    required this.phaseColor,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - 10;
    const stroke = 13.0;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );

    if (progress > 0) {
      final rect = Rect.fromCircle(center: center, radius: radius);
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        Paint()
          ..color = phaseColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_CycleRingPainter old) =>
      old.progress != progress || old.phaseColor != phaseColor;
}

// ---------------------------------------------------------------------------
// Body Weight: current weight summary (reusable extraction)
// ---------------------------------------------------------------------------

class HomeBodyWeightCard extends StatelessWidget {
  const HomeBodyWeightCard({super.key, required this.data});
  final WeightData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final WeightUnit unit = data.unit;
    final current = data.currentInUnit;
    final change = data.totalChangeKg;

    String changeText;
    Color changeColor;
    IconData changeIcon;
    if (change == null) {
      changeText = 'Log another entry to see your trend';
      changeColor = theme.colorScheme.onSurfaceVariant;
      changeIcon = Icons.trending_flat_rounded;
    } else {
      final inUnit = unit.fromKg(change.abs());
      final rounded = inUnit.toStringAsFixed(1);
      if (change > 0.05) {
        changeText = 'Up $rounded ${unit.label} overall';
        changeColor = const Color(0xFFEF7C4B);
        changeIcon = Icons.trending_up_rounded;
      } else if (change < -0.05) {
        changeText = 'Down $rounded ${unit.label} overall';
        changeColor = const Color(0xFF34A853);
        changeIcon = Icons.trending_down_rounded;
      } else {
        changeText = 'Holding steady';
        changeColor = theme.colorScheme.onSurfaceVariant;
        changeIcon = Icons.trending_flat_rounded;
      }
    }

    return NutritionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          toolCardTitleHeader(context, HomeToolCard.bodyWeight),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                current == null ? '—' : current.toStringAsFixed(1),
                style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface),
              ),
              const SizedBox(width: 6),
              Text(unit.label,
                  style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(changeIcon, size: 18, color: changeColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(changeText,
                    style: theme.textTheme.bodyMedium?.copyWith(
                        color: changeColor, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Generic gradient "insights" card (bulleted list) — used by the Nutrition
// Coach and Meal Planner insight boxes re-created for Home.
// ---------------------------------------------------------------------------

class _HomeInsightsCard extends StatelessWidget {
  const _HomeInsightsCard({
    required this.toolCardId,
    required this.accent,
    required this.bullets,
    this.emptyText,
  });

  final String toolCardId;
  final Color accent;
  final List<String> bullets;
  final String? emptyText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent.withOpacity(0.18), accent.withOpacity(0.05)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accent.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          toolCardTitleHeader(context, toolCardId),
          const SizedBox(height: 12),
          if (bullets.isEmpty)
            Text(emptyText ?? 'No insights yet.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant))
          else
            ...bullets.map(
              (b) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Icon(Icons.circle, size: 6, color: accent),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(b,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(height: 1.4)),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Period Tracker: cycle predictions (next period + ovulation) — re-created
// from the tool screen's private _buildPredictionRow.
// ---------------------------------------------------------------------------

class HomePeriodPredictionCard extends StatelessWidget {
  const HomePeriodPredictionCard({super.key, required this.data});
  final PeriodData data;

  static const Color _periodColor = Color(0xFFE9506E);
  static const Color _ovulationColor = Color(0xFF7E57C2);

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _formatShort(DateTime d) => '${_months[d.month - 1]} ${d.day}';

  @override
  Widget build(BuildContext context) {
    final next = data.nextPeriodDate;
    final until = data.daysUntilNextPeriod;
    final ov = data.ovulationDate;

    String nextValue;
    String nextSub;
    if (next == null) {
      nextValue = '—';
      nextSub = 'Log a period';
    } else if (until != null && until >= 0) {
      nextValue = until == 0 ? 'Today' : 'in $until d';
      nextSub = _formatShort(next);
    } else {
      nextValue = '${-(until ?? 0)}d late';
      nextSub = _formatShort(next);
    }

    return NutritionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          toolCardTitleHeader(context, HomeToolCard.periodPrediction),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _stat(
                  context,
                  icon: Icons.water_drop_rounded,
                  color: _periodColor,
                  label: 'Next period',
                  value: nextValue,
                  sub: nextSub,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _stat(
                  context,
                  icon: Icons.spa_rounded,
                  color: _ovulationColor,
                  label: 'Ovulation',
                  value: ov == null ? '—' : _formatShort(ov),
                  sub: ov == null ? 'Log a period' : 'Est. fertile window',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String label,
    required String value,
    required String sub,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 12),
          Text(label,
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(value,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold, color: color)),
          Text(sub,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Period Tracker: phase insight (wellness tip) — re-created from the tool
// screen's private _buildPhaseInsight.
// ---------------------------------------------------------------------------

class HomePeriodPhaseCard extends StatelessWidget {
  const HomePeriodPhaseCard({super.key, required this.data});
  final PeriodData data;

  Color _phaseColor(CyclePhase phase) {
    switch (phase) {
      case CyclePhase.menstrual:
        return const Color(0xFFE9506E);
      case CyclePhase.follicular:
        return const Color(0xFF66BB6A);
      case CyclePhase.ovulation:
        return const Color(0xFF7E57C2);
      case CyclePhase.luteal:
        return const Color(0xFF5C6BC0);
      case CyclePhase.unknown:
        return const Color(0xFF9E9E9E);
    }
  }

  IconData _phaseIcon(CyclePhase phase) {
    switch (phase) {
      case CyclePhase.menstrual:
        return Icons.water_drop_rounded;
      case CyclePhase.follicular:
        return Icons.spa_rounded;
      case CyclePhase.ovulation:
        return Icons.wb_sunny_rounded;
      case CyclePhase.luteal:
        return Icons.nightlight_round;
      case CyclePhase.unknown:
        return Icons.woman_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phase = data.currentPhase;
    final color = _phaseColor(phase);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.15), color.withOpacity(0.05)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          toolCardTitleHeader(context, HomeToolCard.periodPhase),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_phaseIcon(phase), size: 26, color: color),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.hasData
                          ? '${phase.label} phase tips'
                          : 'Start tracking',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      phase.wellnessTip,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Body Weight: trend chart — re-created from the tool screen's private
// _buildChartCard + _WeightChartPainter.
// ---------------------------------------------------------------------------

class HomeWeightChartCard extends StatelessWidget {
  const HomeWeightChartCard({super.key, required this.data});
  final WeightData data;

  static const Color _accent = Color(0xFF5C9EAD);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = data.sortedEntries;
    return NutritionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          toolCardTitleHeader(context, HomeToolCard.bodyWeightChart),
          const SizedBox(height: 16),
          if (entries.length < 2)
            SizedBox(
              height: 140,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.show_chart_rounded,
                        size: 36,
                        color: theme.colorScheme.onSurfaceVariant
                            .withOpacity(0.5)),
                    const SizedBox(height: 8),
                    Text(
                      'Log at least two entries to see your chart',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else
            SizedBox(
              height: 180,
              child: CustomPaint(
                size: Size.infinite,
                painter: _HomeWeightChartPainter(
                  entries: entries,
                  unit: data.unit,
                  lineColor: _accent,
                  gridColor: theme.colorScheme.onSurface.withOpacity(0.08),
                  labelColor: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HomeWeightChartPainter extends CustomPainter {
  final List<WeightEntry> entries; // sorted oldest → newest
  final WeightUnit unit;
  final Color lineColor;
  final Color gridColor;
  final Color labelColor;

  _HomeWeightChartPainter({
    required this.entries,
    required this.unit,
    required this.lineColor,
    required this.gridColor,
    required this.labelColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (entries.length < 2) return;

    const leftPad = 36.0;
    const bottomPad = 22.0;
    const topPad = 8.0;
    final chartW = size.width - leftPad;
    final chartH = size.height - bottomPad - topPad;

    final values = entries.map((e) => unit.fromKg(e.weightKg)).toList();
    var minV = values.reduce((a, b) => a < b ? a : b);
    var maxV = values.reduce((a, b) => a > b ? a : b);
    if ((maxV - minV).abs() < 0.5) {
      minV -= 1;
      maxV += 1;
    } else {
      final pad = (maxV - minV) * 0.15;
      minV -= pad;
      maxV += pad;
    }
    final range = (maxV - minV).abs() < 0.001 ? 1.0 : (maxV - minV);

    double xFor(int i) =>
        leftPad +
        (entries.length == 1 ? 0 : (chartW * i / (entries.length - 1)));
    double yFor(double v) => topPad + chartH * (1 - (v - minV) / range);

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (var i = 0; i <= 2; i++) {
      final v = minV + range * (i / 2);
      final y = yFor(v);
      canvas.drawLine(Offset(leftPad, y), Offset(size.width, y), gridPaint);
      tp.text = TextSpan(
        text: v.toStringAsFixed(0),
        style: TextStyle(color: labelColor, fontSize: 10),
      );
      tp.layout();
      tp.paint(canvas, Offset(0, y - tp.height / 2));
    }

    final fillPath = Path()..moveTo(xFor(0), yFor(values[0]));
    for (var i = 1; i < values.length; i++) {
      fillPath.lineTo(xFor(i), yFor(values[i]));
    }
    fillPath.lineTo(xFor(values.length - 1), topPad + chartH);
    fillPath.lineTo(xFor(0), topPad + chartH);
    fillPath.close();
    canvas.drawPath(fillPath, Paint()..color = lineColor.withOpacity(0.12));

    final linePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()..moveTo(xFor(0), yFor(values[0]));
    for (var i = 1; i < values.length; i++) {
      path.lineTo(xFor(i), yFor(values[i]));
    }
    canvas.drawPath(path, linePaint);

    final dotPaint = Paint()..color = lineColor;
    final dotInner = Paint()..color = Colors.white;
    for (var i = 0; i < values.length; i++) {
      final o = Offset(xFor(i), yFor(values[i]));
      canvas.drawCircle(o, 4, dotPaint);
      canvas.drawCircle(o, 2, dotInner);
    }

    void drawXLabel(int i, TextAlign align) {
      final d = entries[i].date;
      tp.text = TextSpan(
        text: '${d.month}/${d.day}',
        style: TextStyle(color: labelColor, fontSize: 10),
      );
      tp.layout();
      var x = xFor(i);
      if (align == TextAlign.right) x -= tp.width;
      if (align == TextAlign.center) x -= tp.width / 2;
      x = x.clamp(leftPad, size.width - tp.width);
      tp.paint(canvas, Offset(x, size.height - tp.height));
    }

    drawXLabel(0, TextAlign.left);
    drawXLabel(entries.length - 1, TextAlign.right);
  }

  @override
  bool shouldRepaint(_HomeWeightChartPainter old) =>
      old.entries != entries || old.unit != unit;
}

// ---------------------------------------------------------------------------
// Body Weight: BMI — re-created from the tool screen's private _buildBmiCard
// (read-only on Home: no "Add height/Edit" action).
// ---------------------------------------------------------------------------

class HomeBmiCard extends StatelessWidget {
  const HomeBmiCard({super.key, required this.data});
  final WeightData data;

  Color _bmiColor(BmiCategory c) {
    switch (c) {
      case BmiCategory.underweight:
        return const Color(0xFF4A90D9);
      case BmiCategory.healthy:
        return const Color(0xFF34A853);
      case BmiCategory.overweight:
        return const Color(0xFFF0A020);
      case BmiCategory.obese:
        return const Color(0xFFE9506E);
      case BmiCategory.unknown:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bmi = data.bmi;
    final category = data.bmiCategory;
    final color = _bmiColor(category);

    return NutritionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          toolCardTitleHeader(context, HomeToolCard.bodyWeightBmi),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    bmi == null ? '—' : bmi.toStringAsFixed(1),
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold, color: color),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Body Mass Index',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(
                      category.label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: bmi == null
                            ? theme.colorScheme.onSurfaceVariant
                            : color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Body Weight: history list — re-created from the tool screen's private
// _buildHistory (read-only on Home: no swipe-to-delete). Caps the number of
// rows so a long history doesn't blow out the Home layout.
// ---------------------------------------------------------------------------

class HomeWeightHistoryCard extends StatelessWidget {
  const HomeWeightHistoryCard({super.key, required this.data});
  final WeightData data;

  /// Most-recent entries to show on Home.
  static const int _maxRows = 8;

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _formatDate(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    if (day == today) return 'Today';
    if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return '${_months[d.month - 1]} ${d.day}, ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unit = data.unit;
    final all = data.sortedEntries.reversed.toList(); // newest first
    final entries = all.take(_maxRows).toList();

    return NutritionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          toolCardTitleHeader(context, HomeToolCard.bodyWeightHistory),
          const SizedBox(height: 8),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No entries yet. Log your weight to start your history.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            )
          else ...[
            ...List.generate(entries.length, (i) {
              final e = entries[i];
              // Difference vs the previous (older) entry in the full list.
              final older = (i + 1) < all.length ? all[i + 1] : null;
              final diffKg =
                  older == null ? null : e.weightKg - older.weightKg;
              return _row(context, e, diffKg, unit);
            }),
            if (all.length > entries.length)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '+ ${all.length - entries.length} more in Body Weight',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _row(
      BuildContext context, WeightEntry e, double? diffKg, WeightUnit unit) {
    final theme = Theme.of(context);
    String? diffText;
    Color diffColor = theme.colorScheme.onSurfaceVariant;
    if (diffKg != null && diffKg.abs() > 0.05) {
      final v = unit.fromKg(diffKg.abs()).toStringAsFixed(1);
      diffText = diffKg > 0 ? '+$v' : '-$v';
      diffColor =
          diffKg > 0 ? const Color(0xFFEF7C4B) : const Color(0xFF34A853);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(Icons.monitor_weight_rounded,
              size: 20, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_formatDate(e.date),
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                if (e.note != null && e.note!.isNotEmpty)
                  Text(e.note!,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          if (diffText != null) ...[
            Text(diffText,
                style: TextStyle(
                    color: diffColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 12)),
            const SizedBox(width: 10),
          ],
          Text(
            '${unit.fromKg(e.weightKg).toStringAsFixed(1)} ${unit.label}',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
