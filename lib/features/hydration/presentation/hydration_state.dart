import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:uuid/uuid.dart';

import '../../meal_planner/domain/meal_planner_models.dart';
import '../../weather/data/open_meteo_weather_service.dart';
import '../../weather/data/weather_hydration_adjustment_service.dart';
import '../../weather/data/weather_repository.dart';
import '../../weather/domain/weather_models.dart';
import '../../weather/domain/weather_service.dart';
import '../data/gemini_hydration_coach_service.dart';
import '../data/hydration_repository.dart';
import '../domain/hydration_coach_service.dart';
import '../domain/hydration_models.dart';

/// Presentation-layer state for the AI Hydration Coach.
///
/// The goal is derived from the Meal Planner [UserProfile] (weight/gender/
/// activity) plus optional weather + exercise adjustments. All AI is optional;
/// heuristics keep the tool fully functional offline.
class HydrationState extends ChangeNotifier {
  final HydrationCoachService _service;
  final HydrationRepository _repo;
  final WeatherService _weatherService;
  final WeatherRepository _weatherRepo;
  final WeatherHydrationAdjustmentService _weatherAdjust;
  final _uuid = const Uuid();

  HydrationState({
    HydrationCoachService? service,
    HydrationRepository? repository,
    WeatherService? weatherService,
    WeatherRepository? weatherRepository,
    WeatherHydrationAdjustmentService? weatherAdjustment,
  })  : _service = service ?? GeminiHydrationCoachService(),
        _repo = repository ?? HydrationRepository(),
        _weatherService = weatherService ?? OpenMeteoWeatherService(),
        _weatherRepo = weatherRepository ?? WeatherRepository(),
        _weatherAdjust =
            weatherAdjustment ?? const WeatherHydrationAdjustmentService();

  // Quick-add presets (ml).
  static const List<int> quickAddOptions = [100, 200, 250, 500, 750, 1000];

  // --- state ---
  HydrationGoal _goal = const HydrationGoal(baseMl: 2500);
  List<HydrationEntry> _entries = [];
  WeatherAdjustment _weather = const WeatherAdjustment();
  List<String> _insights = [];
  HydrationPrediction? _prediction;
  List<Reminder> _reminders = [];
  List<DailyHydration> _recent = [];
  int _currentStreak = 0;
  int _bestStreak = 0;
  bool _isLoading = false;
  bool _isAnalyzing = false;

  // inputs from other tools
  HydrationProfile _profile = const HydrationProfile();

  // User-set base target override (null = auto from profile/weight/activity).
  int? _manualBaseMl;

  /// Allowed range for a manually set daily base target (ml).
  static const int minTargetMl = 500;
  static const int maxTargetMl = 6000;

  // --- Open-Meteo weather state ---
  WeatherLocation? _weatherLocation;
  WeatherData? _weatherData;
  WeatherHydrationAdjustment _weatherAdjustment =
      const WeatherHydrationAdjustment();
  bool _isWeatherLoading = false;
  String? _weatherError;
  bool _weatherStale = false; // cached-but-expired shown as fallback

  // --- getters ---
  HydrationGoal get goal => _goal;
  int get goalMl => _goal.totalMl;

  /// The base daily target (before exercise/weather adjustments).
  int get baseTargetMl => _goal.baseMl;

  /// Whether the base target is a user-set value (vs. auto-calculated).
  bool get isManualTarget => _manualBaseMl != null;
  List<HydrationEntry> get entries => _entries;
  WeatherAdjustment get weather => _weather;

  // Open-Meteo weather getters (for the UI + AI context).
  WeatherLocation? get weatherLocation => _weatherLocation;
  bool get hasWeatherLocation => _weatherLocation != null;
  WeatherData? get weatherData => _weatherData;
  WeatherHydrationAdjustment get weatherAdjustment => _weatherAdjustment;
  bool get isWeatherLoading => _isWeatherLoading;
  String? get weatherError => _weatherError;
  bool get weatherStale => _weatherStale;
  List<String> get insights => _insights;
  HydrationPrediction? get prediction => _prediction;
  List<Reminder> get reminders => _reminders;
  List<DailyHydration> get recent => _recent;
  int get currentStreak => _currentStreak;
  int get bestStreak => _bestStreak;
  bool get isLoading => _isLoading;
  bool get isAnalyzing => _isAnalyzing;

  int get consumedMl => _entries.fold(0, (s, e) => s + e.amountMl);
  int get remainingMl => (goalMl - consumedMl).clamp(0, 999999);
  double get progress => goalMl <= 0 ? 0 : (consumedMl / goalMl).clamp(0.0, 1.0);
  int get completionPercentage =>
      goalMl <= 0 ? 0 : ((consumedMl / goalMl) * 100).round();

  /// Timeline entries, newest first.
  List<HydrationEntry> get timeline {
    final list = [..._entries]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list;
  }

  /// 0–100 hydration score derived from completion + consistency + timing.
  HydrationScore get score {
    // Completion (today) — up to 55 pts.
    final completion = (progress * 55).round();

    // Consistency (recent days meeting goal) — up to 30 pts.
    int consistency = 0;
    if (_recent.isNotEmpty) {
      final met = _recent.take(7).where((d) => d.metGoal).length;
      final total = _recent.take(7).length;
      consistency = ((met / total) * 30).round();
    } else if (progress >= 0.5) {
      consistency = 15;
    }

    // Timing (spread across the day) — up to 15 pts.
    final hoursWithWater =
        _entries.map((e) => e.timestamp.hour).toSet().length;
    final timing = (hoursWithWater.clamp(0, 5) / 5 * 15).round();

    final total = (completion + consistency + timing).clamp(0, 100);
    final String explanation;
    if (total >= 85) {
      explanation = 'Excellent hydration consistency.';
    } else if (total >= 60) {
      explanation = 'Good hydration — spread your intake for an even higher score.';
    } else if (total >= 35) {
      explanation = 'You\'re building the habit. Aim for steady sips today.';
    } else {
      explanation = 'Let\'s get hydrated — start with a glass now.';
    }
    return HydrationScore(score: total, explanation: explanation);
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
        _repo.loadEntries(today),
        _repo.loadWeather(),
        _repo.loadStreak(),
        _repo.loadRecent(),
        _weatherRepo.loadLocation(),
        _weatherRepo.loadCachedWeather(),
        _repo.loadManualBaseMl(),
      ]);
      _entries = results[0] as List<HydrationEntry>;
      _weather = results[1] as WeatherAdjustment;
      final streak = results[2] as Map<String, dynamic>;
      _currentStreak = streak['current'] as int? ?? 0;
      _bestStreak = streak['best'] as int? ?? 0;
      _recent = results[3] as List<DailyHydration>;
      _weatherLocation = results[4] as WeatherLocation?;
      _weatherData = results[5] as WeatherData?;
      _manualBaseMl = results[6] as int?;
      if (_weatherData != null) {
        _weatherAdjustment = _weatherAdjust.compute(_weatherData);
      }
      await _recomputeGoal();
      // Kick a fresh weather fetch in the background if we have a location.
      if (_weatherLocation != null) {
        // ignore: unawaited_futures
        refreshWeather();
      }
    } catch (e) {
      debugPrint('❌ HydrationState.load: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
      // Push a fresh snapshot to the home-screen widget after loading.
      // ignore: unawaited_futures
      syncHydrationWidget();
    }
  }

  /// Feeds profile inputs from the Meal Planner + activity (exercise minutes).
  Future<void> syncProfile(UserProfile? profile,
      {int exerciseMinutesToday = 0}) async {
    _profile = HydrationProfile(
      age: profile?.age,
      gender: profile?.gender,
      weightKg: profile?.weightKg,
      activityLevel: profile?.activityLevel ?? 'moderate',
      exerciseMinutesToday: exerciseMinutesToday,
    );
    await _recomputeGoal();
    notifyListeners();
  }

  Future<void> _recomputeGoal() async {
    // Prefer the Open-Meteo-driven weather adjustment; fall back to any legacy
    // manual adjustment (or none) when no live/cached weather exists.
    final weatherMl = _weatherAdjustment.isActive
        ? _weatherAdjustment.adjustmentMl
        : _weather.extraMl;
    final weatherDesc =
        _weatherAdjustment.isActive ? _weatherAdjustment.reason : _weather.description;
    final computed = await _service.calculateGoal(
      _profile,
      weather: WeatherAdjustment(extraMl: weatherMl, description: weatherDesc),
    );
    // A user-set base target replaces the auto-calculated base, while exercise
    // and weather adjustments still layer on top.
    _goal = _manualBaseMl == null
        ? computed
        : HydrationGoal(
            baseMl: _manualBaseMl!,
            exerciseAdjustmentMl: computed.exerciseAdjustmentMl,
            weatherAdjustmentMl: computed.weatherAdjustmentMl,
          );
  }

  /// Sets a manual daily base target (ml), or pass `null` to revert to the
  /// auto-calculated target. The value is clamped to a safe range and persisted.
  Future<void> setManualTarget(int? ml) async {
    final clamped = ml?.clamp(minTargetMl, maxTargetMl).toInt();
    _manualBaseMl = clamped;
    await _repo.saveManualBaseMl(clamped);
    await _recomputeGoal();
    notifyListeners();
    await refreshAnalysis();
    await _persistToday();
  }

  // ---------------------------------------------------------------------------
  // Open-Meteo weather
  // ---------------------------------------------------------------------------

  /// Saves a confirmed [location], refreshes weather, and recalculates the goal.
  Future<void> setWeatherLocation(WeatherLocation location) async {
    _weatherLocation = location;
    _weatherError = null;
    notifyListeners();
    await _weatherRepo.saveLocation(location); // also clears weather cache
    _weatherData = null;
    await refreshWeather(force: true);
  }

  /// Clears the saved weather location (reverts to standard, weather-free goal).
  Future<void> clearWeatherLocation() async {
    _weatherLocation = null;
    _weatherData = null;
    _weatherAdjustment = const WeatherHydrationAdjustment();
    await _weatherRepo.clearWeatherCache();
    await _recomputeGoal();
    notifyListeners();
  }

  /// Fetches current weather (cache-aware, offline-tolerant). Never throws.
  Future<void> refreshWeather({bool force = false}) async {
    final loc = _weatherLocation;
    if (loc == null) return;

    // Use fresh cache unless forced.
    if (!force && await _weatherRepo.isCacheFresh()) {
      _weatherData ??= await _weatherRepo.loadCachedWeather();
      _weatherStale = false;
      if (_weatherData != null) {
        _weatherAdjustment = _weatherAdjust.compute(_weatherData);
        await _recomputeGoal();
        notifyListeners();
      }
      return;
    }

    _isWeatherLoading = true;
    _weatherError = null;
    notifyListeners();
    try {
      final data = await _weatherService.getCurrentWeather(
        latitude: loc.latitude,
        longitude: loc.longitude,
      );
      _weatherData = data;
      _weatherStale = false;
      _weatherAdjustment = _weatherAdjust.compute(data);
      await _weatherRepo.saveWeatherCache(data);
      await _recomputeGoal();
      await refreshAnalysis();
    } catch (e) {
      debugPrint('ℹ️ HydrationState.refreshWeather: $e');
      // Offline-tolerant: keep any cached weather, mark it stale for the UI.
      final cached = await _weatherRepo.loadCachedWeather();
      if (cached != null) {
        _weatherData = cached;
        _weatherStale = true;
        _weatherAdjustment = _weatherAdjust.compute(cached);
      } else {
        // No weather at all → standard goal, no weather adjustment.
        _weatherData = null;
        _weatherAdjustment = const WeatherHydrationAdjustment();
        _weatherError =
            "Weather data isn't available right now. Your standard hydration "
            "target is being used.";
      }
      await _recomputeGoal();
    } finally {
      _isWeatherLoading = false;
      notifyListeners();
    }
  }

  /// Structured, privacy-safe weather context for the AI insight prompt.
  Map<String, dynamic>? get aiWeatherContext {
    final w = _weatherData;
    if (w == null) return null;
    return {
      'temperatureCelsius': w.temperatureCelsius,
      'apparentTemperatureCelsius': w.apparentTemperatureCelsius,
      'relativeHumidity': w.relativeHumidity,
      'weatherAdjustmentMl': _weatherAdjustment.adjustmentMl,
      'currentConsumedMl': consumedMl,
      'dailyGoalMl': goalMl,
    };
  }

  // ---------------------------------------------------------------------------
  // Logging
  // ---------------------------------------------------------------------------
  Future<void> logWater(int amountMl, {String source = 'quick_add'}) async {
    if (amountMl <= 0) return;
    final entry = HydrationEntry(
      id: _uuid.v4(),
      amountMl: amountMl,
      timestamp: DateTime.now(),
      source: source,
    );
    _entries = [..._entries, entry];
    notifyListeners();
    await _repo.saveEntries(DateTime.now(), _entries);
    await refreshAnalysis();
    await _persistToday();
    await evaluateStreak();
  }

  Future<void> removeEntry(String id) async {
    _entries = _entries.where((e) => e.id != id).toList();
    notifyListeners();
    await _repo.saveEntries(DateTime.now(), _entries);
    await refreshAnalysis();
    await _persistToday();
  }

  // ---------------------------------------------------------------------------
  // AI analysis
  // ---------------------------------------------------------------------------
  Future<void> refreshAnalysis() async {
    _isAnalyzing = true;
    notifyListeners();
    try {
      final hour = DateTime.now().hour;
      final recentPoints = _recent
          .map((d) => HydrationTrendPoint(
                date: DateTime.tryParse(d.date) ?? DateTime.now(),
                consumedMl: d.consumedMl,
                goalMl: d.goalMl,
              ))
          .toList();
      final prediction = await _service.predictCompletion(
        goalMl: goalMl,
        consumedMl: consumedMl,
        hourOfDay: hour,
      );
      final insights = await _service.generateInsights(
        goalMl: goalMl,
        consumedMl: consumedMl,
        hourOfDay: hour,
        entries: _entries,
        recent: recentPoints,
        weatherContext: aiWeatherContext,
      );
      final reminders = await _service.generateReminders(
        goalMl: goalMl,
        consumedMl: consumedMl,
        hourOfDay: hour,
        entries: _entries,
      );
      _prediction = prediction;
      _insights = insights;
      _reminders = reminders;
    } catch (e) {
      debugPrint('❌ HydrationState.refreshAnalysis: $e');
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
    final day = DailyHydration(
      date: HydrationRepository.dateKey(today),
      goalMl: goalMl,
      consumedMl: consumedMl,
      weatherAdjustmentMl: _weather.extraMl,
      hydrationScore: score.score,
      aiInsights: _insights,
      entries: _entries,
      createdAt: today,
    );
    await _repo.saveDaily(day);
    await syncHydrationWidget();
  }

  // ---------------------------------------------------------------------------
  // Home-screen widget sync
  // ---------------------------------------------------------------------------

  /// Widget kind understood by `HomeWidget.updateWidget` (matches the iOS
  /// widget `kind` and the Android receiver class name).
  static const String _widgetKind = 'HydrationToolWidget';

  /// Mirrors today's hydration snapshot + a 7-day completion trend into the
  /// shared app group so the home-screen widget can render live data (progress
  /// ring on the front, mini bar graph on the back) without opening the app.
  Future<void> syncHydrationWidget() async {
    try {
      // Ensure the shared app group is set (safe/idempotent, and needed when
      // this runs before AppState's constructor on some cold starts).
      await HomeWidget.setAppGroupId('group.com.aiwellnesspal.app');

      await HomeWidget.saveWidgetData<bool>('hydration_has_data', true);
      await HomeWidget.saveWidgetData<int>('hydration_consumed_ml', consumedMl);
      await HomeWidget.saveWidgetData<int>('hydration_goal_ml', goalMl);
      await HomeWidget.saveWidgetData<int>(
          'hydration_pct', completionPercentage.clamp(0, 100));      await HomeWidget.updateWidget(
          name: _widgetKind, androidName: _widgetKind);
    } catch (e) {
      debugPrint('ℹ️ HydrationState.syncHydrationWidget: $e');
    }
  }

  Future<void> evaluateStreak() async {
    final metGoal = consumedMl >= goalMl && goalMl > 0;
    if (!metGoal) return; // only advance streak on goal completion
    final todayKey = HydrationRepository.dateKey(DateTime.now());
    final streak = await _repo.loadStreak();
    if (streak['lastDate'] == todayKey) return;

    var current = (streak['current'] as int? ?? 0) + 1;
    var best = streak['best'] as int? ?? 0;
    if (current > best) best = current;
    _currentStreak = current;
    _bestStreak = best;
    await _repo.saveStreak(current, best, todayKey);
    notifyListeners();
  }
}
