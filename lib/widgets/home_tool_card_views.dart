import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features/calorie_budget/presentation/calorie_budget_state.dart';
import '../features/calorie_budget/presentation/widgets/calorie_budget_cards.dart';
import '../features/hydration/presentation/hydration_state.dart';
import '../features/hydration/presentation/widgets/hydration_cards.dart';
import '../features/meal_planner/domain/meal_planner_models.dart';
import '../features/meal_planner/presentation/meal_planner_state.dart';
import '../features/nutrition/domain/nutrition_models.dart' show MealTypeInfo;
import '../features/nutrition/presentation/nutrition_state.dart';
import '../features/nutrition/presentation/widgets/nutrition_cards.dart';
import '../models/period_data.dart';
import '../models/weight_data.dart';
import '../providers/app_state.dart';
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
    default:
      return null;
  }
  // Each card renders its own title header INSIDE its NutritionCard, so no
  // outer wrapper is needed here.
  return body;
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
