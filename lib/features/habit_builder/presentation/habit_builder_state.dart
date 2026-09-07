import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../../services/notification_service.dart';
import '../domain/habit_models.dart';

/// State provider for the Habit Builder feature.
///
/// Persists habits locally via SharedPreferences (matching the app's
/// architecture). Habit completion is logged per-date so streak and progress
/// are always available offline.
class HabitBuilderState extends ChangeNotifier {
  static const String _prefsKey = 'habit_builder_habits';
  static const _uuid = Uuid();

  List<Habit> _habits = [];

  List<Habit> get habits => _habits;

  /// Only habits scheduled for today and marked active.
  List<Habit> get todaysHabits =>
      _habits.where((h) => h.isActive && h.isScheduledToday).toList();

  /// Number of today's habits that are already completed.
  int get completedTodayCount =>
      todaysHabits.where((h) => h.isCompletedToday).length;

  int get totalActive => _habits.where((h) => h.isActive).length;

  // ---------------------------------------------------------------------------
  // Loading
  // ---------------------------------------------------------------------------

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        _habits = Habit.decodeList(raw);
      }
    } catch (e) {
      debugPrint('❌ HabitBuilderState.load: $e');
    }
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, Habit.encodeList(_habits));
    } catch (e) {
      debugPrint('❌ HabitBuilderState._save: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // CRUD
  // ---------------------------------------------------------------------------

  Future<void> addHabit(Habit habit) async {
    _habits = [habit, ..._habits];
    notifyListeners();
    await _save();
  }

  /// Creates and adds a new habit from individual fields.
  Future<Habit> createHabit({
    required String title,
    String? description,
    required HabitTool tool,
    HabitFrequency frequency = HabitFrequency.daily,
    List<int> activeDays = const [1, 2, 3, 4, 5, 6, 7],
    double? targetValue,
    String? targetUnit,
  }) async {
    final habit = Habit(
      id: _uuid.v4(),
      title: title,
      description: description,
      tool: tool,
      frequency: frequency,
      activeDays: activeDays,
      targetValue: targetValue,
      targetUnit: targetUnit,
    );
    await addHabit(habit);
    return habit;
  }

  Future<void> updateHabit(Habit updated) async {
    _habits =
        _habits.map((h) => h.id == updated.id ? updated : h).toList();
    notifyListeners();
    await _save();
  }

  Future<void> deleteHabit(String id) async {
    _habits = _habits.where((h) => h.id != id).toList();
    notifyListeners();
    await _save();
    // Clean up any scheduled reminder for this habit.
    await NotificationService().cancelHabitReminder(id);
  }

  // ---------------------------------------------------------------------------
  // Reminders
  // ---------------------------------------------------------------------------

  /// ISO weekdays (1=Mon … 7=Sun) a habit is scheduled on, from its frequency.
  List<int> _weekdaysFor(Habit h) {
    switch (h.frequency) {
      case HabitFrequency.daily:
        return const [1, 2, 3, 4, 5, 6, 7];
      case HabitFrequency.weekdays:
        return const [1, 2, 3, 4, 5];
      case HabitFrequency.weekends:
        return const [6, 7];
      case HabitFrequency.custom:
        return h.activeDays.isEmpty
            ? const [1, 2, 3, 4, 5, 6, 7]
            : h.activeDays;
    }
  }

  /// Sets (or updates) a daily reminder for a habit at [hour]:[minute] and
  /// schedules the notification on the habit's active weekdays.
  Future<void> setReminder(String id, int hour, int minute) async {
    final idx = _habits.indexWhere((h) => h.id == id);
    if (idx == -1) return;

    final updated = _habits[idx]
        .copyWith(reminderHour: hour, reminderMinute: minute);
    _habits[idx] = updated;
    notifyListeners();
    await _save();

    await NotificationService().scheduleHabitReminder(
      habitId: updated.id,
      label: updated.title,
      hour: hour,
      minute: minute,
      weekdays: _weekdaysFor(updated),
    );
  }

  /// Removes a habit's reminder and cancels its scheduled notifications.
  Future<void> clearReminder(String id) async {
    final idx = _habits.indexWhere((h) => h.id == id);
    if (idx == -1) return;

    _habits[idx] = _habits[idx].copyWith(clearReminder: true);
    notifyListeners();
    await _save();

    await NotificationService().cancelHabitReminder(id);
  }

  Future<void> toggleActive(String id) async {
    _habits = _habits
        .map((h) => h.id == id ? h.copyWith(isActive: !h.isActive) : h)
        .toList();
    notifyListeners();
    await _save();
  }

  // ---------------------------------------------------------------------------
  // Completion logging
  // ---------------------------------------------------------------------------

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Marks the habit as completed for today (value = targetValue or 1.0).
  Future<void> markComplete(String id) async {
    final idx = _habits.indexWhere((h) => h.id == id);
    if (idx == -1) return;
    final h = _habits[idx];
    final key = _dateKey(DateTime.now());
    final newLog = Map<String, double>.from(h.log)
      ..[key] = h.targetValue ?? 1.0;
    _habits[idx] = h.copyWith(log: newLog);
    notifyListeners();
    await _save();
  }

  /// Removes the completion for today (undo).
  Future<void> markIncomplete(String id) async {
    final idx = _habits.indexWhere((h) => h.id == id);
    if (idx == -1) return;
    final h = _habits[idx];
    final key = _dateKey(DateTime.now());
    final newLog = Map<String, double>.from(h.log)..remove(key);
    _habits[idx] = h.copyWith(log: newLog);
    notifyListeners();
    await _save();
  }

  /// Toggle today's completion status.
  Future<void> toggleToday(String id) async {
    final h = _habits.firstWhere((h) => h.id == id,
        orElse: () => throw StateError('Habit $id not found'));
    if (h.isCompletedToday) {
      await markIncomplete(id);
    } else {
      await markComplete(id);
    }
  }

  // ---------------------------------------------------------------------------
  // Context string for today's plan (future integration)
  // ---------------------------------------------------------------------------

  /// A plain-text summary of today's active habits for injection into the AI
  /// daily plan prompt. Returns null when there are no habits set up yet.
  String? get habitContext {
    final today = todaysHabits;
    if (today.isEmpty) return null;
    final lines = today.map((h) {
      final target = (h.targetValue != null && h.targetUnit != null)
          ? ' (${h.targetValue} ${h.targetUnit})'
          : '';
      return '- ${h.title}$target [${h.tool.label}]';
    }).join('\n');
    return 'USER HABITS FOR TODAY:\n$lines\n'
        'Where possible, weave these habits into the wellness plan.';
  }
}
