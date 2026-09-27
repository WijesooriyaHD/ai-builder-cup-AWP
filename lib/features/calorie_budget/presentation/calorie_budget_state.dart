import 'package:flutter/foundation.dart';
import '../../../services/pro_access.dart';
import 'package:home_widget/home_widget.dart';
import 'package:uuid/uuid.dart';

import '../../meal_planner/domain/meal_planner_models.dart';
import '../../nutrition/domain/nutrition_models.dart';
import '../data/calorie_budget_repository.dart';
import '../data/gemini_calorie_budget_service.dart';
import '../domain/calorie_budget_models.dart';
import '../domain/calorie_budget_service.dart';

/// Presentation-layer state for the AI Calorie Budget tool.
///
/// Consumed calories are supplied by the Nutrition Coach (today's meals) and
/// the daily budget is derived from the Meal Planner profile (or a user
/// override). Burned calories come from local exercise entries.
class CalorieBudgetState extends ChangeNotifier {
  final CalorieBudgetService _service;
  final CalorieBudgetRepository _repo;
  final _uuid = const Uuid();

  CalorieBudgetState({
    CalorieBudgetService? service,
    CalorieBudgetRepository? repository,
  })  : _service = service ?? GeminiCalorieBudgetService(),
        _repo = repository ?? CalorieBudgetRepository();

  // --- inputs from other tools ---
  int _consumed = 0; // from Nutrition Coach today's meals
  List<CalorieEvent> _foodEvents = const []; // today's meals as timeline events
  /// Safe floor/ceiling for any daily budget we show or plan against
  /// (App Store Review Guideline 1.4.1: no unsafe calorie targets).
  static const int minDailyBudget = 1200;
  static const int maxDailyBudget = 5000;

  /// Clamps [kcal] into the safe daily-budget range.
  static int clampBudget(int kcal) =>
      kcal.clamp(minDailyBudget, maxDailyBudget).toInt();

  int _budgetOverride = 0; // 0 = derive from profile
  int _profileBudget = 2000; // from Meal Planner UserProfile

  // --- own state ---
  GoalMode _goalMode = GoalMode.maintenance;
  List<ExerciseEntry> _exercises = [];
  CaloriePrediction? _prediction;
  List<String> _insights = [];
  List<DailyCalorieBudget> _recent = [];
  int _currentStreak = 0;
  int _bestStreak = 0;
  bool _isLoading = false;
  bool _isAnalyzing = false;

  // --- getters ---
  GoalMode get goalMode => _goalMode;
  List<ExerciseEntry> get exercises => _exercises;
  CaloriePrediction? get prediction => _prediction;
  List<String> get insights => _insights;
  List<DailyCalorieBudget> get recent => _recent;
  int get currentStreak => _currentStreak;
  int get bestStreak => _bestStreak;
  bool get isLoading => _isLoading;
  bool get isAnalyzing => _isAnalyzing;

  int get consumed => _consumed;
  int get burned => _exercises.fold(0, (s, e) => s + e.calories);

  int get dailyBudget =>
      clampBudget(_budgetOverride > 0 ? _budgetOverride : _profileBudget);

  CalorieSummary get summary => CalorieSummary(
        dailyBudget: dailyBudget,
        consumed: _consumed,
        burned: burned,
        goalMode: _goalMode,
      );

  int get remaining => summary.remaining;

  /// The last up-to-7 days as trend points (oldest → newest), ensuring today
  /// is represented from the live totals. Shared by the tool screen's weekly
  /// progress card and the Home embedding of it.
  List<CalorieTrendPoint> get trendPoints {
    final recentDays = _recent.reversed.take(7).toList();
    final points = recentDays
        .map((d) => CalorieTrendPoint(
              date: DateTime.tryParse(d.date) ?? DateTime.now(),
              consumed: d.consumed,
              burned: d.burned,
              budget: d.dailyBudget,
            ))
        .toList();
    final todayKey = CalorieBudgetRepository.dateKey(DateTime.now());
    if (!recentDays.any((d) => d.date == todayKey)) {
      points.add(CalorieTrendPoint(
        date: DateTime.now(),
        consumed: consumed,
        burned: burned,
        budget: dailyBudget,
      ));
    }
    if (points.length > 7) return points.sublist(points.length - 7);
    return points;
  }

  /// Mirrors the calorie budget into the shared app group so the home-screen
  /// "Calorie Budget" widget can show a kcal-remaining ring on its data face.
  Future<void> syncCalorieWidget() async {
    try {
      await HomeWidget.setAppGroupId('group.com.aiwellnesspal.app');
      final s = summary;
      await HomeWidget.saveWidgetData<int>('calorie_budget', s.dailyBudget);
      await HomeWidget.saveWidgetData<int>('calorie_consumed', s.consumed);
      await HomeWidget.saveWidgetData<int>('calorie_burned', s.burned);
      await HomeWidget.saveWidgetData<int>('calorie_remaining', s.remaining);
      await HomeWidget.saveWidgetData<int>(
          'calorie_pct', (s.consumedFraction * 100).round().clamp(0, 100));
      await HomeWidget.updateWidget(
          name: 'CalorieBudgetToolWidget',
          androidName: 'CalorieBudgetToolWidget');
    } catch (e) {
      debugPrint('ℹ️ CalorieBudgetState.syncCalorieWidget: $e');
    }
  }

  /// Combined timeline (meals + exercises), newest first.
  List<CalorieEvent> get timeline {
    final ex = _exercises.map((e) => CalorieEvent(
          id: e.id,
          kind: CalorieEventKind.exercise,
          label: e.type.label,
          calories: -e.calories,
          time: e.time,
        ));
    final all = [..._foodEvents, ...ex]..sort((a, b) => b.time.compareTo(a.time));
    return all;
  }

  // ---------------------------------------------------------------------------
  // Loading
  // ---------------------------------------------------------------------------
  Future<void> load() async {
    _isLoading = true;
    notifyListeners();
    try {
      final today = DateTime.now();
      final results = await Future.wait([
        _repo.loadGoalMode(),
        _repo.loadBudgetOverride(),
        _repo.loadExercises(today),
        _repo.loadStreak(),
        _repo.loadRecent(),
      ]);
      _goalMode = results[0] as GoalMode;
      _budgetOverride = results[1] as int;
      _exercises = results[2] as List<ExerciseEntry>;
      final streak = results[3] as Map<String, dynamic>;
      _currentStreak = streak['current'] as int? ?? 0;
      _bestStreak = streak['best'] as int? ?? 0;
      _recent = results[4] as List<DailyCalorieBudget>;
    } catch (e) {
      debugPrint('❌ CalorieBudgetState.load: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Feeds today's consumed calories + meal timeline from the Nutrition Coach,
  /// and the profile budget/goal from the Meal Planner. Called by the screen so
  /// this provider stays decoupled from the others.
  void syncInputs({
    required int consumed,
    required List<Meal> todaysMeals,
    UserProfile? profile,
  }) {
    _consumed = consumed;
    _foodEvents = todaysMeals
        .map((m) => CalorieEvent(
              id: m.id,
              kind: CalorieEventKind.food,
              label: '${m.mealType.label}: ${m.mealName}',
              calories: m.calories,
              time: m.createdAt,
            ))
        .toList();
    if (profile != null) {
      _profileBudget = _budgetForProfile(profile);
    }
    notifyListeners();
    // ignore: unawaited_futures
    syncCalorieWidget();
  }

  int _budgetForProfile(UserProfile p) {
    // The Meal Planner already stores a daily calorie target; use it as the
    // maintenance baseline and apply the goal-mode adjustment.
    final baseline = p.dailyCalories;
    if (_goalMode == GoalMode.custom) return clampBudget(baseline);
    return clampBudget(baseline + _goalMode.calorieAdjustment);
  }

  // ---------------------------------------------------------------------------
  // Exercise
  // ---------------------------------------------------------------------------
  Future<void> addExercise(ExerciseType type, int minutes, {int? calories}) async {
    final kcal = calories ?? (type.kcalPerMinute * minutes).round();
    final entry = ExerciseEntry(
      id: _uuid.v4(),
      type: type,
      minutes: minutes,
      calories: kcal,
      time: DateTime.now(),
    );
    _exercises = [..._exercises, entry];
    notifyListeners();
    await _repo.saveExercises(DateTime.now(), _exercises);
    await refreshAnalysis();
    await _persistToday();
  }

  Future<void> removeExercise(String id) async {
    _exercises = _exercises.where((e) => e.id != id).toList();
    notifyListeners();
    await _repo.saveExercises(DateTime.now(), _exercises);
    await refreshAnalysis();
    await _persistToday();
  }

  /// Edits an existing exercise entry's type/minutes/calories.
  Future<void> updateExercise(
    String id, {
    ExerciseType? type,
    int? minutes,
    int? calories,
  }) async {
    _exercises = _exercises.map((e) {
      if (e.id != id) return e;
      final newType = type ?? e.type;
      final newMinutes = minutes ?? e.minutes;
      final newCalories = calories ??
          (minutes != null || type != null
              ? (newType.kcalPerMinute * newMinutes).round()
              : e.calories);
      return ExerciseEntry(
        id: e.id,
        type: newType,
        minutes: newMinutes,
        calories: newCalories,
        time: e.time,
      );
    }).toList();
    notifyListeners();
    await _repo.saveExercises(DateTime.now(), _exercises);
    await refreshAnalysis();
    await _persistToday();
  }

  ExerciseEntry? exerciseById(String id) {
    for (final e in _exercises) {
      if (e.id == id) return e;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Goal mode / budget override
  // ---------------------------------------------------------------------------
  Future<void> setGoalMode(GoalMode mode) async {
    _goalMode = mode;
    notifyListeners();
    await _repo.saveGoalMode(mode);
    await refreshAnalysis();
  }

  Future<void> setBudgetOverride(int budget) async {
    // 0 (or less) clears the override; anything else is kept within the safe
    // range so a typed value can never set an unsafe target.
    budget = budget > 0 ? clampBudget(budget) : 0;
    _budgetOverride = budget;
    notifyListeners();
    await _repo.saveBudgetOverride(budget);
    await refreshAnalysis();
  }

  // ---------------------------------------------------------------------------
  // AI analysis (prediction + insights)
  // ---------------------------------------------------------------------------
  Future<void> refreshAnalysis() async {
    // Premium-only AI coaching. Called on screen load as well as from the
    // refresh control, so the gate belongs here rather than on the button.
    if (!ProAccess.isPro) return;
    _isAnalyzing = true;
    notifyListeners();
    try {
      final hour = DateTime.now().hour;
      final recentIntakes = _recent
          .where((d) => d.consumed > 0)
          .take(7)
          .map((d) => d.consumed)
          .toList();
      final prediction = await _service.predictEndOfDay(
        summary,
        hourOfDay: hour,
        recentIntakes: recentIntakes,
      );
      final insights = await _service.generateInsights(
        summary,
        prediction,
        hourOfDay: hour,
      );
      _prediction = prediction;
      _insights = insights;
    } catch (e) {
      debugPrint('❌ CalorieBudgetState.refreshAnalysis: $e');
    } finally {
      _isAnalyzing = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Persistence + streak
  // ---------------------------------------------------------------------------
  Future<void> _persistToday() async {
    final today = DateTime.now();
    final day = DailyCalorieBudget(
      date: CalorieBudgetRepository.dateKey(today),
      dailyBudget: dailyBudget,
      consumed: _consumed,
      burned: burned,
      predictedEndOfDay: _prediction?.predictedIntake ?? 0,
      goalMode: _goalMode,
      aiInsights: _insights,
      timeline: timeline,
      createdAt: today,
    );
    await _repo.saveDaily(day);
    await syncCalorieWidget();
  }

  /// Evaluates today's goal achievement and updates the streak. Call at day
  /// end or when consumed changes meaningfully.
  Future<void> evaluateStreak() async {
    final metGoal = _consumed > 0 && _consumed <= dailyBudget + burned;
    final todayKey = CalorieBudgetRepository.dateKey(DateTime.now());
    final streak = await _repo.loadStreak();
    final lastDate = streak['lastDate'] as String?;
    if (lastDate == todayKey) return; // already counted today

    var current = streak['current'] as int? ?? 0;
    var best = streak['best'] as int? ?? 0;
    if (metGoal) {
      current += 1;
      if (current > best) best = current;
    } else {
      current = 0;
    }
    _currentStreak = current;
    _bestStreak = best;
    await _repo.saveStreak(current, best, todayKey);
    notifyListeners();
  }
}
