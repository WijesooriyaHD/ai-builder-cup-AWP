import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:uuid/uuid.dart';

import '../data/gemini_nutrition_service.dart';
import '../data/meal_repository.dart';
import '../domain/nutrition_analysis_service.dart';
import '../domain/nutrition_models.dart';

/// Presentation-layer state for the AI Nutrition Coach.
///
/// Depends on the [NutritionAnalysisService] abstraction (default: Gemini) and
/// [MealRepository], so the AI provider can be swapped without UI changes.
class NutritionState extends ChangeNotifier {
  final NutritionAnalysisService _analysis;
  final MealRepository _repo;
  final _uuid = const Uuid();

  NutritionState({
    NutritionAnalysisService? analysisService,
    MealRepository? repository,
  })  : _analysis = analysisService ?? GeminiNutritionService(),
        _repo = repository ?? MealRepository();

  // --- state ---
  List<Meal> _meals = [];
  NutritionGoals _goals = const NutritionGoals();
  bool _isLoading = false;
  bool _isAnalyzing = false;
  String? _error;

  List<Meal> get meals => _meals;
  NutritionGoals get goals => _goals;
  bool get isLoading => _isLoading;
  bool get isAnalyzing => _isAnalyzing;
  String? get error => _error;

  /// Meals logged today, newest first.
  List<Meal> get todaysMeals {
    final now = DateTime.now();
    return _meals
        .where((m) =>
            m.createdAt.year == now.year &&
            m.createdAt.month == now.month &&
            m.createdAt.day == now.day)
        .toList();
  }

  DailyTotals get todaysTotals => DailyTotals.fromMeals(todaysMeals);

  /// Recent meals (across days), newest first, capped for the dashboard.
  List<Meal> recentMeals([int limit = 5]) => _meals.take(limit).toList();

  List<Meal> mealsOfType(MealType type) =>
      todaysMeals.where((m) => m.mealType == type).toList();

  int get caloriesRemaining =>
      (_goals.calories - todaysTotals.calories).clamp(-9999, 99999);

  // ---------------------------------------------------------------------------
  // Home-screen widget sync
  // ---------------------------------------------------------------------------

  /// Mirrors today's nutrition progress into the shared app group so the
  /// home-screen "Nutrition Coach" widget can show today's calories + macros
  /// on its flipped data face. Safe to call after any state change.
  Future<void> syncNutritionWidget() async {
    try {
      await HomeWidget.setAppGroupId('group.com.aiwellnesspal.app');
      final t = todaysTotals;
      final pct = _goals.calories <= 0
          ? 0
          : ((t.calories / _goals.calories) * 100).round().clamp(0, 100);
      await HomeWidget.saveWidgetData<int>('nutrition_calories', t.calories);
      await HomeWidget.saveWidgetData<int>(
          'nutrition_calorie_goal', _goals.calories);
      await HomeWidget.saveWidgetData<int>('nutrition_pct', pct);
      await HomeWidget.saveWidgetData<int>(
          'nutrition_protein', t.macros.protein.round());
      await HomeWidget.saveWidgetData<int>(
          'nutrition_protein_goal', _goals.protein);
      await HomeWidget.saveWidgetData<int>(
          'nutrition_carbs', t.macros.carbs.round());
      await HomeWidget.saveWidgetData<int>(
          'nutrition_carbs_goal', _goals.carbs);
      await HomeWidget.saveWidgetData<int>(
          'nutrition_fat', t.macros.fat.round());
      await HomeWidget.saveWidgetData<int>('nutrition_fat_goal', _goals.fat);
      await HomeWidget.saveWidgetData<int>('nutrition_meal_count', t.mealCount);
      await HomeWidget.updateWidget(
          name: 'NutritionToolWidget', androidName: 'NutritionToolWidget');
    } catch (e) {
      debugPrint('ℹ️ NutritionState.syncNutritionWidget: $e');
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
        _repo.loadMeals(),
        _repo.loadGoals(),
      ]);
      _meals = results[0] as List<Meal>;
      _goals = results[1] as NutritionGoals;
    } catch (e) {
      debugPrint('❌ NutritionState.load: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
      // ignore: unawaited_futures
      syncNutritionWidget();
    }
  }

  // ---------------------------------------------------------------------------
  // Analysis (returns a NutritionResult to review before logging)
  // ---------------------------------------------------------------------------
  Future<NutritionResult?> analyzePhoto(File image) =>
      _runAnalysis(() => _analysis.analyzePhoto(image));

  Future<NutritionResult?> analyzeText(String text) =>
      _runAnalysis(() => _analysis.analyzeText(text));

  /// Returns the analyzed result, or throws [BarcodeNotFoundException] so the
  /// UI can offer manual entry / AI estimation.
  Future<NutritionResult?> analyzeBarcode(String barcode) =>
      _runAnalysis(() => _analysis.analyzeBarcode(barcode),
          rethrowNotFound: true);

  Future<NutritionResult?> _runAnalysis(
    Future<NutritionResult> Function() fn, {
    bool rethrowNotFound = false,
  }) async {
    _isAnalyzing = true;
    _error = null;
    notifyListeners();
    try {
      return await fn();
    } on BarcodeNotFoundException {
      if (rethrowNotFound) rethrow;
      _error = 'Product not found.';
      return null;
    } on NutritionAnalysisException catch (e) {
      _error = e.message;
      return null;
    } catch (e) {
      debugPrint('❌ NutritionState analysis: $e');
      _error = 'Something went wrong. Please try again.';
      return null;
    } finally {
      _isAnalyzing = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Logging
  // ---------------------------------------------------------------------------

  /// Saves an analyzed [result] as a meal. If [imageFile] is provided it is
  /// uploaded to Storage first. Optimistically updates local state.
  Future<Meal> logMeal(
    NutritionResult result, {
    required MealType mealType,
    File? imageFile,
  }) async {
    String? imageUrl;
    if (imageFile != null) {
      imageUrl = await _repo.uploadMealImage(imageFile);
    }

    final meal = Meal.fromResult(
      result,
      id: _uuid.v4(),
      mealType: mealType,
      imageUrl: imageUrl,
      createdAt: DateTime.now(),
    );

    // Optimistic insert (newest first).
    _meals = [meal, ..._meals];
    notifyListeners();
    // ignore: unawaited_futures
    syncNutritionWidget();

    await _repo.saveMeal(meal);
    return meal;
  }

  Future<void> deleteMeal(String mealId) async {
    _meals = _meals.where((m) => m.id != mealId).toList();
    notifyListeners();
    // ignore: unawaited_futures
    syncNutritionWidget();
    await _repo.deleteMeal(mealId);
  }

  /// Edits a logged meal's name / calories / meal type in place.
  Future<void> updateMeal(
    String mealId, {
    String? mealName,
    int? calories,
    MealType? mealType,
  }) async {
    Meal? updated;
    _meals = _meals.map((m) {
      if (m.id != mealId) return m;
      updated = Meal(
        id: m.id,
        mealName: mealName ?? m.mealName,
        mealType: mealType ?? m.mealType,
        imageUrl: m.imageUrl,
        calories: calories ?? m.calories,
        macros: m.macros,
        foodQualityScore: m.foodQualityScore,
        aiInsights: m.aiInsights,
        createdAt: m.createdAt,
      );
      return updated!;
    }).toList();
    notifyListeners();
    // ignore: unawaited_futures
    syncNutritionWidget();
    if (updated != null) await _repo.saveMeal(updated!);
  }

  Future<void> updateGoals(NutritionGoals goals) async {
    _goals = goals;
    notifyListeners();
    // ignore: unawaited_futures
    syncNutritionWidget();
    await _repo.saveGoals(goals);
  }

  // ---------------------------------------------------------------------------
  // Smart daily feedback (derived, non-clinical)
  // ---------------------------------------------------------------------------

  /// Rolls up the day into a few supportive coaching messages.
  List<String> get dailyFeedback {
    final t = todaysTotals;
    if (t.mealCount == 0) {
      return ['Log your first meal to get personalized coaching today.'];
    }
    final msgs = <String>[];

    final calPct = _goals.calories == 0 ? 0 : t.calories / _goals.calories;
    if (calPct >= 1.0) {
      msgs.add("You've reached your calorie goal for today.");
    } else if (calPct >= 0.75) {
      msgs.add("You're close to your calorie goal — nicely paced.");
    }

    if (t.macros.protein < _goals.protein * 0.6) {
      msgs.add('You are below your protein goal today. '
          'Consider adding eggs, fish, or dhal.');
    } else if (t.macros.protein >= _goals.protein) {
      msgs.add('Great protein intake today.');
    }

    final sugarPct =
        _goals.sugar == 0 ? 0 : t.macros.sugar / _goals.sugar;
    if (sugarPct >= 0.75) {
      msgs.add('You have used ${(sugarPct * 100).round()}% of your daily '
          'sugar allowance.');
    }

    if (t.macros.fiber < 8 && t.mealCount >= 2) {
      msgs.add('Adding fruit or vegetables would boost your fiber and '
          'micronutrients.');
    }

    if (msgs.isEmpty) {
      msgs.add("Today's meals look well balanced. Keep it up!");
    }
    return msgs;
  }
}
