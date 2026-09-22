import 'package:flutter/material.dart';

import '../../domain/nutrition_models.dart';

/// Shared accent color for the nutrition module (fresh green).
const Color kNutritionAccent = Color(0xFF57B894);

/// A soft, rounded card container matching the app's wellness styling.
class NutritionCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const NutritionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.04) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border:
            Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: child,
    );
  }
}

/// A single macro stat (label + value) used inside summary cards.
class MacroStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const MacroStat(
      {super.key,
      required this.label,
      required this.value,
      required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(value,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 2),
        Text(label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

/// Displays calories + the three primary macros for a meal/day.
class NutritionSummaryCard extends StatelessWidget {
  final String title;
  final int calories;
  final MacroNutrients macros;

  const NutritionSummaryCard({
    super.key,
    this.title = 'Nutrition',
    required this.calories,
    required this.macros,
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
              const Icon(Icons.local_fire_department_rounded,
                  color: kNutritionAccent, size: 20),
              const SizedBox(width: 8),
              Text(title,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
              Text('$calories kcal',
                  style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold, color: kNutritionAccent)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              MacroStat(
                  label: 'Protein',
                  value: '${macros.protein.round()}g',
                  color: const Color(0xFF4A90D9)),
              MacroStat(
                  label: 'Carbs',
                  value: '${macros.carbs.round()}g',
                  color: const Color(0xFFF0A020)),
              MacroStat(
                  label: 'Fat',
                  value: '${macros.fat.round()}g',
                  color: const Color(0xFFE9506E)),
              MacroStat(
                  label: 'Fiber',
                  value: '${macros.fiber.round()}g',
                  color: const Color(0xFF57B894)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Displays the 0–100 food quality score with an AI explanation.
class FoodQualityCard extends StatelessWidget {
  final int score;
  final List<String> insights;

  const FoodQualityCard({
    super.key,
    required this.score,
    this.insights = const [],
  });

  Color get _color {
    if (score >= 80) return const Color(0xFF34A853);
    if (score >= 60) return const Color(0xFF57B894);
    if (score >= 40) return const Color(0xFFF0A020);
    return const Color(0xFFE9506E);
  }

  String get _label {
    if (score >= 80) return 'Excellent';
    if (score >= 60) return 'Good';
    if (score >= 40) return 'Fair';
    return 'Needs balance';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NutritionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 64,
                height: 64,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 64,
                      height: 64,
                      child: CircularProgressIndicator(
                        value: score / 100,
                        strokeWidth: 6,
                        backgroundColor: _color.withOpacity(0.15),
                        valueColor: AlwaysStoppedAnimation(_color),
                      ),
                    ),
                    Text('$score',
                        style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold, color: _color)),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Food Quality Score',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text('$_label · $score/100',
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: _color, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
          if (insights.isNotEmpty) ...[
            const SizedBox(height: 16),
            ...insights.map(
              (i) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.auto_awesome_rounded,
                        size: 16, color: _color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(i,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(height: 1.35)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Horizontal list of recent meals (image + name + calories).
class RecentMealsCard extends StatelessWidget {
  final List<Meal> meals;
  final ValueChanged<Meal>? onTapMeal;

  const RecentMealsCard({super.key, required this.meals, this.onTapMeal});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NutritionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Recent meals',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          if (meals.isEmpty)
            Text('No meals logged yet.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant))
          else
            SizedBox(
              height: 128,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: meals.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, i) {
                  final m = meals[i];
                  return GestureDetector(
                    onTap: onTapMeal == null ? null : () => onTapMeal!(m),
                    child: SizedBox(
                      width: 110,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _mealThumb(context, m),
                          const SizedBox(height: 6),
                          Text(m.mealName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(fontWeight: FontWeight.w600)),
                          Text('${m.calories} kcal',
                              style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _mealThumb(BuildContext context, Meal m) {
    final radius = BorderRadius.circular(16);
    if (m.imageUrl != null && m.imageUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: radius,
        child: Image.network(
          m.imageUrl!,
          width: 110,
          height: 80,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder(context, m, radius),
        ),
      );
    }
    return _placeholder(context, m, radius);
  }

  Widget _placeholder(BuildContext context, Meal m, BorderRadius radius) {
    return Container(
      width: 110,
      height: 80,
      decoration: BoxDecoration(
        color: kNutritionAccent.withOpacity(0.12),
        borderRadius: radius,
      ),
      child: Center(
        child: Text(m.mealType.emoji, style: const TextStyle(fontSize: 28)),
      ),
    );
  }
}

/// Shows calories consumed / remaining and macro progress toward daily goals.
class DailyProgressCard extends StatelessWidget {
  final DailyTotals totals;
  final NutritionGoals goals;

  /// Optional replacement title header rendered inside the card. When provided
  /// (e.g. on the Home screen), it replaces the card's default "Today's
  /// progress" title so the styling matches the other Home cards.
  final Widget? titleHeader;

  const DailyProgressCard({
    super.key,
    required this.totals,
    required this.goals,
    this.titleHeader,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remaining = (goals.calories - totals.calories);
    final calPct = goals.calories == 0
        ? 0.0
        : (totals.calories / goals.calories).clamp(0.0, 1.0);

    return NutritionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          titleHeader ??
              Text("Today's progress",
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _bigStat(context, '${totals.calories}', 'consumed',
                  kNutritionAccent),
              const SizedBox(width: 24),
              _bigStat(
                context,
                remaining >= 0 ? '$remaining' : '+${-remaining}',
                remaining >= 0 ? 'remaining' : 'over goal',
                remaining >= 0
                    ? theme.colorScheme.onSurface
                    : const Color(0xFFE9506E),
              ),
              const Spacer(),
              Text('Goal ${goals.calories}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: calPct.toDouble(),
              minHeight: 10,
              backgroundColor: kNutritionAccent.withOpacity(0.15),
              valueColor: const AlwaysStoppedAnimation(kNutritionAccent),
            ),
          ),
          const SizedBox(height: 20),
          _macroBar(context, 'Protein', totals.macros.protein, goals.protein,
              const Color(0xFF4A90D9)),
          const SizedBox(height: 12),
          _macroBar(context, 'Carbs', totals.macros.carbs, goals.carbs,
              const Color(0xFFF0A020)),
          const SizedBox(height: 12),
          _macroBar(context, 'Fat', totals.macros.fat, goals.fat,
              const Color(0xFFE9506E)),
        ],
      ),
    );
  }

  Widget _bigStat(
      BuildContext context, String value, String label, Color color) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold, color: color)),
        Text(label,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }

  Widget _macroBar(BuildContext context, String label, double value,
      int goal, Color color) {
    final theme = Theme.of(context);
    final pct = goal == 0 ? 0.0 : (value / goal).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label,
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const Spacer(),
            Text('${value.round()} / ${goal}g',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: pct.toDouble(),
            minHeight: 7,
            backgroundColor: color.withOpacity(0.15),
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }
}
