import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/meditation_models.dart';

/// Fully-offline persistence for the Meditation & Mindfulness tool using
/// SharedPreferences (matching the app's existing persistence approach). Stores
/// session history, unlocked achievements, and reminders locally.
class MeditationRepository {
  static const String _historyKey = 'meditation_history';
  static const String _achievementsKey = 'meditation_achievements';
  static const String _remindersKey = 'meditation_reminders';
  static const String _longestStreakKey = 'meditation_longest_streak';

  // Keep at most this many records locally (analytics only needs recent data).
  static const int _maxHistory = 400;

  // ---------------------------------------------------------------------------
  // Session history
  // ---------------------------------------------------------------------------
  Future<List<MeditationSessionRecord>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_historyKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) =>
              MeditationSessionRecord.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      debugPrint('❌ MeditationRepository.loadHistory: $e');
      return [];
    }
  }

  Future<void> addSession(MeditationSessionRecord record) async {
    final history = await loadHistory();
    history.insert(0, record);
    if (history.length > _maxHistory) {
      history.removeRange(_maxHistory, history.length);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _historyKey, jsonEncode(history.map((r) => r.toMap()).toList()));
  }

  // ---------------------------------------------------------------------------
  // Achievements
  // ---------------------------------------------------------------------------
  Future<Set<String>> loadUnlockedAchievements() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_achievementsKey);
    return raw?.toSet() ?? <String>{};
  }

  Future<void> saveUnlockedAchievements(Set<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_achievementsKey, ids.toList());
  }

  // ---------------------------------------------------------------------------
  // Longest streak (persisted separately so it survives a broken streak)
  // ---------------------------------------------------------------------------
  Future<int> loadLongestStreak() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_longestStreakKey) ?? 0;
  }

  Future<void> saveLongestStreak(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_longestStreakKey, value);
  }

  // ---------------------------------------------------------------------------
  // Reminders
  // ---------------------------------------------------------------------------
  Future<List<MindfulnessReminder>> loadReminders() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_remindersKey);
    if (raw == null) return _defaultReminders();
    try {
      return MindfulnessReminder.decodeList(raw);
    } catch (e) {
      debugPrint('❌ MeditationRepository.loadReminders: $e');
      return _defaultReminders();
    }
  }

  Future<void> saveReminders(List<MindfulnessReminder> reminders) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_remindersKey, MindfulnessReminder.encodeList(reminders));
  }

  List<MindfulnessReminder> _defaultReminders() => const [
        MindfulnessReminder(
            id: 'morning',
            label: 'Morning Mindfulness',
            hour: 8,
            minute: 0,
            enabled: false),
        MindfulnessReminder(
            id: 'afternoon',
            label: 'Afternoon Reset',
            hour: 14,
            minute: 0,
            enabled: false),
        MindfulnessReminder(
            id: 'evening',
            label: 'Evening Wind Down',
            hour: 20,
            minute: 0,
            enabled: false),
        MindfulnessReminder(
            id: 'bedtime',
            label: 'Bedtime Meditation',
            hour: 22,
            minute: 0,
            enabled: false),
      ];
}
