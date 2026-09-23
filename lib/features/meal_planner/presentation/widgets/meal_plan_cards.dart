import 'package:flutter/material.dart';

import '../../../nutrition/domain/nutrition_models.dart';
import '../../../nutrition/presentation/widgets/nutrition_cards.dart'
    show NutritionCard;
import '../../domain/meal_planner_models.dart';

/// Accent color for the meal planner module (warm coral-orange).
const Color kMealPlanAccent = Color(0xFFEF8354);

/// Shows today's four meals (breakfast/lunch/dinner/snacks) with per-meal
/// calories, plus optional tap and swap callbacks.
class TodaysMealPlanCard extends StatelessWidget {
  final DayPlan day;
  final ValueChanged<PlannedMeal>? onTapMeal;
  final ValueChanged<PlannedMeal>? onSwapMeal;

  const TodaysMealPlanCard({
    super.key,
    required this.day,
    this.onTapMeal,
    this.onSwapMeal,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meals = [day.breakfast, day.lunch, day.dinner, ...day.snacks];
    return NutritionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.restaurant_menu_rounded,
                  color: kMealPlanAccent, size: 20),
              const SizedBox(width: 8),
              Text("Today's meals",
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
              Text('${day.totalCalories} kcal',
                  style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold, color: kMealPlanAccent)),
            ],
          ),
          const SizedBox(height: 8),
          ...meals.map((m) => _mealRow(context, m)),
        ],
      ),
    );
  }

  Widget _mealRow(BuildContext context, PlannedMeal m) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTapMeal == null ? null : () => onTapMeal!(m),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(m.type.emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(m.type.label.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: kMealPlanAccent,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      )),
                  const SizedBox(height: 2),
                  Text(m.name,
                      style: theme.textTheme.bodyLarge
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  Text(
                    '${m.calories} kcal · P ${m.macros.protein.round()} · '
                    'C ${m.macros.carbs.round()} · F ${m.macros.fat.round()}',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (onSwapMeal != null)
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Swap meal',
                icon: const Icon(Icons.swap_horiz_rounded,
                    color: kMealPlanAccent),
                onPressed: () => onSwapMeal!(m),
              ),
          ],
        ),
      ),
    );
  }
}

/// Displays daily calorie + macro totals against the target.
class DailyNutritionSummaryCard extends StatelessWidget {
  final DayPlan day;
  final int calorieTarget;

  /// Optional replacement title header (used on Home for consistent styling).
  final Widget? titleHeader;

  const DailyNutritionSummaryCard({
    super.key,
    required this.day,
    required this.calorieTarget,
    this.titleHeader,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final macros = day.totalMacros;
    final pct = calorieTarget == 0
        ? 0.0
        : (day.totalCalories / calorieTarget).clamp(0.0, 1.0);
    return NutritionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          titleHeader ??
              Text('Daily nutrition',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('${day.totalCalories}',
                  style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold, color: kMealPlanAccent)),
              const SizedBox(width: 4),
              Text('/ $calorieTarget kcal',
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: pct.toDouble(),
              minHeight: 8,
              backgroundColor: kMealPlanAccent.withOpacity(0.15),
              valueColor: const AlwaysStoppedAnimation(kMealPlanAccent),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _macro(context, 'Protein', '${macros.protein.round()}g',
                  const Color(0xFF4A90D9)),
              _macro(context, 'Carbs', '${macros.carbs.round()}g',
                  const Color(0xFFF0A020)),
              _macro(context, 'Fat', '${macros.fat.round()}g',
                  const Color(0xFFE9506E)),
              _macro(context, 'Fiber', '${macros.fiber.round()}g',
                  const Color(0xFF57B894)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _macro(BuildContext context, String label, String value, Color c) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(value,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold, color: c)),
        Text(label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

/// Displays the categorized grocery list with check-off progress.
class GroceryListCard extends StatelessWidget {
  final GroceryList list;
  final ValueChanged<String>? onToggle;
  final VoidCallback? onGenerate;
  final bool isBuilding;

  /// Optional replacement title header (used on Home for consistent styling).
  final Widget? titleHeader;

  const GroceryListCard({
    super.key,
    required this.list,
    this.onToggle,
    this.onGenerate,
    this.isBuilding = false,
    this.titleHeader,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NutritionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (titleHeader != null)
                Expanded(child: titleHeader!)
              else ...[
                const Icon(Icons.shopping_cart_rounded,
                    color: kMealPlanAccent, size: 20),
                const SizedBox(width: 8),
                Text('Grocery list',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
              ],
              if (!list.isEmpty)
                Text('${list.checkedCount}/${list.items.length}',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 12),
          if (list.isEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Generate a shopping list from this plan.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kMealPlanAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: isBuilding ? null : onGenerate,
                  icon: isBuilding
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.auto_awesome_rounded),
                  label: Text(isBuilding ? 'Building…' : 'Generate list'),
                ),
              ],
            )
          else ...[
            // Progress bar for check-off.
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: list.items.isEmpty
                    ? 0
                    : list.checkedCount / list.items.length,
                minHeight: 6,
                backgroundColor: kMealPlanAccent.withOpacity(0.15),
                valueColor: const AlwaysStoppedAnimation(kMealPlanAccent),
              ),
            ),
            const SizedBox(height: 12),
            ...list.grouped.entries.map((e) => _categoryGroup(context, e.key, e.value)),
          ],
        ],
      ),
    );
  }

  Widget _categoryGroup(
      BuildContext context, GroceryCategory cat, List<GroceryItem> items) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 2),
          child: Row(
            children: [
              Text(cat.emoji, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
              Text(cat.label,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        ...items.map((item) => InkWell(
              onTap: onToggle == null ? null : () => onToggle!(item.name),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      item.checked
                          ? Icons.check_circle_rounded
                          : Icons.circle_outlined,
                      size: 20,
                      color: item.checked
                          ? kMealPlanAccent
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        item.name,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          decoration: item.checked
                              ? TextDecoration.lineThrough
                              : null,
                          color: item.checked
                              ? theme.colorScheme.onSurfaceVariant
                              : null,
                        ),
                      ),
                    ),
                    if (item.quantity != null && item.quantity!.isNotEmpty)
                      Text(item.quantity!,
                          style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
            )),
      ],
    );
  }
}

/// Displays the full multi-day schedule overview for a weekly (7-day) or
/// monthly (30-day) plan.
///
/// Previously this hard-capped at 7 rows and was always titled "Weekly
/// overview", so a 30-day monthly plan showed only its first week. It now
/// renders every day the plan contains, titles itself from [MealPlan.planType],
/// and — for long (monthly) plans — groups days into weeks with running weekly
/// calorie subtotals so the month stays scannable. The list is capped in HEIGHT
/// and scrolls internally, so 30 rows never blow out the page layout.
class WeeklyPlanOverviewCard extends StatelessWidget {
  final MealPlan plan;
  final ValueChanged<int>? onTapDay;

  /// Optional replacement title header (used on Home for consistent styling).
  final Widget? titleHeader;

  const WeeklyPlanOverviewCard({
    super.key,
    required this.plan,
    this.onTapDay,
    this.titleHeader,
  });

  bool get _isMonthly => plan.planType == PlanType.monthly;

  String get _title => _isMonthly ? 'Monthly overview' : 'Weekly overview';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = plan.days;
    if (days.isEmpty) return const SizedBox.shrink();

    return NutritionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: titleHeader ??
                    Text(_title,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
              ),
              // Total-days chip, so the user can see the whole span at a glance
              // (e.g. "30 days" for a monthly plan).
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: kMealPlanAccent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('${days.length} days',
                    style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold, color: kMealPlanAccent)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Cap the height so a 30-day monthly plan scrolls within the card
          // instead of producing an enormous column. A weekly plan (7 rows)
          // sits comfortably under this cap and won't scroll.
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: SingleChildScrollView(
              child: _isMonthly
                  ? _buildGroupedByWeek(theme, days)
                  : _buildDayList(theme, days, startIndex: 0),
            ),
          ),
        ],
      ),
    );
  }

  /// A flat list of day rows for [days], where row i maps to absolute day
  /// index `startIndex + i` (so tapping opens the correct day in a grouped
  /// monthly view).
  Widget _buildDayList(ThemeData theme, List<DayPlan> days,
      {required int startIndex}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(days.length, (i) {
        final absoluteIndex = startIndex + i;
        return _buildDayRow(theme, days[i], absoluteIndex);
      }),
    );
  }

  /// Groups a monthly plan into weeks (Week 1..5) with a per-week calorie
  /// subtotal header, so 30 days are easy to navigate.
  Widget _buildGroupedByWeek(ThemeData theme, List<DayPlan> days) {
    const perWeek = 7;
    final weekCount = (days.length / perWeek).ceil();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(weekCount, (w) {
        final start = w * perWeek;
        final end = (start + perWeek).clamp(0, days.length);
        final weekDays = days.sublist(start, end);
        final weekCalories =
            weekDays.fold<int>(0, (s, d) => s + d.totalCalories);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(top: w == 0 ? 0 : 12, bottom: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Week ${w + 1}',
                        style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: kMealPlanAccent)),
                  ),
                  Text('$weekCalories kcal',
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            _buildDayList(theme, weekDays, startIndex: start),
          ],
        );
      }),
    );
  }

  Widget _buildDayRow(ThemeData theme, DayPlan d, int index) {
    return InkWell(
      onTap: onTapDay == null ? null : () => onTapDay!(index),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 52,
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: kMealPlanAccent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  'Day ${index + 1}',
                  style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.bold, color: kMealPlanAccent),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '${d.breakfast.name} · ${d.lunch.name} · ${d.dinner.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ),
            const SizedBox(width: 8),
            Text('${d.totalCalories}',
                style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
