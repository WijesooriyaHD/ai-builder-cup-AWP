import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart';

import '../features/habit_builder/domain/habit_models.dart';
import '../features/habit_builder/presentation/habit_builder_state.dart';
import 'notification_service.dart';

/// Bridges Gemini Live tool/function calls to the app's real actions so the
/// wellness pal can *do* things mid-conversation (create a habit, set a
/// reminder) — not just talk.
///
/// The [tools] declarations are handed to [LiveConversationService], and
/// [handleToolCall] is wired as its `onToolCall`. This keeps the Live service
/// free of app-state dependencies while reusing the same habit logic as the
/// rest of the app.
class LiveToolBridge {
  LiveToolBridge(this._habits);

  final HabitBuilderState _habits;

  /// The most recently created/updated habit id, so a follow-up like "remind me
  /// at 7:30" (update_habit_reminder) can resolve "it" within the conversation.
  String? _lastHabitId;
  String? _lastHabitTitle;

  /// Function declarations exposed to the model.
  List<Tool> get tools => [
        Tool.functionDeclarations([
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
        ]),
      ];

  /// Executes a tool call and returns a result payload for the model.
  Future<Map<String, Object?>> handleToolCall(
      String name, Map<String, Object?> args) async {
    switch (name) {
      case 'create_habit':
        return _createHabit(args);
      case 'update_habit_reminder':
        return _updateHabitReminder(args);
      default:
        return {
          'status': 'error',
          'message': 'Unknown action "$name".',
        };
    }
  }

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

  // --- helpers ---

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
