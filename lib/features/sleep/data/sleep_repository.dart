import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/sleep_models.dart';

/// Persists Sleep Coach state: the onboarding-completed flag (local + cloud)
/// and daily sleep summaries to Firestore under `users/{uid}/sleep/{date}`.
///
/// Raw health data is not stored unnecessarily; only compact daily summaries.
class SleepRepository {
  FirebaseFirestore? _dbOverride;
  FirebaseAuth? _authOverride;
  FirebaseFirestore? _lazyDb;
  FirebaseAuth? _lazyAuth;

  SleepRepository({FirebaseFirestore? db, FirebaseAuth? auth})
      : _dbOverride = db,
        _authOverride = auth;

  // Lazily resolved so unit tests can use the SharedPreferences-only paths
  // without initializing Firebase.
  FirebaseFirestore get _db =>
      _dbOverride ??= (_lazyDb ??= FirebaseFirestore.instance);
  FirebaseAuth get _auth => _authOverride ??= (_lazyAuth ??= FirebaseAuth.instance);

  String? get _uid {
    try {
      return _auth.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  static const String _onboardedKey = 'sleep_coach_onboarded';

  CollectionReference<Map<String, dynamic>>? get _col {
    final uid = _uid;
    if (uid == null) return null;
    return _db.collection('users').doc(uid).collection('sleep');
  }

  static String dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  // ---------------------------------------------------------------------------
  // Onboarding
  // ---------------------------------------------------------------------------
  Future<bool> isOnboarded({Map<String, dynamic>? cloudProfile}) async {
    final prefs = await SharedPreferences.getInstance();
    if (cloudProfile != null && cloudProfile['sleep_onboarded'] == true) {
      await prefs.setBool(_onboardedKey, true);
      return true;
    }
    return prefs.getBool(_onboardedKey) ?? false;
  }

  Future<void> setOnboarded() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardedKey, true);
    final uid = _uid;
    if (uid != null) {
      try {
        await _db.collection('users').doc(uid).set({
          'sleep_onboarded': true,
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('❌ SleepRepository.setOnboarded: $e');
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Daily summary (compact, privacy-conscious)
  // ---------------------------------------------------------------------------
  Future<void> saveDailySummary({
    required SleepSession session,
    required SleepScore score,
    List<String> aiInsights = const [],
  }) async {
    final col = _col;
    if (col == null) return;
    try {
      await col.doc(dateKey(session.date)).set({
        'date': dateKey(session.date),
        'totalSleepMinutes': session.totalSleepMinutes,
        'score': score.value,
        'stages': {
          for (final s in session.stages) s.type.name: s.minutes,
        },
        'source': session.source,
        'aiInsights': aiInsights,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('❌ SleepRepository.saveDailySummary: $e');
    }
  }
}
