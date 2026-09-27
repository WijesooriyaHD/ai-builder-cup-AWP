import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../providers/app_state.dart';
import '../../../widgets/ai_response_safety.dart';
import '../../calorie_budget/presentation/calorie_budget_state.dart';
import '../../hydration/presentation/hydration_state.dart';
import '../../nutrition/domain/nutrition_models.dart';
import '../../nutrition/presentation/nutrition_state.dart';
import '../data/sleep_factors_analyzer.dart';
import '../domain/sleep_models.dart';
import 'sleep_onboarding_screen.dart';
import 'sleep_overview_sheet.dart';
import 'sleep_state.dart';
import 'widgets/sleep_cards.dart';

/// The AI Sleep Coach dashboard. Tells the story: what happened → why → what to
/// do tonight → add it to your routine. Consumes hydration/nutrition/exercise
/// from the other tools for the Sleep Factors + Food & Sleep sections.
class SleepCoachScreen extends StatefulWidget {
  const SleepCoachScreen({super.key});

  @override
  State<SleepCoachScreen> createState() => _SleepCoachScreenState();
}

class _SleepCoachScreenState extends State<SleepCoachScreen> {
  bool _routineAdded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    final sleep = context.read<SleepState>();
    final nutrition = context.read<NutritionState>();
    final hydration = context.read<HydrationState>();
    final calorie = context.read<CalorieBudgetState>();

    // Adopt a previously-granted health connection silently (no prompt).
    await sleep.restoreHealthConnection();

    // Load the source tools so we have factor data.
    await Future.wait([
      nutrition.load(),
      hydration.load(),
      calorie.load(),
    ]);
    sleep.setFactorInputs(_buildFactorInputs(nutrition, hydration, calorie));
    await sleep.load();
  }

  Future<void> _connectHealth(BuildContext context, SleepState state) async {
    final connected = await state.connectHealth();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(connected
            ? 'Connected. Showing your real sleep data.'
            : 'No health data connected — showing sample data instead.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Derives privacy-safe factor inputs from the other tools (yesterday's day).
  SleepFactorInputs _buildFactorInputs(
    NutritionState nutrition,
    HydrationState hydration,
    CalorieBudgetState calorie,
  ) {
    // Dinner = latest non-snack meal logged today (proxy for "before sleep").
    final meals = nutrition.todaysMeals;
    Meal? dinner;
    for (final m in meals) {
      if (m.mealType == MealType.dinner) {
        if (dinner == null || m.createdAt.isAfter(dinner.createdAt)) dinner = m;
      }
    }
    dinner ??= meals.isNotEmpty
        ? meals.reduce((a, b) => a.createdAt.isAfter(b.createdAt) ? a : b)
        : null;

    // Caffeine heuristic: a meal name mentioning coffee/tea/energy logged late.
    final lateCaffeine = meals.any((m) {
      final n = m.mealName.toLowerCase();
      final isCaffeine = n.contains('coffee') ||
          n.contains('espresso') ||
          n.contains('tea') ||
          n.contains('energy drink') ||
          n.contains('cola');
      return isCaffeine && m.createdAt.hour >= 14;
    });

    return SleepFactorInputs(
      hydrationMl: hydration.consumedMl > 0 ? hydration.consumedMl : null,
      hydrationGoalMl: hydration.goalMl,
      exerciseMinutes:
          calorie.exercises.fold<int>(0, (s, e) => s + e.minutes),
      dinnerTime: dinner?.createdAt,
      dinnerCalories: dinner?.calories,
      lateCaffeine: meals.isEmpty ? null : lateCaffeine,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Consumer<SleepState>(
      builder: (context, state, _) {
        return Scaffold(
          backgroundColor:
              isDark ? const Color(0xFF0F1115) : const Color(0xFFF4F3FB),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: const Text('Sleep Coach'),
            centerTitle: true,
            actions: [
              if (!state.healthConnected)
                IconButton(
                  tooltip: Platform.isIOS
                      ? 'Connect Apple Health'
                      : 'Connect Health Connect',
                  icon: const Icon(Icons.favorite_border_rounded),
                  onPressed: () => _connectHealth(context, state),
                ),
              IconButton(
                tooltip: 'How sleep insights work',
                icon: const Icon(Icons.info_outline_rounded),
                onPressed: () => showSleepOverviewSheet(context),
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                _buildDateNav(context, state),
                Expanded(child: _buildBody(context, state)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDateNav(BuildContext context, SleepState state) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: () => state.previousDay(),
          ),
          Expanded(
            child: Center(
              child: Text(_formatDate(state.selectedDate),
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: state.canGoNext ? () => state.nextDay() : null,
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, SleepState state) {
    switch (state.status) {
      case SleepStatus.loading:
        return const SleepSkeleton();
      case SleepStatus.error:
        return _buildError(context, state);
      case SleepStatus.empty:
        return _buildEmpty(context);
      case SleepStatus.loaded:
        return _buildDashboard(context, state);
    }
  }

  Widget _buildDashboard(BuildContext context, SleepState state) {
    final session = state.session!;
    final score = state.score!;
    final nutrition = context.read<NutritionState>();

    // Food & Sleep from the latest meal today (if any).
    final meals = nutrition.todaysMeals;
    final lastMeal = meals.isNotEmpty
        ? meals.reduce((a, b) => a.createdAt.isAfter(b.createdAt) ? a : b)
        : null;

    return RefreshIndicator(
      onRefresh: () async {
        await _init();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          if (!state.healthConnected) ...[
            _SampleDataBanner(
                onConnect: () => _connectHealth(context, state)),
            const SizedBox(height: 12),
          ],
          SleepScoreCard(
              greeting: state.greeting, session: session, score: score),
          const SizedBox(height: 16),
          SleepStagesCard(session: session),
          const SizedBox(height: 16),
          AISleepInsightCard(
            insight: state.insight,
            isAnalyzing: state.isAnalyzing,
            aiFailed: state.aiFailed,
            onRetry: () => state.retryAnalysis(),
          ),
          const SizedBox(height: 16),
          if (state.insight != null)
            AIRecommendationCard(
              recommendation: state.insight!.recommendation,
              added: _routineAdded,
              onAddToRoutine: () => _addToRoutine(context, state),
            ),
          if (state.insight != null) const SizedBox(height: 16),
          SleepFactorsCard(factors: state.factors),
          const SizedBox(height: 16),
          FoodSleepCard(
            dinnerName: lastMeal?.mealName,
            dinnerTime:
                lastMeal == null ? null : _formatTime(lastMeal.createdAt),
            dinnerCalories: lastMeal?.calories,
            protein: lastMeal?.macros.protein.round(),
            carbs: lastMeal?.macros.carbs.round(),
            fat: lastMeal?.macros.fat.round(),
            note: _dinnerNote(state),
          ),
          const SizedBox(height: 16),
          SleepHistoryChart(points: state.history),
          const SizedBox(height: 16),
          const AiDisclaimerNote(
            text: 'Sleep insights are AI-generated and may be inaccurate. '
                "They aren't medical advice. If you have ongoing sleep "
                'problems, talk to a healthcare professional.',
          ),
        ],
      ),
    );
  }

  String? _dinnerNote(SleepState state) {
    final dinner = state.factors
        .where((f) => f.key == 'dinner_timing' && f.value != null)
        .toList();
    if (dinner.isEmpty) return null;
    if (dinner.first.status == FactorStatus.needsAttention) {
      return 'Your dinner was logged fairly late, which may affect wind-down.';
    }
    return null;
  }

  Future<void> _addToRoutine(BuildContext context, SleepState state) async {
    final rec = state.insight?.recommendation;
    if (rec == null) return;
    final appState = context.read<AppState>();
    try {
      // Reuse the existing wellness-intention system as the routine/habit store.
      await appState.addDream(
        '🌙 ${rec.title}',
        initialSteps: [
          {'title': rec.title, 'isCompleted': false},
        ],
      );
      if (mounted) {
        setState(() => _routineAdded = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Added to your wellness intentions.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not add to your routine. Please try again.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Widget _buildEmpty(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 40),
        const Center(child: Text('🌙', style: TextStyle(fontSize: 48))),
        const SizedBox(height: 16),
        Center(
          child: Text("Sleep data isn't available yet.",
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            'Connect a sleep source to see your score, stages, and insights.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: 24),
        Center(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: kSleepAccent),
            onPressed: () =>
                _connectHealth(context, context.read<SleepState>()),
            icon: const Icon(Icons.favorite_rounded),
            label: const Text('Connect Sleep Data'),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: () => context.read<SleepState>().load(),
            child: const Text('Show sample data'),
          ),
        ),
      ],
    );
  }

  Widget _buildError(BuildContext context, SleepState state) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 44, color: Colors.grey),
            const SizedBox(height: 12),
            Text(state.error ?? 'Something went wrong.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: kSleepAccent),
              onPressed: () => state.load(),
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _formatDate(DateTime d) {
    final today = DateTime.now();
    if (d.year == today.year && d.month == today.month && d.day == today.day) {
      return 'Today';
    }
    return '${_months[d.month - 1]} ${d.day}, ${d.year}';
  }

  String _formatTime(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    final ap = t.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ap';
  }
}

/// Persistent label shown above the scores while the demo source is active,
/// so sample numbers are never mistaken for the user's own sleep.
class _SampleDataBanner extends StatelessWidget {
  final VoidCallback onConnect;

  const _SampleDataBanner({required this.onConnect});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final source = Platform.isIOS ? 'Apple Health' : 'Health Connect';
    return Material(
      color: kSleepAccent.withOpacity(0.12),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onConnect,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.info_outline_rounded,
                  size: 18, color: kSleepAccent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Sample data — connect $source to see your own',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Entry helper: shows onboarding on first open, else the dashboard.
class SleepCoachEntry extends StatelessWidget {
  const SleepCoachEntry({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: context.read<SleepState>().isOnboarded(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.data == true) {
          return const SleepCoachScreen();
        }
        return const SleepOnboardingScreen();
      },
    );
  }
}
