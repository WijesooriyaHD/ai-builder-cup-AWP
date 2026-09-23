import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/toolkit_customize_sheet.dart';
import '../providers/app_state.dart';
import 'package:provider/provider.dart';
import '../models/period_data.dart';
import 'period_tracker_screen.dart';
import '../models/weight_data.dart';
import 'weight_tracker_screen.dart';
import '../features/nutrition/presentation/nutrition_coach_screen.dart';
import '../features/nutrition/presentation/nutrition_state.dart';
import '../features/meal_planner/presentation/meal_planner_screen.dart';
import '../features/meal_planner/presentation/meal_planner_state.dart';
import '../features/meal_planner/domain/meal_planner_models.dart';
import '../features/calorie_budget/presentation/calorie_budget_screen.dart';
import '../features/calorie_budget/presentation/calorie_budget_state.dart';
import '../features/hydration/presentation/hydration_coach_screen.dart';
import '../features/hydration/presentation/hydration_state.dart';
import '../features/sleep/presentation/sleep_coach_screen.dart';
import '../features/meditation/presentation/meditation_home_screen.dart';
import 'travel_screen.dart';

class SheStacksScreen extends StatefulWidget {
  const SheStacksScreen({super.key});

  @override
  State<SheStacksScreen> createState() => _SheStacksScreenState();
}

class _SheStacksScreenState extends State<SheStacksScreen> {
  static const String _hiddenToolsKey = ToolkitCustomize.hiddenToolsKey;

  /// IDs of tools the user has hidden from the toolkit. Persisted locally.
  Set<String> _hiddenTools = {};

  @override
  void initState() {
    super.initState();
    _loadHiddenTools();
  }

  Future<void> _loadHiddenTools() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_hiddenToolsKey);
      if (raw != null && raw.isNotEmpty && mounted) {
        setState(() {
          _hiddenTools = Set<String>.from(jsonDecode(raw) as List);
        });
      }
    } catch (e) {
      debugPrint('❌ SheStacks._loadHiddenTools: $e');
    }
  }

  /// The toolkit registry: id, label, icon, and the card builder. Order here
  /// is the display order. Driving the list + the customize sheet from one
  /// source keeps them in sync.
  List<_ToolkitEntry> _toolkitEntries(AppState appState) => [
        _ToolkitEntry('period', 'Period Tracker', Icons.favorite_rounded,
            (c) => _buildPeriodTrackerCard(c, appState)),
        _ToolkitEntry('weight', 'Body Weight', Icons.monitor_weight_rounded,
            (c) => _buildWeightTrackerCard(c, appState)),            
        _ToolkitEntry('hydration', 'Hydration Coach', Icons.water_drop_rounded,
            (c) => _buildHydrationCard(c)),
        _ToolkitEntry('calorie_budget', 'Calorie Budget', Icons.local_fire_department_rounded,
            (c) => _buildCalorieBudgetCard(c)),
        _ToolkitEntry('meal_planner', 'Meal Planner', Icons.set_meal_rounded,
            (c) => _buildMealPlannerCard(c)),
        _ToolkitEntry('nutrition', 'AI Nutrition Coach', Icons.restaurant_rounded,
            (c) => _buildNutritionCoachCard(c)),
        _ToolkitEntry('meditation', 'Meditation Pal', Icons.self_improvement_rounded,
            (c) => _buildMeditationCard(c)),
        _ToolkitEntry('sleep', 'Sleep Coach', Icons.nightlight_round,
            (c) => _buildSleepCoachCard(c)),
        _ToolkitEntry('travel', 'Mindful Travel', Icons.flight_takeoff_rounded,
            (c) => _buildMindfulTravelCard(c)),
      ];

  /// Builds the visible tool cards (hidden ones filtered out), each followed
  /// by spacing. Shows a gentle empty-state when everything is hidden.
  List<Widget> _buildVisibleToolCards(BuildContext context, AppState appState) {
    final entries = _toolkitEntries(appState)
        .where((e) => !_hiddenTools.contains(e.id))
        .toList();

    if (entries.isEmpty) {
      return [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withOpacity(0.08)),
          ),
          child: Column(
            children: [
              Icon(Icons.tune_rounded,
                  size: 40,
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.4)),
              const SizedBox(height: 12),
              const Text('No tools shown',
                  style:
                      TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 6),
              Text('Tap the customize button above to add tools back.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.5),
                      fontSize: 13)),
            ],
          ),
        ),
      ];
    }

    final widgets = <Widget>[];
    for (var i = 0; i < entries.length; i++) {
      widgets.add(entries[i].builder(context));
      if (i < entries.length - 1) widgets.add(const SizedBox(height: 16));
    }
    return widgets;
  }

  /// Opens the shared Customize Toolkit sheet, then reloads visibility so the
  /// tool cards refresh. The same sheet is used by the Habit Builder screen, so
  /// both stay in sync.
  Future<void> _showCustomizeSheet(
      BuildContext context, AppState appState) async {
    await showToolkitCustomizeSheet(context);
    await _loadHiddenTools();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Consumer<AppState>(
      builder: (context, appState, child) {
        return Scaffold(
          backgroundColor: isDark ? const Color(0xFF0F1115) : const Color(0xFFF8F9FB),
          body: Stack(
            children: [
              CustomScrollView(
                slivers: [
                  _buildSliverAppBar(context, appState),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24.0, vertical: 16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ..._buildVisibleToolCards(context, appState),
                          const SizedBox(height: 120),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSliverAppBar(BuildContext context, AppState appState) {
    return SliverAppBar(
      expandedHeight: 110.0,
      floating: false,
      pinned: true,
      elevation: 0,
      backgroundColor: Colors.transparent,
      actions: [
        IconButton(
          icon: const Icon(Icons.tune_rounded),
          tooltip: 'Customize tools',
          onPressed: () => _showCustomizeSheet(context, appState),
        ),
        const SizedBox(width: 4),
      ],
      flexibleSpace: FlexibleSpaceBar(
        centerTitle: true,
        titlePadding: const EdgeInsets.only(bottom: 14),
        // FittedBox scales the two-line title down as the bar collapses,
        // preventing a bottom RenderFlex overflow.
        title: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "LIFE TOOLKIT",
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.0,
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                "Tools to elevate your wellness and life",
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color:
                      Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildPeriodTrackerCard(BuildContext context, AppState appState) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final data = appState.periodData;
    const accent = Color(0xFFE9506E);

    final phase = data.currentPhase;
    final until = data.daysUntilNextPeriod;

    final String summary;
    if (!data.hasData) {
      summary = 'Tap to log your first period';
    } else if (until != null && until >= 0) {
      summary = until == 0
          ? 'Period likely today · ${phase.label}'
          : 'Next period in $until day${until == 1 ? '' : 's'} · ${phase.label}';
    } else {
      summary = 'Period ${-(until ?? 0)} day(s) late · ${phase.label}';
    }

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PeriodTrackerScreen()),
        );
      },
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [accent.withOpacity(0.25), accent.withOpacity(0.08)]
                : [accent.withOpacity(0.18), accent.withOpacity(0.06)],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: accent.withOpacity(0.3), width: 2),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            children: [
              Positioned(
                right: -20,
                bottom: -20,
                child: Icon(Icons.water_drop_rounded,
                    size: 120, color: accent.withOpacity(0.08)),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: accent.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.water_drop_rounded,
                          color: accent, size: 26),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text(
                                'Period Tracker',
                                style: TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.w900),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: accent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Text(
                                  'NEW',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            summary,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        color: accent.withOpacity(0.8)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSleepCoachCard(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const accent = Color(0xFF6C63FF);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SleepCoachEntry()),
        );
      },
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [accent.withOpacity(0.28), accent.withOpacity(0.1)]
                : [accent.withOpacity(0.2), accent.withOpacity(0.07)],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: accent.withOpacity(0.35), width: 2),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            children: [
              Positioned(
                right: -20,
                bottom: -20,
                child: Icon(Icons.nightlight_round,
                    size: 120, color: accent.withOpacity(0.1)),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: accent.withOpacity(0.18),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.nightlight_round,
                          color: accent, size: 26),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Flexible(
                                child: Text(
                                  'Sleep Coach',
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: accent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Text(
                                  'NEW',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Understand your sleep and build better habits.',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        color: accent.withOpacity(0.8)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMeditationCard(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const accent = Color(0xFF6C63FF);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MeditationHomeScreen()),
        );
      },
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [accent.withOpacity(0.28), accent.withOpacity(0.1)]
                : [accent.withOpacity(0.2), accent.withOpacity(0.07)],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: accent.withOpacity(0.35), width: 2),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            children: [
              Positioned(
                right: -20,
                bottom: -20,
                child: Icon(Icons.self_improvement_rounded,
                    size: 120, color: accent.withOpacity(0.1)),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: accent.withOpacity(0.18),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.self_improvement_rounded,
                          color: accent, size: 26),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Flexible(
                                child: Text(
                                  'Meditation Pal',
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: accent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Text(
                                  'NEW',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Breathe, meditate, and find your calm.',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        color: accent.withOpacity(0.8)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMindfulTravelCard(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const accent = Color(0xFF3A7BD5);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const TravelScreen()),
        );
      },
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [accent.withOpacity(0.28), accent.withOpacity(0.1)]
                : [accent.withOpacity(0.2), accent.withOpacity(0.07)],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: accent.withOpacity(0.35), width: 2),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            children: [
              Positioned(
                right: -20,
                bottom: -20,
                child: Icon(Icons.flight_takeoff_rounded,
                    size: 120, color: accent.withOpacity(0.1)),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: accent.withOpacity(0.18),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.flight_takeoff_rounded,
                          color: accent, size: 26),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Flexible(
                                child: Text(
                                  'Mindful Travel',
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: accent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Text(
                                  'NEW',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Travel well. AI wellness guidance for every trip.',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        color: accent.withOpacity(0.8)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHydrationCard(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const accent = Color(0xFF3FA9F5);
    return Consumer<HydrationState>(
      builder: (context, hydration, _) {
        final pct = hydration.completionPercentage;
        final String summary;
        if (hydration.consumedMl == 0) {
          summary = 'Track your water & build a hydration streak';
        } else {
          summary =
              '$pct% of goal · ${(hydration.consumedMl / 1000).toStringAsFixed(1)}L today';
        }

        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HydrationCoachScreen()),
            );
          },
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [accent.withOpacity(0.28), accent.withOpacity(0.1)]
                    : [accent.withOpacity(0.2), accent.withOpacity(0.07)],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: accent.withOpacity(0.35), width: 2),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Stack(
                children: [
                  Positioned(
                    right: -20,
                    bottom: -20,
                    child: Icon(Icons.water_drop_rounded,
                        size: 120, color: accent.withOpacity(0.1)),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: accent.withOpacity(0.18),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.water_drop_rounded,
                              color: accent, size: 26),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Flexible(
                                    child: Text(
                                      'AI Hydration Coach',
                                      style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w900),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: accent,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Text(
                                      'NEW',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                summary,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withOpacity(0.7),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded,
                            color: accent.withOpacity(0.8)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCalorieBudgetCard(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const accent = Color(0xFFF5A623);

    return Consumer<CalorieBudgetState>(
      builder: (context, budget, _) {
        final s = budget.summary;
        final String summary;
        if (s.consumed == 0 && s.burned == 0) {
          summary = 'Track your daily energy balance';
        } else if (s.isOverBudget) {
          summary = '${s.remaining.abs()} kcal over · ${s.consumed} eaten';
        } else {
          summary = '${s.remaining} kcal remaining today';
        }

        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CalorieBudgetScreen()),
            );
          },
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [accent.withOpacity(0.28), accent.withOpacity(0.1)]
                    : [accent.withOpacity(0.2), accent.withOpacity(0.07)],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: accent.withOpacity(0.35), width: 2),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Stack(
                children: [
                  Positioned(
                    right: -20,
                    bottom: -20,
                    child: Icon(Icons.local_fire_department_rounded,
                        size: 120, color: accent.withOpacity(0.1)),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: accent.withOpacity(0.18),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                              Icons.local_fire_department_rounded,
                              color: accent,
                              size: 26),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Flexible(
                                    child: Text(
                                      'AI Calorie Budget',
                                      style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w900),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: accent,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Text(
                                      'NEW',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                summary,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withOpacity(0.7),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded,
                            color: accent.withOpacity(0.8)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMealPlannerCard(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const accent = Color(0xFFEF8354);

    return Consumer<MealPlannerState>(
      builder: (context, planner, _) {
        final plan = planner.activePlan;
        final String summary;
        if (plan == null) {
          summary = 'Generate a personalized AI meal plan';
        } else {
          summary =
              '${plan.goal.label} · ${plan.dietMode.label} · ~${plan.dailyCalories} kcal';
        }

        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MealPlannerScreen()),
            );
          },
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [accent.withOpacity(0.28), accent.withOpacity(0.1)]
                    : [accent.withOpacity(0.2), accent.withOpacity(0.07)],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: accent.withOpacity(0.35), width: 2),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Stack(
                children: [
                  Positioned(
                    right: -20,
                    bottom: -20,
                    child: Icon(Icons.apple_rounded,
                        size: 120, color: accent.withOpacity(0.1)),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: accent.withOpacity(0.18),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.apple_rounded,
                              color: accent, size: 26),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Flexible(
                                    child: Text(
                                      'AI Meal Planner',
                                      style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w900),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: accent,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Text(
                                      'NEW',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                summary,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withOpacity(0.7),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded,
                            color: accent.withOpacity(0.8)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildNutritionCoachCard(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const accent = Color(0xFF57B894);

    return Consumer<NutritionState>(
      builder: (context, nutrition, _) {
        final totals = nutrition.todaysTotals;
        final String summary;
        if (totals.mealCount == 0) {
          summary = 'Snap, scan or describe your meals';
        } else {
          summary =
              '${totals.calories} kcal today · ${totals.mealCount} meal${totals.mealCount == 1 ? '' : 's'} logged';
        }

        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const NutritionCoachScreen()),
            );
          },
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [accent.withOpacity(0.28), accent.withOpacity(0.1)]
                    : [accent.withOpacity(0.2), accent.withOpacity(0.07)],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: accent.withOpacity(0.35), width: 2),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Stack(
                children: [
                  Positioned(
                    right: -20,
                    bottom: -20,
                    child: Icon(Icons.restaurant_menu_rounded,
                        size: 120, color: accent.withOpacity(0.1)),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: accent.withOpacity(0.18),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.restaurant_menu_rounded,
                              color: accent, size: 26),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Flexible(
                                    child: Text(
                                      'AI Nutrition Coach',
                                      style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w900),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: accent,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Text(
                                      'NEW',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                summary,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withOpacity(0.7),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded,
                            color: accent.withOpacity(0.8)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildWeightTrackerCard(BuildContext context, AppState appState) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final data = appState.weightData;
    const accent = Color(0xFF5C9EAD);
    final unit = data.unit;

    final String summary;
    if (!data.hasData) {
      summary = 'Tap to log your first weigh-in';
    } else {
      final current = data.currentInUnit!;
      final change = data.totalChangeKg;
      final base = '${current.toStringAsFixed(1)} ${unit.label}';
      if (change == null || change.abs() <= 0.05) {
        summary = '$base · tracking';
      } else {
        final v = unit.fromKg(change.abs()).toStringAsFixed(1);
        summary = change > 0
            ? '$base · up $v ${unit.label} overall'
            : '$base · down $v ${unit.label} overall';
      }
    }

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const WeightTrackerScreen()),
        );
      },
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [accent.withOpacity(0.25), accent.withOpacity(0.08)]
                : [accent.withOpacity(0.18), accent.withOpacity(0.06)],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: accent.withOpacity(0.3), width: 2),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            children: [
              Positioned(
                right: -20,
                bottom: -20,
                child: Icon(Icons.monitor_weight_rounded,
                    size: 120, color: accent.withOpacity(0.08)),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: accent.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.monitor_weight_rounded,
                          color: accent, size: 26),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text(
                                'Body Weight',
                                style: TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.w900),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: accent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Text(
                                  'NEW',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            summary,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        color: accent.withOpacity(0.8)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A registry entry describing a Life Toolkit tool: its stable id, label,
/// icon (for the customize sheet), and the card builder used in the list.
class _ToolkitEntry {
  final String id;
  final String label;
  final IconData icon;
  final Widget Function(BuildContext context) builder;

  const _ToolkitEntry(this.id, this.label, this.icon, this.builder);
}
