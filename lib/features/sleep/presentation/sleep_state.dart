import 'package:flutter/foundation.dart';
import '../../../services/pro_access.dart';

import '../data/demo_sleep_data_provider.dart';
import '../data/gemini_sleep_ai_service.dart';
import '../data/health_sleep_data_provider.dart';
import '../data/sleep_factors_analyzer.dart';
import '../data/sleep_repository.dart';
import '../data/sleep_score_calculator.dart';
import '../domain/sleep_ai_service.dart';
import '../domain/sleep_data_provider.dart';
import '../domain/sleep_models.dart';

/// The load status of the sleep dashboard.
enum SleepStatus { loading, loaded, empty, error }

/// Presentation-layer state for the AI Sleep Coach.
///
/// Depends only on abstractions ([SleepDataProvider], [SleepAIService]) so the
/// demo source can be swapped for Apple Health / Health Connect later. Factor
/// inputs (hydration/nutrition/exercise) are pushed in via [syncInputs] so this
/// provider stays decoupled from the other tool states.
class SleepState extends ChangeNotifier {
  /// The demo source, always available as a fallback.
  final SleepDataProvider _demoProvider;

  /// The health-backed source (Apple Health / Health Connect). Optional so
  /// tests can omit it and avoid pulling in the native plugin.
  final HealthSleepDataProvider? _healthProvider;

  final SleepAIService _aiService;
  final SleepScoreCalculator _scoreCalc;
  final SleepFactorsAnalyzer _factorsAnalyzer;
  final SleepRepository _repo;

  SleepState({
    SleepDataProvider? provider,
    HealthSleepDataProvider? healthProvider,
    SleepAIService? aiService,
    SleepScoreCalculator? scoreCalculator,
    SleepFactorsAnalyzer? factorsAnalyzer,
    SleepRepository? repository,
  })  : _demoProvider = provider ?? const DemoSleepDataProvider(),
        _healthProvider = healthProvider,
        _aiService = aiService ?? GeminiSleepAIService(),
        _scoreCalc = scoreCalculator ?? const SleepScoreCalculator(),
        _factorsAnalyzer = factorsAnalyzer ?? const SleepFactorsAnalyzer(),
        _repo = repository ?? SleepRepository();

  /// Whether the user has connected a real health source.
  bool _healthConnected = false;
  bool get healthConnected => _healthConnected;

  /// The active data source: health when connected, else demo.
  SleepDataProvider get _provider =>
      (_healthConnected && _healthProvider != null)
          ? _healthProvider
          : _demoProvider;

  /// Lazily creates a health provider (only when needed, so tests stay light).
  HealthSleepDataProvider get _health =>
      _healthProvider ?? HealthSleepDataProvider();

  // --- state ---
  SleepStatus _status = SleepStatus.loading;
  DateTime _selectedDate = _today();
  SleepSession? _session;
  SleepSession? _previousSession;
  SleepScore? _score;
  List<SleepFactor> _factors = [];
  SleepInsight? _insight;
  List<SleepHistoryPoint> _history = [];
  bool _isAnalyzing = false;
  bool _aiFailed = false;
  String? _error;

  // Factor inputs pushed from other tools.
  SleepFactorInputs _factorInputs = const SleepFactorInputs();

  // --- getters ---
  SleepStatus get status => _status;
  DateTime get selectedDate => _selectedDate;
  SleepSession? get session => _session;
  SleepScore? get score => _score;
  List<SleepFactor> get factors => _factors;
  SleepInsight? get insight => _insight;
  List<SleepHistoryPoint> get history => _history;
  bool get isAnalyzing => _isAnalyzing;
  bool get aiFailed => _aiFailed;
  String? get error => _error;

  bool get canGoNext => _dateOnly(_selectedDate).isBefore(_today());

  /// A morning greeting used at the top of the dashboard.
  String get greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning 🌙';
    if (h < 18) return 'Good afternoon 🌙';
    return 'Good evening 🌙';
  }

  // ---------------------------------------------------------------------------
  // Onboarding
  // ---------------------------------------------------------------------------
  Future<bool> isOnboarded() => _repo.isOnboarded();
  Future<void> completeOnboarding() => _repo.setOnboarded();

  // ---------------------------------------------------------------------------
  // Health connection (Apple Health / Android Health Connect)
  // ---------------------------------------------------------------------------

  /// On startup, adopt the health source silently if permission was already
  /// granted in a previous session (no prompt shown).
  Future<void> restoreHealthConnection() async {
    try {
      if (await _health.hasPermission()) {
        _healthConnected = true;
      }
    } catch (_) {
      _healthConnected = false;
    }
  }

  /// Requests health permission and, if granted, switches to real data.
  /// Returns true on success; on denial the demo source stays active.
  Future<bool> connectHealth() async {
    try {
      final available = await _health.isHealthAvailable();
      if (!available) return false;
      final granted = await _health.requestPermission();
      if (granted) {
        _healthConnected = true;
        notifyListeners();
        await load();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('❌ SleepState.connectHealth: $e');
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Factor inputs (from Hydration / Nutrition / Calorie Budget tools)
  // ---------------------------------------------------------------------------
  void setFactorInputs(SleepFactorInputs inputs) {
    _factorInputs = inputs;
  }

  // ---------------------------------------------------------------------------
  // Loading
  // ---------------------------------------------------------------------------
  Future<void> load() async {
    await _loadForDate(_selectedDate);
    // History loads in the background.
    _loadHistory();
  }

  Future<void> selectDate(DateTime date) async {
    _selectedDate = _dateOnly(date);
    await _loadForDate(_selectedDate);
  }

  Future<void> previousDay() =>
      selectDate(_selectedDate.subtract(const Duration(days: 1)));

  Future<void> nextDay() {
    if (!canGoNext) return Future.value();
    return selectDate(_selectedDate.add(const Duration(days: 1)));
  }

  Future<void> _loadForDate(DateTime date) async {
    _status = SleepStatus.loading;
    _aiFailed = false;
    _error = null;
    notifyListeners();
    try {
      if (!await _provider.isAvailable()) {
        _status = SleepStatus.empty;
        notifyListeners();
        return;
      }
      final session = await _provider.getSession(date);
      if (session == null) {
        _session = null;
        _score = null;
        _status = SleepStatus.empty;
        notifyListeners();
        return;
      }
      _previousSession = await _provider
          .getSession(date.subtract(const Duration(days: 1)));
      _session = session;
      _score = _scoreCalc.calculate(session, previous: _previousSession);
      _factors = _factorsAnalyzer.analyze(_factorInputs);
      _status = SleepStatus.loaded;
      notifyListeners();

      // Persist a compact summary + kick AI analysis.
      // ignore: unawaited_futures
      _repo.saveDailySummary(session: session, score: _score!);
      await _runAnalysis();
    } catch (e) {
      debugPrint('❌ SleepState._loadForDate: $e');
      _status = SleepStatus.error;
      _error = "We couldn't load your sleep data.";
      notifyListeners();
    }
  }

  Future<void> _runAnalysis() async {
    final session = _session;
    final score = _score;
    if (session == null || score == null) return;
    // Premium-only. This runs automatically on load rather than from a button,
    // so the gate has to live here — the UI never gets a chance to ask.
    if (!ProAccess.isPro) {
      _insight = null;
      notifyListeners();
      return;
    }
    _isAnalyzing = true;
    _aiFailed = false;
    notifyListeners();
    try {
      final request = SleepAnalysisRequest(
        sleepMinutes: session.totalSleepMinutes,
        score: score.value,
        stageMinutes: {
          for (final s in session.stages) s.type.name: s.minutes,
        },
        previousSleepMinutes: _previousSession?.totalSleepMinutes,
        factors: _factors,
      );
      _insight = await _aiService.analyze(request);
    } catch (e) {
      debugPrint('❌ SleepState._runAnalysis: $e');
      _aiFailed = true;
    } finally {
      _isAnalyzing = false;
      notifyListeners();
    }
  }

  /// Retry AI analysis after a failure.
  Future<void> retryAnalysis() => _runAnalysis();

  Future<void> _loadHistory() async {
    try {
      final sessions = await _provider.getRecentSessions(days: 7);
      _history = sessions.map((s) {
        final sc = _scoreCalc.calculate(s);
        return SleepHistoryPoint(
          date: s.date,
          totalSleepMinutes: s.totalSleepMinutes,
          score: sc.value,
        );
      }).toList();
      notifyListeners();
    } catch (e) {
      debugPrint('❌ SleepState._loadHistory: $e');
    }
  }

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}
