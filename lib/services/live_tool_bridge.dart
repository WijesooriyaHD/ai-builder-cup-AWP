import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../features/habit_builder/domain/habit_models.dart';
import '../features/habit_builder/presentation/habit_builder_state.dart';
import '../features/hydration/presentation/hydration_state.dart';
import '../models/check_in.dart';
import '../models/wellness_enums.dart';
import '../providers/app_state.dart';
import '../providers/check_in_state.dart';
import '../providers/wellness_plan_state.dart';
import 'accent_colors.dart';
import 'app_navigation_service.dart';
import 'notification_service.dart';

/// A navigation destination the Live pal can request. Mirrors the tap-to-speak
/// Assistant's navigation targets: some are bottom tabs, some are pushed
/// full-screen routes (resolved by the UI layer).
enum LiveNavDestination {
  home,
  intentions,
  habitBuilder,
  reflection,
  settings,
  nutrition,
  mealPlanner,
  calorieBudget,
  hydration,
  sleep,
  meditation,
  periodTracker,
  weightTracker,
  mindfulTravel,
  breathing,
  meditationSession,
  checkIn,
}

/// A request from the Live pal to navigate somewhere. Carries whether the
/// conversation so far had meaningful wellness content, so the UI can decide
/// whether to offer saving a reflection before leaving.
class LiveNavRequest {
  const LiveNavRequest({
    required this.destination,
    required this.hasWellnessContext,
  });

  final LiveNavDestination destination;
  final bool hasWellnessContext;
}

/// A request from the Live pal to END the conversation. The pal decides — in
/// its OWN voice, having already asked the user and heard their answer —
/// whether to [save] the conversation as a reflection.
class LiveEndRequest {
  const LiveEndRequest({required this.save});

  /// True if the user agreed to save this conversation as a reflection.
  final bool save;
}

/// Bridges Gemini Live tool/function calls to the app's real actions so the
/// wellness pal can *do* everything the tap-to-speak Assistant can — change
/// the theme, adjust text size, log water, create habits/intentions, refresh
/// the plan, run a check-in, and navigate — not just talk.
///
/// It reuses the SAME providers the Assistant's sheet mutates (no duplicated
/// logic beyond the shared [AccentColors] map). Navigation is special: because
/// Live holds the mic inside a modal sheet, the bridge does not navigate
/// itself — it hands a [LiveNavRequest] to [onNavigate] so the UI can end the
/// session, optionally offer a reflection, then navigate.
class LiveToolBridge {
  LiveToolBridge({
    required HabitBuilderState habits,
    required AppState appState,
    required AppNavigationService navService,
    required HydrationState hydration,
    required CheckInState checkIn,
    required WellnessPlanState plan,
    this.onNavigate,
    this.onEndConversation,
  })  : _habits = habits,
        _appState = appState,
        _navService = navService,
        _hydration = hydration,
        _checkIn = checkIn,
        _plan = plan;

  final HabitBuilderState _habits;
  final AppState _appState;
  final AppNavigationService _navService;
  final HydrationState _hydration;
  final CheckInState _checkIn;
  final WellnessPlanState _plan;

  /// Called when the pal requests navigation. The UI orchestrates the
  /// end-session / reflection-gate / navigate flow (see ConversationModeSheet).
  final void Function(LiveNavRequest request)? onNavigate;

  /// Called when the pal ends the conversation (user said "let's end" etc.).
  /// The pal has already asked, in its own voice, whether to save a reflection
  /// and passes the user's decision as [LiveEndRequest.save]; the UI tears down
  /// the session and saves (or not) accordingly.
  final void Function(LiveEndRequest request)? onEndConversation;

  String? _lastHabitId;
  String? _lastHabitTitle;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  /// Function declarations exposed to the model.
  List<Tool> get tools => [
        Tool.functionDeclarations([
          // ── Appearance ──────────────────────────────────────────────
          FunctionDeclaration(
            'set_theme',
            'Switch the app between dark and light appearance.',
            parameters: {
              'mode': Schema.enumString(
                enumValues: const ['dark', 'light'],
                description: 'The appearance mode to switch to.',
              ),
            },
          ),
          FunctionDeclaration(
            'set_accent_color',
            'Change the app accent/theme color to a named color.',
            parameters: {
              'color': Schema.enumString(
                enumValues: AccentColors.names,
                description: 'The accent color name.',
              ),
            },
          ),
          FunctionDeclaration(
            'adjust_text_size',
            'Make the app text larger or smaller, or reset it to default.',
            parameters: {
              'action': Schema.enumString(
                enumValues: const ['increase', 'decrease', 'reset'],
                description: 'How to change the text size.',
              ),
            },
          ),
          FunctionDeclaration(
            'toggle_winter_mode',
            'Turn the seasonal winter (snow) mode on or off.',
            parameters: {
              'enabled': Schema.boolean(
                description: 'True to enable winter mode, false to disable.',
              ),
            },
          ),
          // ── Habits ──────────────────────────────────────────────────
          FunctionDeclaration(
            'create_habit',
            'Create a new recurring habit for the user to track. Optionally set '
                'a daily reminder time. Use when the user wants to add/start a '
                'habit.',
            parameters: {
              'title': Schema.string(
                description: 'Concise habit name, e.g. "Play badminton".',
              ),
              'frequency': Schema.enumString(
                enumValues: const ['daily', 'weekdays', 'weekends'],
                description: 'How often it repeats. Default "daily".',
              ),
              'reminder_hour': Schema.integer(
                description:
                    'Reminder hour in 24-hour format (0-23). Omit if none.',
              ),
              'reminder_minute': Schema.integer(
                description: 'Reminder minute (0-59). Omit if none.',
              ),
            },
            optionalParameters: [
              'frequency',
              'reminder_hour',
              'reminder_minute',
            ],
          ),
          FunctionDeclaration(
            'update_habit_reminder',
            'Change the reminder time of the habit currently being discussed. '
                'Use for follow-ups like "change it to 7:30".',
            parameters: {
              'reminder_hour': Schema.integer(
                description: 'New reminder hour in 24-hour format (0-23).',
              ),
              'reminder_minute': Schema.integer(
                description: 'New reminder minute (0-59).',
              ),
            },
          ),
          // ── Actions ─────────────────────────────────────────────────
          FunctionDeclaration(
            'log_water',
            'Log water the user drank. Default one glass (250 ml) if no amount.',
            parameters: {
              'amount_ml': Schema.integer(
                description: 'Amount in millilitres. Omit for one glass (250).',
              ),
            },
            optionalParameters: ['amount_ml'],
          ),
          FunctionDeclaration(
            'log_intention',
            'Add a wellness intention/goal for the user.',
            parameters: {
              'title': Schema.string(
                description: 'The wellness intention, e.g. "Sleep earlier".',
              ),
            },
          ),
          FunctionDeclaration(
            'refresh_plan',
            "Regenerate today's wellness plan for the user.",
            parameters: const {},
          ),
          FunctionDeclaration(
            'submit_check_in',
            "Record the user's daily wellness check-in and regenerate their "
                'plan. Provide whatever values the user shared; omit unknowns.',
            parameters: {
              'energy_score': Schema.integer(
                description: 'Energy from 1 (drained) to 5 (energized).',
              ),
              'mood': Schema.enumString(
                enumValues: const [
                  'calm',
                  'anxious',
                  'tired',
                  'energized',
                  'stressed',
                  'content',
                ],
                description: 'Emotional mood.',
              ),
              'recovery': Schema.enumString(
                enumValues: const [
                  'wellRested',
                  'sore',
                  'fatigued',
                  'recovering',
                ],
                description: 'How the body is recovering.',
              ),
              'available_time': Schema.enumString(
                enumValues: const [
                  'under10',
                  'range10_20',
                  'range20_40',
                  'range40_60',
                  'over60',
                ],
                description: 'Time available today.',
              ),
            },
            optionalParameters: [
              'energy_score',
              'mood',
              'recovery',
              'available_time',
            ],
          ),
          // ── Navigation ──────────────────────────────────────────────
          FunctionDeclaration(
            'navigate',
            'Open another screen/tab in the app (e.g. settings, sleep coach, '
                'meditation). Set has_wellness_context to true ONLY if the '
                'conversation so far included meaningful wellness discussion '
                '(feelings, stress, sleep, habits, goals) that would be worth '
                'saving as a reflection; set it to false for a plain request '
                'like "go to settings" with no wellness discussion.',
            parameters: {
              'destination': Schema.enumString(
                enumValues: const [
                  'home',
                  'intentions',
                  'habitBuilder',
                  'reflection',
                  'settings',
                  'nutrition',
                  'mealPlanner',
                  'calorieBudget',
                  'hydration',
                  'sleep',
                  'meditation',
                  'periodTracker',
                  'weightTracker',
                  'mindfulTravel',
                  'breathing',
                  'meditationSession',
                  'checkIn',
                ],
                description: 'Where to go.',
              ),
              'has_wellness_context': Schema.boolean(
                description:
                    'True if the conversation had wellness content worth '
                    'saving as a reflection before leaving.',
              ),
            },
          ),
          // ── End conversation ────────────────────────────────────────
          FunctionDeclaration(
            'end_conversation',
            'End the live conversation and close the session. Call this when '
                'the user wants to finish (e.g. "let\'s end", "I\'m done", '
                '"goodbye"). Give a brief warm sign-off first. The conversation '
                'is saved automatically — do not ask about saving.',
            parameters: const {},
          ),
        ]),
      ];

  /// Executes a tool call and returns a result payload for the model.
  Future<Map<String, Object?>> handleToolCall(
      String name, Map<String, Object?> args) async {
    switch (name) {
      case 'set_theme':
        return _setTheme(args);
      case 'set_accent_color':
        return _setAccentColor(args);
      case 'adjust_text_size':
        return _adjustTextSize(args);
      case 'toggle_winter_mode':
        return _toggleWinterMode(args);
      case 'create_habit':
        return _createHabit(args);
      case 'update_habit_reminder':
        return _updateHabitReminder(args);
      case 'log_water':
        return _logWater(args);
      case 'log_intention':
        return _logIntention(args);
      case 'refresh_plan':
        return _refreshPlan();
      case 'submit_check_in':
        return _submitCheckIn(args);
      case 'navigate':
        return _navigate(args);
      case 'end_conversation':
        return _endConversation(args);
      default:
        return {'status': 'error', 'message': 'Unknown action "$name".'};
    }
  }

  // ── Appearance ────────────────────────────────────────────────────────

  Map<String, Object?> _setTheme(Map<String, Object?> args) {
    final mode = (args['mode'] as String?)?.toLowerCase();
    if (mode == 'dark') {
      _appState.setThemeMode(ThemeMode.dark);
      return {'status': 'ok', 'message': 'Switched to dark mode.'};
    } else if (mode == 'light') {
      _appState.setThemeMode(ThemeMode.light);
      return {'status': 'ok', 'message': 'Switched to light mode.'};
    }
    return {'status': 'error', 'message': 'Say "dark" or "light".'};
  }

  Map<String, Object?> _setAccentColor(Map<String, Object?> args) {
    final name = args['color'] as String?;
    final value = AccentColors.resolve(name);
    if (value == null) {
      return {'status': 'error', 'message': 'Unknown color "$name".'};
    }
    _appState.setThemeColor(Color(value));
    return {'status': 'ok', 'message': 'Changed the accent color to $name.'};
  }

  Map<String, Object?> _adjustTextSize(Map<String, Object?> args) {
    final action = (args['action'] as String?)?.toLowerCase();
    switch (action) {
      case 'increase':
        _appState.setTextScaleFactor(_appState.textScaleFactor + 0.1);
        return {'status': 'ok', 'message': 'Made the text larger.'};
      case 'decrease':
        _appState.setTextScaleFactor(_appState.textScaleFactor - 0.1);
        return {'status': 'ok', 'message': 'Made the text smaller.'};
      case 'reset':
        _appState.setTextScaleFactor(1.0);
        return {'status': 'ok', 'message': 'Reset the text size.'};
      default:
        return {
          'status': 'error',
          'message': 'Say increase, decrease, or reset.'
        };
    }
  }

  Map<String, Object?> _toggleWinterMode(Map<String, Object?> args) {
    final enabled = args['enabled'] as bool? ?? !_appState.isWinterMode;
    _appState.setWinterMode(enabled);
    return {
      'status': 'ok',
      'message': enabled ? 'Winter mode is on.' : 'Winter mode is off.',
    };
  }

  // ── Habits ────────────────────────────────────────────────────────────

  Future<Map<String, Object?>> _createHabit(Map<String, Object?> args) async {
    final title = (args['title'] as String?)?.trim();
    if (title == null || title.isEmpty) {
      return {'status': 'error', 'message': 'A habit name is required.'};
    }

    final (frequency, activeDays) = _resolveFrequency(args['frequency']);
    final hour = _asInt(args['reminder_hour'], 0, 23);
    final minute = _asInt(args['reminder_minute'], 0, 59);
    final hasReminder = hour != null && minute != null;

    try {
      final habit = await _habits.createHabit(
        title: title,
        tool: HabitTool.custom,
        frequency: frequency,
        activeDays: activeDays,
      );
      _lastHabitId = habit.id;
      _lastHabitTitle = habit.title;

      var reminderNote = '';
      if (hasReminder) {
        final granted = await _ensureNotificationPermission();
        await _habits.setReminder(habit.id, hour, minute);
        reminderNote = granted
            ? ' Reminder set for ${_fmt(hour, minute)}.'
            : ' Reminder saved, but notifications are off.';
      }

      return {
        'status': 'ok',
        'message': 'Created "$title" (${_freqLabel(frequency)}).$reminderNote',
      };
    } catch (e) {
      if (kDebugMode) debugPrint('LiveToolBridge.create_habit failed: $e');
      return {'status': 'error', 'message': 'Could not create the habit.'};
    }
  }

  Future<Map<String, Object?>> _updateHabitReminder(
      Map<String, Object?> args) async {
    final id = _lastHabitId;
    if (id == null) {
      return {
        'status': 'error',
        'message': 'No habit is in context to update. Ask which habit.',
      };
    }
    if (!_habits.habits.any((h) => h.id == id)) {
      _lastHabitId = null;
      return {'status': 'error', 'message': 'That habit no longer exists.'};
    }
    final hour = _asInt(args['reminder_hour'], 0, 23);
    final minute = _asInt(args['reminder_minute'], 0, 59);
    if (hour == null || minute == null) {
      return {'status': 'error', 'message': 'A valid time is required.'};
    }
    try {
      final granted = await _ensureNotificationPermission();
      await _habits.setReminder(id, hour, minute);
      return {
        'status': 'ok',
        'message': granted
            ? 'Moved the reminder for "${_lastHabitTitle ?? 'your habit'}" to '
                '${_fmt(hour, minute)}.'
            : 'Reminder updated, but notifications are off.',
      };
    } catch (e) {
      if (kDebugMode) debugPrint('LiveToolBridge.update_reminder failed: $e');
      return {'status': 'error', 'message': 'Could not update the reminder.'};
    }
  }

  // ── Actions ───────────────────────────────────────────────────────────

  Future<Map<String, Object?>> _logWater(Map<String, Object?> args) async {
    final ml = _asInt(args['amount_ml'], 1, 5000) ?? 250;
    try {
      await _hydration.logWater(ml, source: 'voice');
      return {'status': 'ok', 'message': 'Logged ${ml}ml of water.'};
    } catch (e) {
      if (kDebugMode) debugPrint('LiveToolBridge.log_water failed: $e');
      return {'status': 'error', 'message': 'Could not log water.'};
    }
  }

  Future<Map<String, Object?>> _logIntention(Map<String, Object?> args) async {
    final title = (args['title'] as String?)?.trim();
    if (title == null || title.isEmpty) {
      return {'status': 'error', 'message': 'An intention is required.'};
    }
    // Match the Assistant's free-tier limit.
    if (!_appState.isPro && _appState.dreams.length >= 3) {
      return {
        'status': 'error',
        'message':
            'The free plan allows 3 intentions. Upgrade to Premium for more.',
      };
    }
    try {
      await _appState.addDream(title);
      return {'status': 'ok', 'message': 'Added your intention: "$title".'};
    } catch (e) {
      if (kDebugMode) debugPrint('LiveToolBridge.log_intention failed: $e');
      return {'status': 'error', 'message': 'Could not add the intention.'};
    }
  }

  Future<Map<String, Object?>> _refreshPlan() async {
    final uid = _uid;
    if (uid == null) {
      return {'status': 'error', 'message': 'Please sign in first.'};
    }
    // Regenerating the plan is a Premium feature (matches the Assistant).
    if (!_appState.isPro) {
      return {
        'status': 'error',
        'message': 'Regenerating your plan is a Premium feature.',
      };
    }
    try {
      final checkIn = _checkIn.todaysCheckIn ??
          CheckIn(
            id: 'voice_${const Uuid().v4()}',
            date: DateTime.now(),
            energyScore: 3,
            availableTime: AvailableTimeRange.range20_40,
          );
      await _plan.regeneratePlan(uid, checkIn,
          preferredMethods: _appState.preferredMethods);
      return {'status': 'ok', 'message': 'Refreshed your plan for today.'};
    } catch (e) {
      if (kDebugMode) debugPrint('LiveToolBridge.refresh_plan failed: $e');
      return {'status': 'error', 'message': 'Could not refresh the plan.'};
    }
  }

  Future<Map<String, Object?>> _submitCheckIn(Map<String, Object?> args) async {
    final uid = _uid;
    if (uid == null) {
      return {'status': 'error', 'message': 'Please sign in first.'};
    }
    final energy = _asInt(args['energy_score'], 1, 5);
    final mood = _enumByName(MoodState.values, args['mood'] as String?);
    final recovery =
        _enumByName(RecoveryStatus.values, args['recovery'] as String?);
    final time = _enumByName(
        AvailableTimeRange.values, args['available_time'] as String?);

    if (energy == null && mood == null && recovery == null && time == null) {
      return {
        'status': 'error',
        'message': 'Ask the user how they are feeling first.',
      };
    }

    final skipped = <String>[
      if (energy == null) 'energyScore',
      if (mood == null) 'moodState',
      if (recovery == null) 'recoveryStatus',
      if (time == null) 'availableTime',
    ];

    try {
      // submitCheckIn asserts loadTodaysCheckIn was called first (sets _userId).
      await _checkIn.loadTodaysCheckIn(uid);
      final checkIn = CheckIn(
        id: const Uuid().v4(),
        date: DateTime.now(),
        energyScore: energy,
        moodState: mood,
        recoveryStatus: recovery,
        availableTime: time,
        skippedFields: skipped,
      );
      await _checkIn.submitCheckIn(checkIn);
      await _plan.generatePlan(
        uid,
        checkIn,
        intentions: _appState.intentions,
        cycleContext: _appState.cyclePhaseContext,
        travelContext: _appState.travelContext,
        preferredMethods: _appState.preferredMethods,
      );
      return {'status': 'ok', 'message': 'Saved your check-in and updated your plan.'};
    } catch (e) {
      if (kDebugMode) debugPrint('LiveToolBridge.submit_check_in failed: $e');
      return {'status': 'error', 'message': 'Could not save the check-in.'};
    }
  }

  // ── Navigation ──────────────────────────────────────────────────────────

  Map<String, Object?> _navigate(Map<String, Object?> args) {
    final dest = _destByName(args['destination'] as String?);
    if (dest == null) {
      return {'status': 'error', 'message': 'Unknown destination.'};
    }
    final hasContext = args['has_wellness_context'] as bool? ?? false;
    final cb = onNavigate;
    if (cb == null) {
      return {'status': 'error', 'message': 'Navigation is unavailable.'};
    }
    // The UI orchestrates end-session + optional reflection + navigate.
    cb(LiveNavRequest(destination: dest, hasWellnessContext: hasContext));
    return {
      'status': 'ok',
      'message': 'Taking you there now.',
    };
  }

  Map<String, Object?> _endConversation(Map<String, Object?> args) {
    final cb = onEndConversation;
    if (cb == null) {
      return {'status': 'error', 'message': 'Cannot end right now.'};
    }
    cb(const LiveEndRequest(save: false));
    return {'status': 'ok', 'message': 'Ending the conversation.'};
  }

  /// Applies a [LiveNavDestination] to the app: tabs via [AppNavigationService],
  /// pushed screens via [navigatorKey]. Called by the UI AFTER the Live session
  /// has been torn down. [navigatorKey] is the root navigator.
  void applyNavigation(
    LiveNavDestination dest,
    GlobalKey<NavigatorState> navigatorKey,
  ) {
    // Bottom tabs.
    switch (dest) {
      case LiveNavDestination.home:
        _navService.goToTab(AppTab.home);
        return;
      case LiveNavDestination.intentions:
        _navService.goToTab(AppTab.intentions);
        return;
      case LiveNavDestination.habitBuilder:
        _navService.goToTab(AppTab.habitBuilder);
        return;
      case LiveNavDestination.reflection:
        _navService.goToTab(AppTab.reflection);
        return;
      case LiveNavDestination.checkIn:
        // Check-in lives on Home; the pal can run submit_check_in by voice, so
        // just surface Home here.
        _navService.goToTab(AppTab.home);
        return;
      default:
        break;
    }
    // Pushed screens are resolved by the UI (which owns the screen imports) via
    // [screenForDestination]; here we just push it if provided.
    final builder = _pushBuilder;
    final nav = navigatorKey.currentState;
    if (builder != null && nav != null) {
      final screen = builder(dest);
      if (screen != null) {
        nav.push(MaterialPageRoute(builder: (_) => screen));
      }
    }
  }

  /// Set by the UI so the bridge can build pushed screens without importing
  /// them (keeps the service layer free of screen dependencies).
  Widget? Function(LiveNavDestination dest)? _pushBuilder;
  set pushBuilder(Widget? Function(LiveNavDestination dest)? b) =>
      _pushBuilder = b;

  /// Whether [dest] is a bottom tab (handled entirely by the bridge) vs a
  /// pushed screen (needs the UI's screen builder).
  static bool isTab(LiveNavDestination dest) {
    switch (dest) {
      case LiveNavDestination.home:
      case LiveNavDestination.intentions:
      case LiveNavDestination.habitBuilder:
      case LiveNavDestination.reflection:
      case LiveNavDestination.checkIn:
        return true;
      default:
        return false;
    }
  }

  // ── helpers ───────────────────────────────────────────────────────────

  LiveNavDestination? _destByName(String? name) {
    if (name == null) return null;
    for (final d in LiveNavDestination.values) {
      if (d.name == name) return d;
    }
    return null;
  }

  T? _enumByName<T extends Enum>(List<T> values, String? name) {
    if (name == null) return null;
    for (final v in values) {
      if (v.name == name) return v;
    }
    return null;
  }

  (HabitFrequency, List<int>) _resolveFrequency(Object? raw) {
    switch (raw) {
      case 'weekdays':
        return (HabitFrequency.weekdays, const [1, 2, 3, 4, 5]);
      case 'weekends':
        return (HabitFrequency.weekends, const [6, 7]);
      default:
        return (HabitFrequency.daily, const [1, 2, 3, 4, 5, 6, 7]);
    }
  }

  String _freqLabel(HabitFrequency f) {
    switch (f) {
      case HabitFrequency.weekdays:
        return 'weekdays';
      case HabitFrequency.weekends:
        return 'weekends';
      default:
        return 'every day';
    }
  }

  int? _asInt(Object? v, int min, int max) {
    final n = v is int ? v : (v is num ? v.toInt() : null);
    if (n == null || n < min || n > max) return null;
    return n;
  }

  String _fmt(int hour, int minute) {
    final period = hour >= 12 ? 'PM' : 'AM';
    final h12 = hour % 12 == 0 ? 12 : hour % 12;
    return '$h12:${minute.toString().padLeft(2, '0')} $period';
  }

  Future<bool> _ensureNotificationPermission() async {
    final notifier = NotificationService();
    return await notifier.hasNotificationPermission()
        ? true
        : await notifier.requestPermission();
  }
}
