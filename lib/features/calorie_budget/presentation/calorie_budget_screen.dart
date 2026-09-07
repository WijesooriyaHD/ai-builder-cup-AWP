import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../meal_planner/presentation/meal_planner_state.dart';
import '../../nutrition/presentation/nutrition_state.dart';
import '../data/calorie_budget_repository.dart';
import '../domain/calorie_budget_models.dart';
import 'calorie_budget_state.dart';
import 'widgets/calorie_budget_cards.dart';

/// The AI Calorie Budget dashboard: energy balance ring, AI prediction +
/// recommendations, daily timeline, 7-day trend, and goal streak. Consumed
/// calories flow in from the Nutrition Coach; the budget from the Meal Planner.
class CalorieBudgetScreen extends StatefulWidget {
  const CalorieBudgetScreen({super.key});

  @override
  State<CalorieBudgetScreen> createState() => _CalorieBudgetScreenState();
}

class _CalorieBudgetScreenState extends State<CalorieBudgetScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    final state = context.read<CalorieBudgetState>();
    final nutrition = context.read<NutritionState>();
    final planner = context.read<MealPlannerState>();
    // Make sure the source tools have loaded their data.
    await Future.wait([nutrition.load(), planner.load(), state.load()]);
    _sync();
    await state.refreshAnalysis();
    await state.evaluateStreak();
  }

  void _sync() {
    final state = context.read<CalorieBudgetState>();
    final nutrition = context.read<NutritionState>();
    final planner = context.read<MealPlannerState>();
    state.syncInputs(
      consumed: nutrition.todaysTotals.calories,
      todaysMeals: nutrition.todaysMeals,
      profile: planner.profile,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // React to Nutrition Coach changes (new meals) → keep consumed in sync.
    return Consumer2<CalorieBudgetState, NutritionState>(
      builder: (context, state, nutrition, _) {
        // Keep consumed fresh whenever the nutrition totals change.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (state.consumed != nutrition.todaysTotals.calories) {
            _sync();
          }
        });

        return Scaffold(
          backgroundColor:
              isDark ? const Color(0xFF0F1115) : const Color(0xFFFDF8F0),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: const Text('Calorie Budget'),
            centerTitle: true,
            actions: [
              IconButton(
                tooltip: 'Goal & budget',
                icon: const Icon(Icons.tune_rounded),
                onPressed: () => _showSettings(context, state),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor: kCalorieAccent,
            foregroundColor: Colors.white,
            onPressed: () => _showAddExercise(context, state),
            icon: const Icon(Icons.directions_run_rounded),
            label: const Text('Log exercise'),
          ),
          body: state.isLoading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: () async {
                    _sync();
                    await state.refreshAnalysis();
                  },
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                    children: [
                      CalorieBudgetCard(summary: state.summary),
                      const SizedBox(height: 16),
                      AiInsightCard(
                        prediction: state.prediction,
                        insights: state.insights,
                        isAnalyzing: state.isAnalyzing,
                      ),
                      const SizedBox(height: 16),
                      GoalStreakCard(
                        currentStreak: state.currentStreak,
                        bestStreak: state.bestStreak,
                      ),
                      const SizedBox(height: 16),
                      DailyTimelineCard(
                        events: state.timeline,
                        onTapEvent: (e) => _onTapTimelineEvent(context, state, e),
                      ),
                      const SizedBox(height: 16),
                      WeeklyProgressCard(points: _trendPoints(state)),
                    ],
                  ),
                ),
        );
      },
    );
  }

  List<CalorieTrendPoint> _trendPoints(CalorieBudgetState state) {
    // Build from recent Firestore days (oldest → newest), max 7, plus today.
    final recent = state.recent.reversed.take(7).toList();
    final points = recent
        .map((d) => CalorieTrendPoint(
              date: DateTime.tryParse(d.date) ?? DateTime.now(),
              consumed: d.consumed,
              burned: d.burned,
              budget: d.dailyBudget,
            ))
        .toList();
    // Ensure today is represented.
    final todayKey = CalorieBudgetRepository.dateKey(DateTime.now());
    if (!recent.any((d) => d.date == todayKey)) {
      points.add(CalorieTrendPoint(
        date: DateTime.now(),
        consumed: state.consumed,
        burned: state.burned,
        budget: state.dailyBudget,
      ));
    }
    if (points.length > 7) return points.sublist(points.length - 7);
    return points;
  }

  // ---------------------------------------------------------------------------
  // Add exercise
  // ---------------------------------------------------------------------------
  void _showAddExercise(BuildContext context, CalorieBudgetState state) {
    ExerciseType type = ExerciseType.walking;
    final minutesC = TextEditingController(text: '30');
    final caloriesC = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: StatefulBuilder(builder: (ctx, setLocal) {
          final est = (type.kcalPerMinute *
                  (int.tryParse(minutesC.text) ?? 0))
              .round();
          return _Sheet(
            title: 'Log exercise',
            scrollable: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ExerciseType.values.map((t) {
                    return ChoiceChip(
                      label: Text(t.label),
                      selected: type == t,
                      selectedColor: kCalorieAccent.withOpacity(0.25),
                      onSelected: (_) => setLocal(() => type = t),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: minutesC,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setLocal(() {}),
                        decoration: InputDecoration(
                          labelText: 'Minutes',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: caloriesC,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'kcal (optional)',
                          hintText: '$est',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Estimated burn: ~$est kcal',
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kCalorieAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () {
                      final mins = int.tryParse(minutesC.text) ?? 0;
                      if (mins <= 0) return;
                      final cal = int.tryParse(caloriesC.text);
                      state.addExercise(type, mins, calories: cal);
                      Navigator.pop(ctx);
                    },
                    child: const Text('Add'),
                  ),
                ),
                if (state.exercises.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Divider(),
                  ...state.exercises.map((e) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.directions_run_rounded,
                            color: kCalorieAccent),
                        title: Text('${e.type.label} · ${e.minutes} min'),
                        subtitle: Text('-${e.calories} kcal'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline_rounded),
                          onPressed: () {
                            state.removeExercise(e.id);
                            setLocal(() {});
                          },
                        ),
                      )),
                ],
              ],
            ),
          );
        }),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Edit a timeline event (exercise → this module; food → Nutrition Coach)
  // ---------------------------------------------------------------------------
  void _onTapTimelineEvent(
      BuildContext context, CalorieBudgetState state, CalorieEvent e) {
    if (e.kind == CalorieEventKind.exercise) {
      final entry = state.exerciseById(e.id);
      if (entry != null) _editExercise(context, state, entry);
    } else {
      _editFoodEvent(context, e);
    }
  }

  void _editExercise(
      BuildContext context, CalorieBudgetState state, ExerciseEntry entry) {
    ExerciseType type = entry.type;
    final minutesC = TextEditingController(text: '${entry.minutes}');
    final caloriesC = TextEditingController(text: '${entry.calories}');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: StatefulBuilder(builder: (ctx, setLocal) {
          return _Sheet(
            title: 'Edit exercise',
            scrollable: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ExerciseType.values.map((t) {
                    return ChoiceChip(
                      label: Text(t.label),
                      selected: type == t,
                      selectedColor: kCalorieAccent.withOpacity(0.25),
                      onSelected: (_) => setLocal(() => type = t),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: minutesC,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Minutes',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: caloriesC,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'kcal',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.delete_outline_rounded,
                            color: Color(0xFFE9506E)),
                        label: const Text('Delete',
                            style: TextStyle(color: Color(0xFFE9506E))),
                        onPressed: () {
                          state.removeExercise(entry.id);
                          Navigator.pop(ctx);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kCalorieAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () {
                          final mins = int.tryParse(minutesC.text) ?? entry.minutes;
                          final cal = int.tryParse(caloriesC.text);
                          state.updateExercise(entry.id,
                              type: type, minutes: mins, calories: cal);
                          Navigator.pop(ctx);
                        },
                        child: const Text('Save'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  void _editFoodEvent(BuildContext context, CalorieEvent e) {
    final nutrition = context.read<NutritionState>();
    final nameC = TextEditingController(
        text: e.label.contains(': ')
            ? e.label.split(': ').skip(1).join(': ')
            : e.label);
    final calC = TextEditingController(text: '${e.calories}');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _Sheet(
          title: 'Edit meal',
          scrollable: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('This meal is from your food diary.',
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 12),
              TextField(
                controller: nameC,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: calC,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Calories',
                  suffixText: 'kcal',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.delete_outline_rounded,
                          color: Color(0xFFE9506E)),
                      label: const Text('Delete',
                          style: TextStyle(color: Color(0xFFE9506E))),
                      onPressed: () {
                        nutrition.deleteMeal(e.id);
                        Navigator.pop(ctx);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kCalorieAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        nutrition.updateMeal(
                          e.id,
                          mealName: nameC.text.trim().isEmpty
                              ? null
                              : nameC.text.trim(),
                          calories: int.tryParse(calC.text),
                        );
                        Navigator.pop(ctx);
                      },
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Settings (goal mode + budget override)
  // ---------------------------------------------------------------------------
  void _showSettings(BuildContext context, CalorieBudgetState state) {
    final budgetC = TextEditingController(
        text: state.dailyBudget.toString());
    GoalMode mode = state.goalMode;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: StatefulBuilder(builder: (ctx, setLocal) {
          return _Sheet(
            title: 'Goal & budget',
            scrollable: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Goal mode',
                    style: Theme.of(ctx).textTheme.labelLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: GoalMode.values.map((g) {
                    return ChoiceChip(
                      label: Text('${g.emoji} ${g.label}'),
                      selected: mode == g,
                      selectedColor: kCalorieAccent.withOpacity(0.25),
                      onSelected: (_) => setLocal(() => mode = g),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: budgetC,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Daily budget',
                    suffixText: 'kcal',
                    helperText:
                        'Leave as-is to derive from your Meal Planner profile.',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kCalorieAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () async {
                      await state.setGoalMode(mode);
                      final b = int.tryParse(budgetC.text) ?? 0;
                      // Only treat as an override if it differs from derived.
                      await state.setBudgetOverride(b);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

/// Rounded bottom-sheet with grab handle + title (module-local).
class _Sheet extends StatelessWidget {
  final String title;
  final Widget child;
  final bool scrollable;

  const _Sheet({
    required this.title,
    required this.child,
    this.scrollable = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurface.withOpacity(0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Text(title,
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        child,
      ],
    );
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.all(20),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(28),
      ),
      child: scrollable ? SingleChildScrollView(child: content) : content,
    );
  }
}
