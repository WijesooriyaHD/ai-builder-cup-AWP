import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../../nutrition/domain/nutrition_models.dart' show MealTypeInfo;
import '../data/gemini_meal_planner_service.dart';
import '../data/meal_plan_repository.dart';
import '../domain/meal_planner_models.dart';
import '../domain/meal_planner_service.dart';

/// Presentation-layer state for the AI Meal Planner.
///
/// Depends on the [MealPlannerService] abstraction (default: Gemini) and
/// [MealPlanRepository], so the AI provider can be swapped freely.
class MealPlannerState extends ChangeNotifier {
  final MealPlannerService _service;
  final MealPlanRepository _repo;

  MealPlannerState({
    MealPlannerService? service,
    MealPlanRepository? repository,
  })  : _service = service ?? GeminiMealPlannerService(),
        _repo = repository ?? MealPlanRepository();

  // --- state ---
  UserProfile? _profile;
  MealPlan? _activePlan;
  List<PlannedMeal> _favoriteMeals = [];
  Map<String, int> _preferenceCounts = {};
  bool _isLoading = false;
  bool _isGenerating = false;
  bool _isBuildingGrocery = false;
  String? _error;
  PlanSaveResult? _lastSaveResult;

  UserProfile? get profile => _profile;
  MealPlan? get activePlan => _activePlan;
  List<PlannedMeal> get favoriteMeals => _favoriteMeals;
  bool get isLoading => _isLoading;
  bool get isGenerating => _isGenerating;
  bool get isBuildingGrocery => _isBuildingGrocery;
  String? get error => _error;

  /// The outcome of the most recent plan persistence, so the UI can reassure
  /// the user their plan is saved to their account (or warn it's device-only).
  PlanSaveResult? get lastSaveResult => _lastSaveResult;

  /// True when the active plan is confirmed saved to the user's Firebase
  /// account (not just cached on-device).
  bool get isActivePlanSyncedToCloud =>
      _lastSaveResult == PlanSaveResult.synced;

  bool get hasProfile => _profile != null && _profile!.isComplete;

  DayPlan? get todayPlan =>
      (_activePlan != null && _activePlan!.days.isNotEmpty)
          ? _activePlan!.days.first
          : null;

  bool isFavoriteMeal(PlannedMeal m) =>
      _favoriteMeals.any((f) => f.name.toLowerCase() == m.name.toLowerCase());

  // ---------------------------------------------------------------------------
  // Home-screen widget sync
  // ---------------------------------------------------------------------------

  /// Mirrors today's planned meals into the shared app group so the
  /// home-screen "Meal Planner" widget can show them one at a time (with the
  /// up/down arrows cycling through them). Writes an ordered set of keys:
  /// meal_count + meal_N_name / meal_N_type / meal_N_cal for N in 0..count-1.
  Future<void> syncMealPlannerWidget() async {
    try {
      await HomeWidget.setAppGroupId('group.com.aiwellnesspal.app');
      final meals = todayPlan?.allMeals ?? const <PlannedMeal>[];
      // Cap at 6 so the widget key set stays bounded.
      final capped = meals.take(6).toList();
      await HomeWidget.saveWidgetData<int>('meal_count', capped.length);
      for (var i = 0; i < 6; i++) {
        if (i < capped.length) {
          final m = capped[i];
          await HomeWidget.saveWidgetData<String>('meal_${i}_name', m.name);
          await HomeWidget.saveWidgetData<String>(
              'meal_${i}_type', m.type.label);
          await HomeWidget.saveWidgetData<int>('meal_${i}_cal', m.calories);
        } else {
          // Clear stale slots.
          await HomeWidget.saveWidgetData<String>('meal_${i}_name', '');
          await HomeWidget.saveWidgetData<String>('meal_${i}_type', '');
          await HomeWidget.saveWidgetData<int>('meal_${i}_cal', 0);
        }
      }
      await HomeWidget.updateWidget(
          name: 'MealPlannerToolWidget', androidName: 'MealPlannerToolWidget');
    } catch (e) {
      debugPrint('ℹ️ MealPlannerState.syncMealPlannerWidget: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Loading
  // ---------------------------------------------------------------------------
  Future<void> load() async {
    _isLoading = true;
    notifyListeners();
    try {
      final results = await Future.wait([
        _repo.loadProfile(),
        _repo.loadActivePlan(),
        _repo.loadFavoriteMeals(),
        _repo.loadPreferenceCounts(),
      ]);
      _profile = results[0] as UserProfile?;
      _activePlan = results[1] as MealPlan?;
      _favoriteMeals = results[2] as List<PlannedMeal>;
      _preferenceCounts = results[3] as Map<String, int>;
    } catch (e) {
      debugPrint('❌ MealPlannerState.load: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
      // ignore: unawaited_futures
      syncMealPlannerWidget();
    }
  }

  // ---------------------------------------------------------------------------
  // Profile
  // ---------------------------------------------------------------------------
  Future<void> saveProfile(UserProfile profile) async {
    _profile = profile;
    notifyListeners();
    await _repo.saveProfile(profile);
  }

  // ---------------------------------------------------------------------------
  // Generation
  // ---------------------------------------------------------------------------
  Future<bool> generate({
    required PlanType planType,
    required DietMode dietMode,
    List<String> include = const [],
    List<String> exclude = const [],
  }) async {
    final profile = _profile;
    if (profile == null) {
      _error = 'Please complete your profile first.';
      notifyListeners();
      return false;
    }
    _isGenerating = true;
    _error = null;
    notifyListeners();
    try {
      final plan = await _service.generatePlan(
        profile,
        planType: planType,
        dietMode: dietMode,
        include: include,
        exclude: exclude,
      );
      _activePlan = plan;
      // ignore: unawaited_futures
      syncMealPlannerWidget();
      // Persist to local cache + Firebase and remember the outcome so the UI
      // can confirm the plan is saved to the user's account.
      _lastSaveResult = await _repo.savePlan(plan);
      if (_lastSaveResult == PlanSaveResult.cloudFailed) {
        debugPrint('⚠️ MealPlannerState.generate: plan cached locally but the '
            'Firebase sync failed; will remain device-only until re-saved.');
      }
      _trackChosenMeals(plan);
      return true;
    } on MealPlannerException catch (e) {
      _error = e.message;
      return false;
    } catch (e) {
      debugPrint('❌ MealPlannerState.generate: $e');
      _error = 'Something went wrong. Please try again.';
      return false;
    } finally {
      _isGenerating = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Meal swap
  // ---------------------------------------------------------------------------
  Future<MealSuggestion?> fetchAlternatives(PlannedMeal meal) async {
    final profile = _profile;
    final plan = _activePlan;
    if (profile == null || plan == null) return null;
    // Swap failures are surfaced inline by the swap sheet (with a Try again
    // button), so we don't set the global error banner here — otherwise a
    // failed first attempt would leave a stale banner on the main screen.
    try {
      return await _service.replaceMeal(meal,
          profile: profile, dietMode: plan.dietMode);
    } on MealPlannerException catch (e) {
      debugPrint('❌ MealPlannerState.fetchAlternatives: ${e.message}');
      return null;
    } catch (e) {
      debugPrint('❌ MealPlannerState.fetchAlternatives: $e');
      return null;
    }
  }

  /// Replaces [original] in day 0 of the active plan with [replacement].
  Future<void> replaceMealInPlan(
      PlannedMeal original, PlannedMeal replacement) async {
    final plan = _activePlan;
    if (plan == null || plan.days.isEmpty) return;

    // Track the skip (original) and the choice (replacement).
    _bumpPreference(original.name, -1);
    _bumpPreference(replacement.name, 1);

    // Preserve the original's id and type so replace() targets the right slot
    // (snacks are matched by id; main meals by type).
    final replacementInSlot = PlannedMeal(
      id: original.id,
      type: original.type,
      name: replacement.name,
      calories: replacement.calories,
      macros: replacement.macros,
      reason: replacement.reason,
    );
    final newFirst = plan.days.first.replace(replacementInSlot);
    final newDays = [newFirst, ...plan.days.skip(1)];
    _activePlan = plan.copyWith(days: newDays);
    // A successful swap clears any lingering swap error.
    _error = null;
    notifyListeners();
    // ignore: unawaited_futures
    syncMealPlannerWidget();
    await _repo.updatePlan(_activePlan!);
    await _repo.savePreferenceCounts(_preferenceCounts);
  }

  // ---------------------------------------------------------------------------
  // Grocery list
  // ---------------------------------------------------------------------------
  Future<void> buildGroceryList() async {
    final plan = _activePlan;
    if (plan == null) return;
    _isBuildingGrocery = true;
    notifyListeners();
    try {
      final list = await _service.generateShoppingList(plan);
      _activePlan = plan.copyWith(groceryList: list);
      await _repo.updatePlan(_activePlan!);
    } on MealPlannerException catch (e) {
      _error = e.message;
    } catch (e) {
      debugPrint('❌ MealPlannerState.buildGroceryList: $e');
    } finally {
      _isBuildingGrocery = false;
      notifyListeners();
    }
  }

  Future<void> toggleGroceryItem(String name) async {
    final plan = _activePlan;
    if (plan == null) return;
    _activePlan = plan.copyWith(groceryList: plan.groceryList.toggle(name));
    notifyListeners();
    await _repo.updatePlan(_activePlan!);
  }

  /// Clears the current plan (keeps profile and favorites).
  Future<void> resetPlan() async {
    _activePlan = null;
    // ignore: unawaited_futures
    syncMealPlannerWidget();
    _error = null;
    notifyListeners();
    await _repo.clearActivePlan();
  }

  // ---------------------------------------------------------------------------
  // Favorites + personalization
  // ---------------------------------------------------------------------------
  Future<void> toggleFavoriteMeal(PlannedMeal meal) async {
    if (isFavoriteMeal(meal)) {
      _favoriteMeals = _favoriteMeals
          .where((f) => f.name.toLowerCase() != meal.name.toLowerCase())
          .toList();
    } else {
      _favoriteMeals = [meal, ..._favoriteMeals];
      _bumpPreference(meal.name, 2); // favoriting is a strong signal
    }
    notifyListeners();
    await _repo.saveFavoriteMeals(_favoriteMeals);
    await _repo.savePreferenceCounts(_preferenceCounts);
  }

  void _trackChosenMeals(MealPlan plan) {
    for (final d in plan.days) {
      for (final m in d.allMeals) {
        _bumpPreference(m.name, 1);
      }
    }
    _repo.savePreferenceCounts(_preferenceCounts);
  }

  void _bumpPreference(String name, int delta) {
    final key = name.trim().toLowerCase();
    if (key.isEmpty) return;
    _preferenceCounts[key] = (_preferenceCounts[key] ?? 0) + delta;
  }
}
