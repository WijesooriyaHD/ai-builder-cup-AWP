import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:provider/provider.dart';

import '../../../providers/app_state.dart';
import '../../../utils/pro_modal_utils.dart';
import '../../../widgets/ai_wellness_loader.dart';
import '../../nutrition/domain/nutrition_models.dart';
import '../../nutrition/presentation/nutrition_state.dart';
import '../domain/meal_planner_models.dart';
import 'meal_planner_state.dart';
import 'widgets/meal_plan_cards.dart';

/// The AI Meal Planner: set up a profile, choose goal/diet/plan type, generate
/// AI meal plans, swap meals, build a grocery list, favorite meals, and log
/// planned meals into the Nutrition Coach diary.
class MealPlannerScreen extends StatefulWidget {
  const MealPlannerScreen({super.key});

  @override
  State<MealPlannerScreen> createState() => _MealPlannerScreenState();
}

class _MealPlannerScreenState extends State<MealPlannerScreen> {
  DietMode _dietMode = DietMode.standard;
  PlanType _planType = PlanType.daily;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final state = context.read<MealPlannerState>();
      await state.load();
      // Seed diet/goal defaults from the existing active plan.
      if (state.activePlan != null && mounted) {
        setState(() {
          _dietMode = state.activePlan!.dietMode;
          _planType = state.activePlan!.planType;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Consumer<MealPlannerState>(
      builder: (context, state, _) {
        return Scaffold(
          backgroundColor:
              isDark ? const Color(0xFF0F1115) : const Color(0xFFFDF6F1),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: const Text('AI Meal Planner'),
            centerTitle: true,
            actions: [
              IconButton(
                tooltip: 'Profile',
                icon: const Icon(Icons.person_rounded),
                onPressed: () => _showProfileSheet(context, state),
              ),
            ],
          ),
          body: state.isLoading
              ? const Center(child: CircularProgressIndicator())
              : !state.hasProfile
                  ? _buildProfilePrompt(context, state)
                  : _buildMain(context, state),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Profile prompt (setup)
  // ---------------------------------------------------------------------------
  Widget _buildProfilePrompt(BuildContext context, MealPlannerState state) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.restaurant_menu_rounded,
                size: 56, color: kMealPlanAccent),
            const SizedBox(height: 16),
            Text('Let’s set up your plan',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'Tell us a little about you so the AI can tailor realistic, '
              'goal-aligned meals.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: kMealPlanAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => _showProfileSheet(context, state),
                child: const Text('Set up profile'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Main content
  // ---------------------------------------------------------------------------
  Widget _buildMain(BuildContext context, MealPlannerState state) {
    final plan = state.activePlan;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
      children: [
        _buildControls(context, state),
        const SizedBox(height: 16),
        if (state.error != null && !state.isGenerating) ...[
          _buildErrorBanner(context, state.error!),
          const SizedBox(height: 16),
        ],
        if (state.isGenerating)
          _buildGeneratingCard(context)
        else if (plan == null)
          _buildEmptyState(context)
        else ...[
          if (state.todayPlan != null) ...[
            TodaysMealPlanCard(
              day: state.todayPlan!,
              onTapMeal: (m) => _showMealDetail(context, state, m),
              onSwapMeal: (m) => _showSwapSheet(context, state, m),
            ),
            const SizedBox(height: 16),
            DailyNutritionSummaryCard(
              day: state.todayPlan!,
              calorieTarget: plan.dailyCalories,
            ),
            const SizedBox(height: 16),
          ],
          if (plan.aiInsights.isNotEmpty) ...[
            _buildInsightsCard(context, plan.aiInsights),
            const SizedBox(height: 16),
          ],
          if (plan.planType != PlanType.daily && plan.days.length > 1) ...[
            WeeklyPlanOverviewCard(
              plan: plan,
              onTapDay: (i) => _showDayDetail(context, state, i),
            ),
            const SizedBox(height: 16),
          ],
          GroceryListCard(
            list: plan.groceryList,
            isBuilding: state.isBuildingGrocery,
            onGenerate: () => state.buildGroceryList(),
            onToggle: (name) => state.toggleGroceryItem(name),
          ),
        ],
      ],
    );
  }

  Widget _buildControls(BuildContext context, MealPlannerState state) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            kMealPlanAccent.withOpacity(0.16),
            kMealPlanAccent.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: kMealPlanAccent.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('${state.profile!.goal.emoji} ',
                  style: const TextStyle(fontSize: 16)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Goal: ${state.profile!.goal.label}',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    Text('~${state.profile!.dailyCalories} kcal/day',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              // Always-visible way back into the profile/goal editor. The sheet
              // prefills every field from the saved profile, so nothing is lost.
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: kMealPlanAccent,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
                onPressed: () => _showProfileSheet(context, state),
                icon: const Icon(Icons.edit_rounded, size: 18),
                label: const Text('Edit'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _label(context, 'Diet mode'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: DietMode.values.map((d) {
              final sel = d == _dietMode;
              return ChoiceChip(
                label: Text('${d.emoji} ${d.label}'),
                selected: sel,
                selectedColor: kMealPlanAccent.withOpacity(0.25),
                onSelected: (_) => setState(() => _dietMode = d),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          _label(context, 'Plan length'),
          const SizedBox(height: 6),
          Row(
            children: PlanType.values.map((p) {
              final sel = p == _planType;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(p.label),
                  selected: sel,
                  selectedColor: kMealPlanAccent.withOpacity(0.25),
                  onSelected: (_) => setState(() => _planType = p),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: kMealPlanAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed:
                  state.isGenerating ? null : () => _onGenerate(context, state),
              icon: Icon(context.watch<AppState>().isPro || kDebugMode
                  ? Icons.auto_awesome_rounded
                  : Icons.lock_rounded),
              label: Text(state.activePlan == null
                  ? 'Generate plan'
                  : 'Regenerate plan'),
            ),
          ),
          if (!context.watch<AppState>().isPro && !kDebugMode) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.workspace_premium_rounded,
                    size: 14, color: kMealPlanAccent),
                const SizedBox(width: 4),
                Text('AI generation is a Premium feature',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          ],
          if (state.activePlan != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: kMealPlanAccent,
                  side: BorderSide(color: kMealPlanAccent.withOpacity(0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed:
                    state.isGenerating ? null : () => _confirmReset(context, state),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Reset plan'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Gates AI generation behind Premium. Free users see the upgrade paywall.
  /// In debug builds the gate is bypassed so the AI path can be tested without
  /// a subscription.
  Future<void> _onGenerate(BuildContext context, MealPlannerState state) async {
    final appState = context.read<AppState>();
    if (!appState.isPro && !kDebugMode) {
      ProModalUtils.showProStatusModal(context, false);
      return;
    }
    final ok =
        await state.generate(planType: _planType, dietMode: _dietMode);
    if (!ok && context.mounted) {
      _snack(context, state.error ?? 'Could not generate.');
    }
  }

  /// Confirms and clears the active plan.
  void _confirmReset(BuildContext context, MealPlannerState state) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Reset plan?'),
        content: const Text(
            'This clears your current meal plan and grocery list. Your saved '
            'favorites are kept.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: kMealPlanAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              state.resetPlan();
              Navigator.pop(ctx);
            },
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }

  Widget _label(BuildContext context, String text) => Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      );

  Widget _buildGeneratingCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: const Column(
        children: [
          AiWellnessLoader(color: kMealPlanAccent, size: 160),
          SizedBox(height: 20),
          Text('Crafting your meal plan…',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
          SizedBox(height: 4),
          Text('Balancing your goals, macros, and preferences.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          const Icon(Icons.ramen_dining_rounded,
              size: 44, color: kMealPlanAccent),
          const SizedBox(height: 12),
          Text('No plan yet',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Pick your diet mode and tap Generate plan.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  /// Persistent, readable error banner so failure reasons don't vanish like a
  /// snackbar. Shows the exact message returned by the AI service.
  Widget _buildErrorBanner(BuildContext context, String message) {
    final theme = Theme.of(context);
    const errColor = Color(0xFFE9506E);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: errColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: errColor.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, color: errColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Couldn’t generate',
                    style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold, color: errColor)),
                const SizedBox(height: 4),
                Text(message,
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInsightsCard(BuildContext context, List<String> insights) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            kMealPlanAccent.withOpacity(0.14),
            kMealPlanAccent.withOpacity(0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: kMealPlanAccent.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.insights_rounded,
                  color: kMealPlanAccent, size: 20),
              const SizedBox(width: 8),
              Text('AI insights',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 10),
          ...insights.map((i) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Icon(Icons.circle,
                          size: 6, color: kMealPlanAccent),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(i,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(height: 1.4))),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Meal detail (log to diary / favorite / swap)
  // ---------------------------------------------------------------------------
  void _showMealDetail(
      BuildContext context, MealPlannerState state, PlannedMeal m) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _Sheet(
        title: m.name,
        scrollable: true,
        child: Consumer<MealPlannerState>(builder: (ctx, s, _) {
          final fav = s.isFavoriteMeal(m);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${m.type.emoji} ${m.type.label}',
                  style: Theme.of(ctx).textTheme.labelLarge?.copyWith(
                      color: kMealPlanAccent, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              _macroRow(ctx, m),
              if (m.reason != null && m.reason!.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: kMealPlanAccent.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.lightbulb_rounded,
                          size: 18, color: kMealPlanAccent),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text(m.reason!,
                              style: Theme.of(ctx)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(height: 1.4))),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              // Integration: log this planned meal into the Nutrition Coach.
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: kMealPlanAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.restaurant_rounded),
                label: const Text('Log to food diary'),
                onPressed: () {
                  _logToNutrition(context, m);
                  Navigator.pop(ctx);
                },
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: Icon(
                          fav
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          color: kMealPlanAccent),
                      label: Text(fav ? 'Saved' : 'Favorite',
                          style: const TextStyle(color: kMealPlanAccent)),
                      onPressed: () => s.toggleFavoriteMeal(m),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.swap_horiz_rounded,
                          color: kMealPlanAccent),
                      label: const Text('Swap',
                          style: TextStyle(color: kMealPlanAccent)),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _showSwapSheet(context, s, m);
                      },
                    ),
                  ),
                ],
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _macroRow(BuildContext context, PlannedMeal m) {
    Widget chip(String label, String value) => Expanded(
          child: Column(
            children: [
              Text(value,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              Text(label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
        );
    return Row(
      children: [
        chip('kcal', '${m.calories}'),
        chip('Protein', '${m.macros.protein.round()}g'),
        chip('Carbs', '${m.macros.carbs.round()}g'),
        chip('Fat', '${m.macros.fat.round()}g'),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Swap sheet — 3 AI alternatives
  // ---------------------------------------------------------------------------
  void _showSwapSheet(
      BuildContext context, MealPlannerState state, PlannedMeal meal) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SwapSheet(
        original: meal,
        onFetch: () => state.fetchAlternatives(meal),
        onPick: (alt) async {
          await state.replaceMealInPlan(meal, alt);
          if (ctx.mounted) Navigator.pop(ctx);
          if (context.mounted) _snack(context, 'Meal swapped.');
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Day detail (weekly plan)
  // ---------------------------------------------------------------------------
  void _showDayDetail(BuildContext context, MealPlannerState state, int index) {
    final plan = state.activePlan;
    if (plan == null || index >= plan.days.length) return;
    final day = plan.days[index];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _Sheet(
        title: 'Day ${index + 1}',
        scrollable: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TodaysMealPlanCard(
              day: day,
              onTapMeal: (m) {
                Navigator.pop(ctx);
                _showMealDetail(context, state, m);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Profile setup sheet
  // ---------------------------------------------------------------------------
  void _showProfileSheet(BuildContext context, MealPlannerState state) {
    // Prefill from existing profile OR from the app's weight tracker.
    final appState = context.read<AppState>();
    final existing = state.profile;
    final ageC = TextEditingController(text: existing?.age?.toString() ?? '');
    final heightC = TextEditingController(
        text: (existing?.heightCm ?? appState.weightData.heightCm)
                ?.round()
                .toString() ??
            '');
    final weightC = TextEditingController(
        text: (existing?.weightKg ?? appState.weightData.currentKg)
                ?.round()
                .toString() ??
            '');
    final goalWeightC = TextEditingController(
        text: existing?.goalWeightKg?.round().toString() ?? '');
    final calC = TextEditingController(
        text: (existing?.dailyCalories ?? 2000).toString());
    final nationalityC = TextEditingController(
        text: existing?.nationality ?? 'United States');
    String gender = existing?.gender ?? 'female';
    String activity = existing?.activityLevel ?? 'moderate';
    WellnessGoal goal = existing?.goal ?? WellnessGoal.generalWellness;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: StatefulBuilder(builder: (ctx, setLocal) {
          return _Sheet(
            title: 'Your profile',
            scrollable: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  Expanded(child: _numField(ageC, 'Age', 'yrs')),
                  const SizedBox(width: 12),
                  Expanded(child: _numField(heightC, 'Height', 'cm')),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                      child: _numField(weightC, 'Weight', 'kg',
                          onChanged: (_) => setLocal(() {
                                _resetGoalIfConflicting(
                                    weightC, goalWeightC, goal,
                                    (g) => goal = g);
                              }))),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _numField(goalWeightC, 'Goal wt', 'kg',
                          onChanged: (_) => setLocal(() {
                                _resetGoalIfConflicting(
                                    weightC, goalWeightC, goal,
                                    (g) => goal = g);
                              }))),
                ]),
                const SizedBox(height: 16),
                _label(ctx, 'Gender'),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: ['female', 'male', 'other'].map((g) {
                    return ChoiceChip(
                      label: Text(g[0].toUpperCase() + g.substring(1)),
                      selected: gender == g,
                      selectedColor: kMealPlanAccent.withOpacity(0.25),
                      onSelected: (_) => setLocal(() => gender = g),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                _label(ctx, 'Country / food culture'),
                const SizedBox(height: 6),
                TextField(
                  controller: nationalityC,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    hintText: 'e.g. United States',
                    prefixIcon: const Icon(Icons.public_rounded),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'We use this to suggest meals familiar to your food culture.',
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                _label(ctx, 'Activity level'),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    'sedentary',
                    'light',
                    'moderate',
                    'active',
                    'very_active'
                  ].map((a) {
                    return ChoiceChip(
                      label: Text(a.replaceAll('_', ' ')),
                      selected: activity == a,
                      selectedColor: kMealPlanAccent.withOpacity(0.25),
                      onSelected: (_) => setLocal(() => activity = a),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                _label(ctx, 'Wellness goal'),
                const SizedBox(height: 6),
                Builder(builder: (ctx) {
                  final cur = double.tryParse(weightC.text);
                  final tgt = double.tryParse(goalWeightC.text);
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: WellnessGoal.values.map((g) {
                      final disabled = _isGoalDisabled(g, cur, tgt);
                      return ChoiceChip(
                        label: Text('${g.emoji} ${g.label}'),
                        selected: goal == g,
                        selectedColor: kMealPlanAccent.withOpacity(0.25),
                        // Grey out and block goals that contradict the weights.
                        onSelected: disabled
                            ? null
                            : (_) => setLocal(() => goal = g),
                      );
                    }).toList(),
                  );
                }),
                Builder(builder: (ctx) {
                  final cur = double.tryParse(weightC.text);
                  final tgt = double.tryParse(goalWeightC.text);
                  final hint = _goalConflictHint(cur, tgt);
                  if (hint == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(hint,
                        style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                            color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                  );
                }),
                const SizedBox(height: 16),
                _numField(calC, 'Daily calorie target', 'kcal'),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kMealPlanAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () {
                      final profile = UserProfile(
                        age: int.tryParse(ageC.text),
                        gender: gender,
                        heightCm: double.tryParse(heightC.text),
                        weightKg: double.tryParse(weightC.text),
                        goalWeightKg: double.tryParse(goalWeightC.text),
                        activityLevel: activity,
                        goal: goal,
                        dailyCalories:
                            int.tryParse(calC.text) ?? 2000,
                        nationality: nationalityC.text.trim().isEmpty
                            ? 'United States'
                            : nationalityC.text.trim(),
                      );
                      // Guard: if the goal contradicts the weights, block save.
                      if (_isGoalDisabled(profile.goal, profile.weightKg,
                          profile.goalWeightKg)) {
                        _snack(ctx,
                            'Your ${profile.goal.label} goal doesn\'t match '
                            'your current and goal weights.');
                        return;
                      }
                      if (!profile.isComplete) {
                        _snack(
                            ctx,
                            profile.goalRequiresWeight
                                ? 'For ${profile.goal.label}, please add your '
                                    'current weight, goal weight and calorie target.'
                                : 'Please add your daily calorie target.');
                        return;
                      }
                      state.saveProfile(profile);
                      setState(() {});
                      Navigator.pop(ctx);
                    },
                    child: const Text('Save profile'),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  /// If the currently-selected [goal] conflicts with the entered weights,
  /// reset it to General Wellness via [set].
  void _resetGoalIfConflicting(
    TextEditingController weightC,
    TextEditingController goalWeightC,
    WellnessGoal goal,
    void Function(WellnessGoal) set,
  ) {
    final cur = double.tryParse(weightC.text);
    final tgt = double.tryParse(goalWeightC.text);
    if (_isGoalDisabled(goal, cur, tgt)) {
      set(WellnessGoal.generalWellness);
    }
  }

  /// Whether a goal contradicts the entered weights.
  /// Heavier goal weight than current ⇒ block Weight Loss.
  /// Lighter goal weight than current ⇒ block Weight Gain.
  bool _isGoalDisabled(WellnessGoal g, double? current, double? target) {
    if (current == null || target == null) return false;
    const tolerance = 0.5; // kg; treat near-equal as "maintain"
    final diff = target - current;
    if (diff > tolerance && g == WellnessGoal.weightLoss) return true;
    if (diff < -tolerance && g == WellnessGoal.weightGain) return true;
    return false;
  }

  String? _goalConflictHint(double? current, double? target) {
    if (current == null || target == null) return null;
    const tolerance = 0.5;
    final diff = target - current;
    if (diff > tolerance) {
      return 'Your goal weight is higher than your current weight, so Weight '
          'Loss is unavailable.';
    }
    if (diff < -tolerance) {
      return 'Your goal weight is lower than your current weight, so Weight '
          'Gain is unavailable.';
    }
    return null;
  }

  Widget _numField(TextEditingController c, String label, String unit,
      {ValueChanged<String>? onChanged}) {
    return TextField(
      controller: c,
      keyboardType: TextInputType.number,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        suffixText: unit,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Integration + helpers
  // ---------------------------------------------------------------------------
  void _logToNutrition(BuildContext context, PlannedMeal m) {
    final nutrition = context.read<NutritionState>();
    final result = NutritionResult(
      mealName: m.name,
      calories: m.calories,
      macros: m.macros,
      foodQualityScore: 0,
      aiInsights: m.reason != null ? [m.reason!] : const [],
      source: 'meal_plan',
    );
    nutrition.logMeal(result, mealType: m.type);
    _snack(context, 'Logged "${m.name}" to your food diary.');
  }

  void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }
}

/// AI meal-swap sheet that fetches 3 alternatives on open.
class _SwapSheet extends StatefulWidget {
  final PlannedMeal original;
  final Future<MealSuggestion?> Function() onFetch;
  final ValueChanged<PlannedMeal> onPick;

  const _SwapSheet({
    required this.original,
    required this.onFetch,
    required this.onPick,
  });

  @override
  State<_SwapSheet> createState() => _SwapSheetState();
}

class _SwapSheetState extends State<_SwapSheet> {
  bool _loading = true;
  MealSuggestion? _suggestion;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    final s = await widget.onFetch();
    if (mounted) {
      setState(() {
        _suggestion = s;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Sheet(
      title: 'Swap ${widget.original.type.label.toLowerCase()}',
      scrollable: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Alternatives close to ${widget.original.calories} kcal',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                  child: CircularProgressIndicator(color: kMealPlanAccent)),
            )
          else if (_suggestion == null || _suggestion!.options.isEmpty)
            Column(
              children: [
                const Text('Could not find alternatives right now.'),
                const SizedBox(height: 12),
                TextButton(
                    onPressed: _fetch, child: const Text('Try again')),
              ],
            )
          else
            ..._suggestion!.options.map((opt) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: InkWell(
                    onTap: () => widget.onPick(opt),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: kMealPlanAccent.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: kMealPlanAccent.withOpacity(0.25)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(opt.name,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.bold)),
                                const SizedBox(height: 2),
                                Text(
                                  '${opt.calories} kcal · P ${opt.macros.protein.round()} · '
                                  'C ${opt.macros.carbs.round()} · F ${opt.macros.fat.round()}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color:
                                          theme.colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.check_circle_outline_rounded,
                              color: kMealPlanAccent),
                        ],
                      ),
                    ),
                  ),
                )),
        ],
      ),
    );
  }
}

/// Rounded bottom-sheet with grab handle + title (module-local copy).
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
