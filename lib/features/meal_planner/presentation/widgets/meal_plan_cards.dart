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

  const DailyNutritionSummaryCard({
    super.key,
    required this.day,
    required this.calorieTarget,
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

  const GroceryListCard({
    super.key,
    required this.list,
    this.onToggle,
    this.onGenerate,
    this.isBuilding = false,
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
              const Icon(Icons.shopping_cart_rounded,
                  color: kMealPlanAccent, size: 20),
              const SizedBox(width: 8),
              Text('Grocery list',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
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

/// Displays a compact 7-day schedule overview.
class WeeklyPlanOverviewCard extends StatelessWidget {
  final MealPlan plan;
  final ValueChanged<int>? onTapDay;

  const WeeklyPlanOverviewCard({super.key, required this.plan, this.onTapDay});

  static const _dayLabels = ['Day 1', 'Day 2', 'Day 3', 'Day 4', 'Day 5',
    'Day 6', 'Day 7'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = plan.days.take(7).toList();
    return NutritionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Weekly overview',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ...List.generate(days.length, (i) {
            final d = days[i];
            return InkWell(
              onTap: onTapDay == null ? null : () => onTapDay!(i),
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
                          i < _dayLabels.length ? _dayLabels[i] : 'Day ${i + 1}',
                          style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: kMealPlanAccent),
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
          }),
        ],
      ),
    );
  }
}
