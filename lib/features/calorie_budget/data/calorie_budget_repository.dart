import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/calorie_budget_models.dart';

/// Persists daily calorie budgets to Firestore under
/// `users/{userId}/calorieBudgets/{date}`, with per-day exercise entries and a
/// goal-achievement streak. Uses a local cache for instant/offline reads.
class CalorieBudgetRepository {
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  CalorieBudgetRepository({FirebaseFirestore? db, FirebaseAuth? auth})
      : _db = db ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  String? get _uid => _auth.currentUser?.uid;

  static String _exerciseKey(String date) =>
      'calorie_budget_exercises_$date';
  static const String _goalModeKey = 'calorie_budget_goal_mode';
  static const String _budgetOverrideKey = 'calorie_budget_override';
  static const String _streakKey = 'calorie_budget_streak';
  static const String _bestStreakKey = 'calorie_budget_best_streak';
  static const String _streakDateKey = 'calorie_budget_streak_date';

  CollectionReference<Map<String, dynamic>>? get _col {
    final uid = _uid;
    if (uid == null) return null;
    return _db.collection('users').doc(uid).collection('calorieBudgets');
  }

  static String dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  // ---------------------------------------------------------------------------
  // Daily budget documents
  // ---------------------------------------------------------------------------
  Future<void> saveDaily(DailyCalorieBudget day) async {
    final col = _col;
    if (col != null) {
      try {
        await col.doc(day.date).set(day.toMap());
      } catch (e) {
        debugPrint('❌ CalorieBudgetRepository.saveDaily: $e');
      }
    }
  }

  /// Loads the last [limit] daily records (newest first) for trends.
  Future<List<DailyCalorieBudget>> loadRecent({int limit = 30}) async {
    final col = _col;
    if (col == null) return [];
    try {
      final snap = await col
          .orderBy('date', descending: true)
          .limit(limit)
          .get();
      return snap.docs
          .map((d) => DailyCalorieBudget.fromMap(d.data()))
          .toList();
    } catch (e) {
      debugPrint('❌ CalorieBudgetRepository.loadRecent: $e');
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // Exercise entries (local per-day + mirrored via daily doc timeline)
  // ---------------------------------------------------------------------------
  Future<List<ExerciseEntry>> loadExercises(DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_exerciseKey(dateKey(date)));
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => ExerciseEntry.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveExercises(DateTime date, List<ExerciseEntry> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_exerciseKey(dateKey(date)),
        jsonEncode(items.map((e) => e.toMap()).toList()));

    final uid = _uid;
    if (uid != null) {
      try {
        await _db.collection('users').doc(uid).set({
          'calorie_exercises_${dateKey(date)}':
              items.map((e) => e.toMap()).toList(),
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('❌ CalorieBudgetRepository.saveExercises: $e');
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Settings: goal mode + optional budget override
  // ---------------------------------------------------------------------------
  Future<GoalMode> loadGoalMode({Map<String, dynamic>? cloudProfile}) async {
    final prefs = await SharedPreferences.getInstance();
    if (cloudProfile != null && cloudProfile['calorie_goal_mode'] is String) {
      final g = GoalModeInfo.fromName(cloudProfile['calorie_goal_mode'] as String);
      await prefs.setString(_goalModeKey, g.name);
      return g;
    }
    return GoalModeInfo.fromName(prefs.getString(_goalModeKey));
  }

  Future<void> saveGoalMode(GoalMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_goalModeKey, mode.name);
    final uid = _uid;
    if (uid != null) {
      try {
        await _db.collection('users').doc(uid).set({
          'calorie_goal_mode': mode.name,
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('❌ CalorieBudgetRepository.saveGoalMode: $e');
      }
    }
  }

  /// Optional user override for the daily budget (0 = derive from profile).
  Future<int> loadBudgetOverride() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_budgetOverrideKey) ?? 0;
  }

  Future<void> saveBudgetOverride(int budget) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_budgetOverrideKey, budget);
    final uid = _uid;
    if (uid != null) {
      try {
        await _db.collection('users').doc(uid).set({
          'calorie_budget_override': budget,
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('❌ CalorieBudgetRepository.saveBudgetOverride: $e');
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Streak
  // ---------------------------------------------------------------------------
  Future<Map<String, dynamic>> loadStreak() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'current': prefs.getInt(_streakKey) ?? 0,
      'best': prefs.getInt(_bestStreakKey) ?? 0,
      'lastDate': prefs.getString(_streakDateKey),
    };
  }

  Future<void> saveStreak(int current, int best, String lastDate) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_streakKey, current);
    await prefs.setInt(_bestStreakKey, best);
    await prefs.setString(_streakDateKey, lastDate);
    final uid = _uid;
    if (uid != null) {
      try {
        await _db.collection('users').doc(uid).set({
          'calorie_streak_current': current,
          'calorie_streak_best': best,
          'calorie_streak_date': lastDate,
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('❌ CalorieBudgetRepository.saveStreak: $e');
      }
    }
  }
}
