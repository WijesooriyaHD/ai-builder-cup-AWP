import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/hydration_models.dart';

/// Persists hydration data to Firestore under `users/{userId}/hydration/{date}`
/// with a local cache of today's entries, streak, and settings.
class HydrationRepository {
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  HydrationRepository({FirebaseFirestore? db, FirebaseAuth? auth})
      : _db = db ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  String? get _uid => _auth.currentUser?.uid;

  static String _entriesKey(String date) => 'hydration_entries_$date';
  static const String _streakKey = 'hydration_streak';
  static const String _bestStreakKey = 'hydration_best_streak';
  static const String _streakDateKey = 'hydration_streak_date';
  static const String _weatherKey = 'hydration_weather_extra';
  static const String _manualBaseKey = 'hydration_manual_base_ml';

  CollectionReference<Map<String, dynamic>>? get _col {
    final uid = _uid;
    if (uid == null) return null;
    return _db.collection('users').doc(uid).collection('hydration');
  }

  static String dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  // ---------------------------------------------------------------------------
  // Daily documents
  // ---------------------------------------------------------------------------
  Future<void> saveDaily(DailyHydration day) async {
    final col = _col;
    if (col != null) {
      try {
        await col.doc(day.date).set(day.toMap());
      } catch (e) {
        debugPrint('❌ HydrationRepository.saveDaily: $e');
      }
    }
  }

  Future<List<DailyHydration>> loadRecent({int limit = 30}) async {
    final col = _col;
    if (col == null) return [];
    try {
      final snap =
          await col.orderBy('date', descending: true).limit(limit).get();
      return snap.docs.map((d) => DailyHydration.fromMap(d.data())).toList();
    } catch (e) {
      debugPrint('❌ HydrationRepository.loadRecent: $e');
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // Today's entries (local cache; mirrored via daily doc)
  // ---------------------------------------------------------------------------
  Future<List<HydrationEntry>> loadEntries(DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_entriesKey(dateKey(date)));
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) =>
              HydrationEntry.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveEntries(DateTime date, List<HydrationEntry> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_entriesKey(dateKey(date)),
        jsonEncode(items.map((e) => e.toMap()).toList()));
  }

  // ---------------------------------------------------------------------------
  // Weather adjustment (persisted; future: live weather API populates this)
  // ---------------------------------------------------------------------------
  Future<WeatherAdjustment> loadWeather() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_weatherKey);
    if (raw == null) return const WeatherAdjustment();
    try {
      return WeatherAdjustment.fromMap(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const WeatherAdjustment();
    }
  }

  Future<void> saveWeather(WeatherAdjustment w) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_weatherKey, jsonEncode(w.toMap()));
  }

  // ---------------------------------------------------------------------------
  // Manual base target override (null = auto-calculated from profile)
  // ---------------------------------------------------------------------------
  Future<int?> loadManualBaseMl() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getInt(_manualBaseKey);
    return (v != null && v > 0) ? v : null;
  }

  Future<void> saveManualBaseMl(int? ml) async {
    final prefs = await SharedPreferences.getInstance();
    if (ml == null || ml <= 0) {
      await prefs.remove(_manualBaseKey);
    } else {
      await prefs.setInt(_manualBaseKey, ml);
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
          'hydration_streak_current': current,
          'hydration_streak_best': best,
          'hydration_streak_date': lastDate,
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('❌ HydrationRepository.saveStreak: $e');
      }
    }
  }
}
