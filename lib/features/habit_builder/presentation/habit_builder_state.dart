import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
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
      // The home-screen widget's background isolate writes habit toggles into
      // this same key. Reload so the UI isolate sees the latest value instead
      // of a stale in-memory copy.
      await prefs.reload();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        _habits = Habit.decodeList(raw);
      }
    } catch (e) {
      debugPrint('❌ HabitBuilderState.load: $e');
    }
    notifyListeners();
    // Populate the home-screen "Today's Habits" widget on load.
    await _pushHabitsToWidget();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, Habit.encodeList(_habits));
    } catch (e) {
      debugPrint('❌ HabitBuilderState._save: $e');
    }
    // Keep the home-screen "Today's Habits" widget in sync after every save.
    await _pushHabitsToWidget();
  }

  // ---------------------------------------------------------------------------
  // Home-screen widget ("Today's Habits")
  // ---------------------------------------------------------------------------

  /// Today's date key ("yyyy-MM-dd"), matching Habit's completion log keys.
  static String _todayKey() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-'
        '${n.day.toString().padLeft(2, '0')}';
  }

  /// Pushes today's active habits to the native widget from the UI isolate.
  Future<void> _pushHabitsToWidget() async {
    try {
      await _writeHabitWidgetData(todaysHabits
          .map((h) => {
                'id': h.id,
                'title': h.title,
                'emoji': h.tool.emoji,
                'checked': h.isCompletedToday,
              })
          .toList());
      await HomeWidget.updateWidget(
          name: 'HabitWidget', androidName: 'HabitWidget');
    } catch (e) {
      debugPrint('❌ HabitBuilderState._pushHabitsToWidget: $e');
    }
  }

  /// Writes the "Today's Habits" widget keys.
  ///
  /// Keys: habit_has_habits (bool), habit_count (int, ≤2 shown),
  /// habit_completed / habit_total / habit_progress (int),
  /// and per row 1..2: habit_{n}_id / _text / _emoji / _checked.
  ///
  /// Mirrors the Wellness Intention widget: only the first two habits are
  /// shown as tappable rows, while progress reflects the full day's totals.
  ///
  /// [items] is an ordered list of maps with id/title/emoji/checked for the
  /// habits scheduled today.
  static Future<void> _writeHabitWidgetData(
      List<Map<String, dynamic>> items) async {
    // Ensure writes land in the iOS app group the widget extension reads from.
    // Safe/no-op on Android. Idempotent, so calling it here covers both the UI
    // isolate and the background toggle isolate.
    await HomeWidget.setAppGroupId('group.com.aiwellnesspal.app');

    final total = items.length;
    final completed = items.where((h) => h['checked'] == true).length;
    const maxRows = 2;

    // Mirror the Wellness Intention widget: display the first two *incomplete*
    // habits as tappable rows. Progress still reflects the full day's totals.
    final incomplete =
        items.where((h) => h['checked'] != true).toList(growable: false);
    final rows = incomplete.take(maxRows).toList(growable: false);

    final allDone = total > 0 && completed == total;

    await HomeWidget.saveWidgetData<bool>('habit_has_habits', total > 0);
    await HomeWidget.saveWidgetData<bool>('habit_all_done', allDone);
    await HomeWidget.saveWidgetData<int>('habit_count', rows.length);
    await HomeWidget.saveWidgetData<int>('habit_completed', completed);
    await HomeWidget.saveWidgetData<int>('habit_total', total);
    await HomeWidget.saveWidgetData<int>('habit_progress',
        total == 0 ? 0 : ((completed / total) * 100).round());

    for (int i = 0; i < maxRows; i++) {
      final n = i + 1;
      if (i < rows.length) {
        final h = rows[i];
        await HomeWidget.saveWidgetData<String>('habit_${n}_id', h['id'] ?? '');
        await HomeWidget.saveWidgetData<String>(
            'habit_${n}_text', h['title'] ?? '');
        await HomeWidget.saveWidgetData<String>(
            'habit_${n}_emoji', h['emoji'] ?? '⭐');
        await HomeWidget.saveWidgetData<bool>(
            'habit_${n}_checked', h['checked'] == true);
      } else {
        await HomeWidget.saveWidgetData<String>('habit_${n}_id', '');
        await HomeWidget.saveWidgetData<String>('habit_${n}_text', '');
        await HomeWidget.saveWidgetData<String>('habit_${n}_emoji', '');
        await HomeWidget.saveWidgetData<bool>('habit_${n}_checked', false);
      }
    }
  }

  /// Background-isolate sync used by [AppState.backgroundCallback] when a habit
  /// checkbox is toggled from the home-screen widget. Reads the raw
  /// `habit_builder_habits` prefs, recomputes today's active habits, and writes
  /// the widget keys.
  @pragma('vm:entry-point')
  static Future<void> syncHabitWidgetFromPrefs(SharedPreferences prefs) async {
    try {
      final raw = prefs.getString(_prefsKey);
      final List<Map<String, dynamic>> items = [];
      if (raw != null && raw.isNotEmpty) {
        final habits = Habit.decodeList(raw);
        final today = habits
            .where((h) => h.isActive && h.isScheduledToday)
            .toList();
        for (final h in today) {
          items.add({
            'id': h.id,
            'title': h.title,
            'emoji': h.tool.emoji,
            'checked': h.isCompletedToday,
          });
        }
      }
      await _writeHabitWidgetData(items);
      await HomeWidget.updateWidget(
          name: 'HabitWidget', androidName: 'HabitWidget');
    } catch (e) {
      debugPrint('❌ HabitBuilderState.syncHabitWidgetFromPrefs: $e');
    }
  }

  /// Toggles today's completion for [habitId] directly in the raw prefs list
  /// (used from the background isolate). Returns true if a habit was changed.
  @pragma('vm:entry-point')
  static Future<bool> toggleHabitInPrefs(
      SharedPreferences prefs, String habitId) async {
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return false;
    try {
      final List<dynamic> list = jsonDecode(raw);
      final key = _todayKey();
      bool changed = false;
      for (final h in list) {
        if (h['id'] == habitId) {
          final log = Map<String, dynamic>.from(h['log'] ?? {});
          if (log.containsKey(key)) {
            log.remove(key);
          } else {
            final target = (h['targetValue'] as num?)?.toDouble() ?? 1.0;
            log[key] = target;
          }
          h['log'] = log;
          changed = true;
          break;
        }
      }
      if (changed) {
        await prefs.setString(_prefsKey, jsonEncode(list));
      }
      return changed;
    } catch (e) {
      debugPrint('❌ HabitBuilderState.toggleHabitInPrefs: $e');
      return false;
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
