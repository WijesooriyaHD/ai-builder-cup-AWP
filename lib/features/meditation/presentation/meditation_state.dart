import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../services/achievement_service.dart';
import '../../../services/notification_service.dart';
import '../data/gemini_mindfulness_coach.dart';
import '../data/meditation_repository.dart';
import '../data/mindfulness_stats_calculator.dart';
import '../domain/meditation_models.dart';

/// Presentation-layer state for the Meditation & Mindfulness tool.
///
/// Uses provider/ChangeNotifier + SharedPreferences (offline) to match the
/// app's architecture. AI recommendation degrades to a heuristic when offline.
class MeditationState extends ChangeNotifier {
  final MeditationRepository _repo;
  final MindfulnessStatsCalculator _calc;
  final GeminiMindfulnessCoach _coach;
  final NotificationService _notifications;
  final _uuid = const Uuid();

  MeditationState({
    MeditationRepository? repository,
    MindfulnessStatsCalculator? calculator,
    GeminiMindfulnessCoach? coach,
    NotificationService? notifications,
  })  : _repo = repository ?? MeditationRepository(),
        _calc = calculator ?? const MindfulnessStatsCalculator(),
        _coach = coach ?? GeminiMindfulnessCoach(),
        _notifications = notifications ?? NotificationService();

  // --- state ---
  List<MeditationSessionRecord> _history = [];
  MindfulnessStats _stats = const MindfulnessStats();
  Set<String> _unlocked = {};
  List<MindfulnessReminder> _reminders = [];
  String _recommendation = 'Take a moment for yourself today.';
  bool _isLoading = false;
  bool _loadingRecommendation = false;

  // --- getters ---
  List<MeditationSessionRecord> get history => _history;
  MindfulnessStats get stats => _stats;
  Set<String> get unlockedAchievements => _unlocked;
  List<MindfulnessReminder> get reminders => _reminders;
  String get recommendation => _recommendation;
  bool get isLoading => _isLoading;
  bool get loadingRecommendation => _loadingRecommendation;

  int get achievementCount => _unlocked.length;
  bool isUnlocked(String id) => _unlocked.contains(id);

  List<int> get weeklyMinutes => _calc.weeklyMinutes(_history);
  Map<SessionType, int> get minutesByType => _calc.minutesByType(_history);

  String get greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good Morning ☀️';
    if (h < 18) return 'Good Afternoon 🌤️';
    return 'Good Evening 🌙';
  }

  // ---------------------------------------------------------------------------
  // Loading
  // ---------------------------------------------------------------------------
  Future<void> load() async {
    _isLoading = true;
    notifyListeners();
    try {
      final results = await Future.wait([
        _repo.loadHistory(),
        _repo.loadUnlockedAchievements(),
        _repo.loadReminders(),
        _repo.loadLongestStreak(),
      ]);
      _history = results[0] as List<MeditationSessionRecord>;
      _unlocked = results[1] as Set<String>;
      _reminders = results[2] as List<MindfulnessReminder>;
      final longest = results[3] as int;
      _stats = _calc.stats(_history, longestStored: longest);
      // Persist any improved longest streak.
      if (_stats.longestStreak > longest) {
        await _repo.saveLongestStreak(_stats.longestStreak);
      }
    } catch (e) {
      debugPrint('❌ MeditationState.load: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    // Re-sync scheduled notifications so enabled reminders survive reboots and
    // app restarts. Best-effort — never blocks the dashboard.
    unawaited(_syncScheduledReminders());
    // Mirror any previously-earned meditation achievements into the global
    // AchievementService so they show up in the home-page grid immediately.
    unawaited(_syncAchievementsToGlobal());
  }

  /// Mirrors all locally-stored meditation achievement IDs into the global
  /// [AchievementService] so they appear in the home-page achievements grid
  /// and the global Achievements screen. Best-effort — runs after load().
  Future<void> _syncAchievementsToGlobal() async {
    try {
      for (final id in _unlocked) {
        await AchievementService().unlockSpecialAchievement(id);
      }
    } catch (e) {
      debugPrint('❌ MeditationState._syncAchievementsToGlobal: $e');
    }
  }

  /// Reschedules every enabled reminder with the OS. Safe to call repeatedly.
  ///
  /// Does not prompt for permission — that only happens when the user turns a
  /// reminder on. If permission isn't granted yet, enabled reminders simply
  /// stay pending until it is (and get scheduled on the next sync).
  Future<void> _syncScheduledReminders() async {
    final anyEnabled = _reminders.any((r) => r.enabled);
    if (!anyEnabled) return;

    bool authorized;
    try {
      authorized = await _notifications.hasNotificationPermission();
      notificationsAuthorized = authorized;
    } catch (_) {
      authorized = false;
    }
    if (!authorized) return; // nothing to schedule until the user grants it

    for (final r in _reminders) {
      try {
        await _notifications.scheduleMeditationReminder(
          reminderId: r.id,
          label: r.label,
          hour: r.hour,
          minute: r.minute,
          weekdays: r.days,
          enabled: r.enabled,
          assumeAuthorized: true,
        );
      } catch (e) {
        debugPrint('❌ MeditationState._syncScheduledReminders(${r.id}): $e');
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Completing a session
  // ---------------------------------------------------------------------------

  /// Records a completed session, updates stats/streak, and unlocks any new
  /// achievements. Returns the list of newly-unlocked achievements (for UI).
  Future<List<MindfulnessAchievement>> completeSession({
    required SessionType type,
    required String title,
    required int minutes,
  }) async {
    final record = MeditationSessionRecord(
      id: _uuid.v4(),
      type: type,
      title: title,
      minutes: minutes,
      completedAt: DateTime.now(),
    );
    _history = [record, ..._history];
    await _repo.addSession(record);

    final longest = await _repo.loadLongestStreak();
    _stats = _calc.stats(_history, longestStored: longest);
    if (_stats.longestStreak > longest) {
      await _repo.saveLongestStreak(_stats.longestStreak);
    }

    // Achievements.
    final candidate = _calc.evaluateAchievements(_history, _stats);
    final newly = _calc.newlyUnlocked(candidate, _unlocked);
    if (newly.isNotEmpty) {
      _unlocked = {..._unlocked, ...candidate};
      await _repo.saveUnlockedAchievements(_unlocked);
      // Mirror into the global AchievementService so meditation badges appear
      // in the home-page achievements grid and global Achievements screen.
      for (final a in newly) {
        await AchievementService().unlockSpecialAchievement(a.id);
      }
    }

    notifyListeners();
    onSessionCompleted?.call();
    return newly;
  }

  /// Fires when a meditation session is completed.
  ///
  /// Wired in `main.dart` to the engagement system. A plain callback so this
  /// feature keeps no dependency on notifications.
  void Function()? onSessionCompleted;

  // ---------------------------------------------------------------------------
  // AI recommendation
  // ---------------------------------------------------------------------------
  Future<void> refreshRecommendation({
    int? lastSleepMinutes,
    int? hydrationPercent,
    int? exerciseMinutesToday,
  }) async {
    _loadingRecommendation = true;
    notifyListeners();
    try {
      final ctx = MindfulnessContext(
        currentStreak: _stats.currentStreak,
        minutesThisWeek: _stats.minutesThisWeek,
        lastSleepMinutes: lastSleepMinutes,
        hydrationPercent: hydrationPercent,
        exerciseMinutesToday: exerciseMinutesToday,
        hourOfDay: DateTime.now().hour,
      );
      _recommendation = await _coach.recommend(ctx);
    } catch (e) {
      debugPrint('❌ MeditationState.refreshRecommendation: $e');
    } finally {
      _loadingRecommendation = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Reminders
  // ---------------------------------------------------------------------------
  /// Whether the OS granted notification permission (for UI hints).
  bool notificationsAuthorized = false;

  /// Requests permission (if needed) and fires a test notification a few
  /// seconds out. Returns true if it was scheduled, false if permission was
  /// denied. Used to verify the reminder pipeline end to end.
  Future<bool> sendTestNotification() async {
    try {
      notificationsAuthorized = await _notifications.requestPermission();
      notifyListeners();
      if (!notificationsAuthorized) return false;
      return await _notifications.sendTestMeditationNotification();
    } catch (e) {
      debugPrint('❌ MeditationState.sendTestNotification: $e');
      return false;
    }
  }

  Future<void> updateReminder(MindfulnessReminder reminder) async {
    _reminders =
        _reminders.map((r) => r.id == reminder.id ? reminder : r).toList();
    notifyListeners();
    await _repo.saveReminders(_reminders);

    try {
      // If turning a reminder on, make sure we actually have permission first,
      // otherwise the scheduled notification would silently never fire.
      if (reminder.enabled) {
        notificationsAuthorized = await _notifications.requestPermission();
        notifyListeners();
      }
      await _notifications.scheduleMeditationReminder(
        reminderId: reminder.id,
        label: reminder.label,
        hour: reminder.hour,
        minute: reminder.minute,
        weekdays: reminder.days,
        enabled: reminder.enabled,
        // When enabling, use the fresh grant result so we don't re-query a
        // possibly-stale permission status right after the prompt.
        assumeAuthorized: reminder.enabled ? notificationsAuthorized : null,
      );
      if (reminder.enabled && !notificationsAuthorized) {
        debugPrint('⚠️ Meditation reminder enabled but permission denied — '
            'it will not fire until notifications are allowed in Settings.');
      }
    } catch (e) {
      debugPrint('❌ MeditationState.updateReminder(${reminder.id}): $e');
    }
  }
}
