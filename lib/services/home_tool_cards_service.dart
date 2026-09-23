import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The wellness-tool summary cards a user can add to the Home screen.
///
/// These ids are stable and used as Home card ids (so the existing pin /
/// re-arrange / order-persistence machinery treats them exactly like the
/// default Home cards). Keep the string values stable across releases.
class HomeToolCard {
  const HomeToolCard._();

  // Nutrition Coach
  static const String nutrition = 'tool_nutrition_progress';
  static const String nutritionCoach = 'tool_nutrition_coach';
  static const String nutritionRecentMeals = 'tool_nutrition_recent_meals';

  // AI Meal Planner
  static const String mealPlanner = 'tool_meal_today';
  static const String mealNutritionSummary = 'tool_meal_nutrition_summary';
  static const String mealInsights = 'tool_meal_insights';
  static const String mealWeeklyOverview = 'tool_meal_weekly_overview';
  static const String mealGrocery = 'tool_meal_grocery';

  // Calorie Budget
  static const String calorieBudget = 'tool_calorie_ring';
  static const String calorieInsight = 'tool_calorie_insight';
  static const String calorieStreak = 'tool_calorie_streak';
  static const String calorieTimeline = 'tool_calorie_timeline';
  static const String calorieWeekly = 'tool_calorie_weekly';

  // Period Tracker
  static const String periodTracker = 'tool_period_ring';
  static const String periodPrediction = 'tool_period_prediction';
  static const String periodPhase = 'tool_period_phase';

  // Hydration Coach
  static const String hydration = 'tool_hydration_ring';
  static const String hydrationInsights = 'tool_hydration_insights';
  static const String hydrationScore = 'tool_hydration_score';
  static const String hydrationStreak = 'tool_hydration_streak';
  static const String hydrationTimeline = 'tool_hydration_timeline';
  static const String hydrationWeekly = 'tool_hydration_weekly';

  // Body Weight
  static const String bodyWeight = 'tool_body_weight';
  static const String bodyWeightChart = 'tool_body_weight_chart';
  static const String bodyWeightBmi = 'tool_body_weight_bmi';
  static const String bodyWeightHistory = 'tool_body_weight_history';

  /// All addable tool-card ids.
  static const List<String> all = [
    // Nutrition
    nutrition,
    nutritionCoach,
    nutritionRecentMeals,
    // Meal Planner
    mealPlanner,
    mealNutritionSummary,
    mealInsights,
    mealWeeklyOverview,
    mealGrocery,
    // Calorie Budget
    calorieBudget,
    calorieInsight,
    calorieStreak,
    calorieTimeline,
    calorieWeekly,
    // Period Tracker
    periodTracker,
    periodPrediction,
    periodPhase,
    // Hydration
    hydration,
    hydrationInsights,
    hydrationScore,
    hydrationStreak,
    hydrationTimeline,
    hydrationWeekly,
    // Body Weight
    bodyWeight,
    bodyWeightChart,
    bodyWeightBmi,
    bodyWeightHistory,
  ];

  /// Human-readable title for a tool card id (used in menus and the Home
  /// re-arrange tiles).
  static String titleFor(String id) {
    switch (id) {
      // Nutrition
      case nutrition:
        return "Today's Progress";
      case nutritionCoach:
        return 'Coach Insights';
      case nutritionRecentMeals:
        return 'Recent Meals';
      // Meal Planner
      case mealPlanner:
        return "Today's Meals";
      case mealNutritionSummary:
        return "Today's Nutrition";
      case mealInsights:
        return 'Meal Plan Insights';
      case mealWeeklyOverview:
        return 'Weekly Meal Plan';
      case mealGrocery:
        return 'Grocery List';
      // Calorie Budget
      case calorieBudget:
        return 'Calorie Budget';
      case calorieInsight:
        return 'Calorie Insights';
      case calorieStreak:
        return 'Calorie Streak';
      case calorieTimeline:
        return "Today's Timeline";
      case calorieWeekly:
        return 'Calorie · Last 7 Days';
      // Period Tracker
      case periodTracker:
        return 'Period Tracker';
      case periodPrediction:
        return 'Cycle Predictions';
      case periodPhase:
        return 'Phase Insight';
      // Hydration
      case hydration:
        return 'Hydration';
      case hydrationInsights:
        return 'Hydration Insights';
      case hydrationScore:
        return 'Hydration Score';
      case hydrationStreak:
        return 'Hydration Streak';
      case hydrationTimeline:
        return 'Hydration Timeline';
      case hydrationWeekly:
        return 'Hydration · Last 7 Days';
      // Body Weight
      case bodyWeight:
        return 'Body Weight';
      case bodyWeightChart:
        return 'Weight Trend';
      case bodyWeightBmi:
        return 'BMI';
      case bodyWeightHistory:
        return 'Weight History';
      default:
        return 'Wellness Card';
    }
  }

  static bool isToolCard(String id) => all.contains(id);

  /// Keyword/alias phrases that map a spoken request to a card id. Each entry's
  /// phrases are lower-cased; [resolveFromSpeech] scores a query against them.
  /// Order roughly follows the tool grouping. Used by the Live pal's
  /// `manage_home_card` voice action so users can say e.g. "add my weight
  /// history to the home screen".
  static const Map<String, List<String>> _spokenAliases = {
    nutrition: ['nutrition progress', "today's progress", 'daily progress',
        'nutrition today', 'macros progress'],
    nutritionCoach: ['coach insights', 'nutrition coach', 'coach feedback',
        'nutrition insights', 'coaching'],
    nutritionRecentMeals: ['recent meals', 'last meals', 'meals i logged',
        'recently logged meals'],
    mealPlanner: ["today's meals", 'meal plan today', 'planned meals',
        'my meals', 'meal planner today'],
    mealNutritionSummary: ["today's nutrition", 'daily nutrition',
        'nutrition summary', 'plan nutrition'],
    mealInsights: ['meal plan insights', 'meal insights', 'plan insights'],
    mealWeeklyOverview: ['weekly meal plan', 'weekly overview',
        'monthly meal plan', 'meal plan overview', 'week plan'],
    mealGrocery: ['grocery list', 'shopping list', 'groceries'],
    calorieBudget: ['calorie budget', 'calories remaining', 'calorie ring',
        'energy balance', 'kcal remaining', 'calorie dashboard'],
    calorieInsight: ['calorie insights', 'calorie prediction', 'ai prediction',
        'calorie ai'],
    calorieStreak: ['calorie streak', 'budget streak', 'goal streak'],
    calorieTimeline: ["today's timeline", 'calorie timeline',
        'food timeline', 'daily timeline'],
    calorieWeekly: ['calorie weekly', 'calories last 7 days',
        'weekly calories', 'calorie trend'],
    periodTracker: ['period tracker', 'cycle ring', 'cycle tracker',
        'my cycle', 'period ring'],
    periodPrediction: ['cycle predictions', 'next period', 'ovulation',
        'period prediction', 'fertile window'],
    periodPhase: ['phase insight', 'cycle phase', 'period phase',
        'phase tips'],
    hydration: ['hydration', 'water intake', 'hydration ring', 'water ring',
        'hydration progress', 'drink water progress'],
    hydrationInsights: ['hydration insights', 'smart insights', 'water insights',
        'hydration reminders'],
    hydrationScore: ['hydration score', 'water score'],
    hydrationStreak: ['hydration streak', 'water streak'],
    hydrationTimeline: ['hydration timeline', 'water timeline',
        'water log timeline'],
    hydrationWeekly: ['hydration weekly', 'water last 7 days',
        'weekly hydration', 'hydration trend'],
    bodyWeight: ['body weight', 'current weight', 'weight', 'my weight'],
    bodyWeightChart: ['weight trend', 'weight chart', 'weight graph',
        'weight over time'],
    bodyWeightBmi: ['bmi', 'body mass index'],
    bodyWeightHistory: ['weight history', 'weight log', 'past weights',
        'weight entries'],
  };

  /// Resolves a free-text spoken phrase (e.g. "my weight history",
  /// "calorie streak card") to a card id, or null if nothing matches well
  /// enough. Case-insensitive; scores each card by how many of its alias
  /// phrases the query contains, preferring the longest phrase matched so
  /// "hydration score" beats a bare "hydration".
  static String? resolveFromSpeech(String query) {
    final matches = resolveCandidatesFromSpeech(query);
    return matches.length == 1 ? matches.first : null;
  }

  /// Like [resolveFromSpeech] but returns EVERY card whose best-matching alias
  /// phrase ties for the longest match — so the caller can disambiguate when a
  /// vague phrase (e.g. "insights") maps to several tools. Returns an empty
  /// list when nothing matches, one id for a clear match, or multiple ids for
  /// an ambiguous one.
  static List<String> resolveCandidatesFromSpeech(String query) {
    final q = query
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (q.isEmpty) return const [];

    // For each card, the length of its longest alias phrase contained in the
    // query (0 if none match). Then keep all cards tied at the global best.
    final matchLen = <String, int>{};
    var bestLen = 0;
    _spokenAliases.forEach((id, phrases) {
      var cardBest = 0;
      for (final phrase in phrases) {
        if (q.contains(phrase) && phrase.length > cardBest) {
          cardBest = phrase.length;
        }
      }
      if (cardBest > 0) {
        matchLen[id] = cardBest;
        if (cardBest > bestLen) bestLen = cardBest;
      }
    });
    if (bestLen == 0) return const [];
    return matchLen.entries
        .where((e) => e.value == bestLen)
        .map((e) => e.key)
        .toList();
  }

  /// A human-readable, comma-separated catalog of the addable cards grouped by
  /// tool, for embedding in the pal's app-knowledge so it knows what it can add.
  static String get spokenCatalog =>
      'Nutrition Coach: Today\'s Progress, Coach Insights, Recent Meals. '
      'Meal Planner: Today\'s Meals, Today\'s Nutrition, Meal Plan Insights, '
      'Weekly Meal Plan, Grocery List. '
      'Calorie Budget: Calorie Budget, Calorie Insights, Calorie Streak, '
      'Today\'s Timeline, Calorie Last 7 Days. '
      'Period Tracker: Period Tracker, Cycle Predictions, Phase Insight. '
      'Hydration: Hydration, Hydration Insights, Hydration Score, '
      'Hydration Streak, Hydration Timeline, Hydration Last 7 Days. '
      'Body Weight: Body Weight, Weight Trend, BMI, Weight History.';

  /// Representative icon for a tool card id (used in the Home section header so
  /// tool cards match the default Home cards' icon + title formatting).
  static IconData iconFor(String id) {
    switch (id) {
      // Nutrition
      case nutrition:
        return Icons.restaurant_rounded;
      case nutritionCoach:
        return Icons.tips_and_updates_rounded;
      case nutritionRecentMeals:
        return Icons.history_rounded;
      // Meal Planner
      case mealPlanner:
        return Icons.restaurant_menu_rounded;
      case mealNutritionSummary:
        return Icons.pie_chart_rounded;
      case mealInsights:
        return Icons.auto_awesome_rounded;
      case mealWeeklyOverview:
        return Icons.calendar_view_week_rounded;
      case mealGrocery:
        return Icons.shopping_cart_rounded;
      // Calorie Budget
      case calorieBudget:
        return Icons.local_fire_department_rounded;
      case calorieInsight:
        return Icons.auto_awesome_rounded;
      case calorieStreak:
        return Icons.emoji_events_rounded;
      case calorieTimeline:
        return Icons.timeline_rounded;
      case calorieWeekly:
        return Icons.bar_chart_rounded;
      // Period Tracker
      case periodTracker:
        return Icons.female_rounded;
      case periodPrediction:
        return Icons.event_rounded;
      case periodPhase:
        return Icons.spa_rounded;
      // Hydration
      case hydration:
        return Icons.water_drop_rounded;
      case hydrationInsights:
        return Icons.auto_awesome_rounded;
      case hydrationScore:
        return Icons.speed_rounded;
      case hydrationStreak:
        return Icons.emoji_events_rounded;
      case hydrationTimeline:
        return Icons.timeline_rounded;
      case hydrationWeekly:
        return Icons.bar_chart_rounded;
      // Body Weight
      case bodyWeight:
        return Icons.monitor_weight_rounded;
      case bodyWeightChart:
        return Icons.show_chart_rounded;
      case bodyWeightBmi:
        return Icons.straighten_rounded;
      case bodyWeightHistory:
        return Icons.history_rounded;
      default:
        return Icons.dashboard_customize_rounded;
    }
  }
}

/// Single source of truth for WHICH wellness-tool cards the user has added to
/// their Home screen. Shared by the tool screens (which add/remove) and the
/// Home screen (which renders them).
///
/// Persists the enabled set to SharedPreferences (instant, offline) and mirrors
/// it to the user's Firestore profile doc so it follows them across devices —
/// matching how the Home card ORDER is persisted.
class HomeToolCardsService extends ChangeNotifier {
  HomeToolCardsService({FirebaseFirestore? db, FirebaseAuth? auth})
      : _db = db ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  static const String _prefsKey = 'wellness_home_tool_cards';
  static const String _firestoreField = 'home_tool_cards';

  final Set<String> _enabled = {};
  bool _loaded = false;

  /// The tool-card ids currently on Home, in the order they were added.
  /// (Home ordering/pinning is layered on top by the Home screen.)
  List<String> get enabled => _enabled.toList();

  bool isEnabled(String id) => _enabled.contains(id);

  bool get isLoaded => _loaded;

  /// Loads the enabled set: local cache first (instant), then reconcile with
  /// the cloud copy so the set follows the user across devices.
  Future<void> load({Map<String, dynamic>? cloudProfile}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final local = prefs.getStringList(_prefsKey);
      if (local != null) {
        _enabled
          ..clear()
          ..addAll(local.where(HomeToolCard.isToolCard));
      }
    } catch (e) {
      debugPrint('HomeToolCardsService: local load failed: $e');
    }

    // Reconcile with the cloud copy if provided (or fetched).
    try {
      List<dynamic>? cloud;
      if (cloudProfile != null) {
        cloud = cloudProfile[_firestoreField] as List<dynamic>?;
      } else {
        final uid = _auth.currentUser?.uid;
        if (uid != null) {
          final doc = await _db.collection('users').doc(uid).get();
          cloud = doc.data()?[_firestoreField] as List<dynamic>?;
        }
      }
      if (cloud != null) {
        _enabled
          ..clear()
          ..addAll(cloud.map((e) => e.toString()).where(HomeToolCard.isToolCard));
        // Keep local cache in step with the cloud.
        unawaited(_writeLocal());
      }
    } catch (e) {
      debugPrint('HomeToolCardsService: cloud load failed: $e');
    }

    _loaded = true;
    notifyListeners();
  }

  /// Adds [id] to Home (idempotent) and persists.
  Future<void> add(String id) async {
    if (!HomeToolCard.isToolCard(id) || _enabled.contains(id)) return;
    _enabled.add(id);
    notifyListeners();
    await _persist();
  }

  /// Removes [id] from Home (idempotent) and persists.
  Future<void> remove(String id) async {
    if (!_enabled.remove(id)) return;
    notifyListeners();
    await _persist();
  }

  /// Toggles [id]'s presence on Home. Returns the new enabled state.
  Future<bool> toggle(String id) async {
    if (_enabled.contains(id)) {
      await remove(id);
      return false;
    }
    await add(id);
    return true;
  }

  Future<void> _persist() async {
    await _writeLocal();
    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      try {
        await _db.collection('users').doc(uid).set(
          {_firestoreField: _enabled.toList()},
          SetOptions(merge: true),
        );
      } catch (e) {
        debugPrint('HomeToolCardsService: Firestore mirror failed: $e');
      }
    }
  }

  Future<void> _writeLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefsKey, _enabled.toList());
    } catch (e) {
      debugPrint('HomeToolCardsService: local write failed: $e');
    }
  }
}
