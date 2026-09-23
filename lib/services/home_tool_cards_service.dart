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
