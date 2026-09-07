import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/nutrition_models.dart';

/// Persists meals to Firestore under `users/{userId}/meals/{mealId}` with a
/// local SharedPreferences cache for offline/instant reads, plus daily
/// nutrition goals on the user doc.
class MealRepository {
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  final FirebaseStorage _storage;

  MealRepository({
    FirebaseFirestore? db,
    FirebaseAuth? auth,
    FirebaseStorage? storage,
  })  : _db = db ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _storage = storage ?? FirebaseStorage.instance;

  String? get _uid => _auth.currentUser?.uid;

  static const String _cacheKey = 'nutrition_meals_cache';
  static const String _goalsKey = 'nutrition_goals';

  CollectionReference<Map<String, dynamic>>? get _mealsCol {
    final uid = _uid;
    if (uid == null) return null;
    return _db.collection('users').doc(uid).collection('meals');
  }

  // ---------------------------------------------------------------------------
  // Meals
  // ---------------------------------------------------------------------------

  /// Loads meals, cache-first for instant UI then Firestore for the source of
  /// truth. Returns meals sorted newest-first.
  Future<List<Meal>> loadMeals({int limit = 60}) async {
    // Firestore (authoritative).
    final col = _mealsCol;
    if (col != null) {
      try {
        final snap = await col
            .orderBy('createdAt', descending: true)
            .limit(limit)
            .get();
        final meals =
            snap.docs.map((d) => Meal.fromMap(d.id, d.data())).toList();
        await _cacheMeals(meals);
        return meals;
      } catch (e) {
        debugPrint('❌ MealRepository.loadMeals Firestore error: $e');
      }
    }
    // Fallback to cache.
    return _loadCachedMeals();
  }

  /// Saves [meal] to Firestore (and refreshes the local cache). Returns the
  /// meal, unchanged, so callers can update state optimistically.
  Future<Meal> saveMeal(Meal meal) async {
    final col = _mealsCol;
    if (col != null) {
      try {
        await col.doc(meal.id).set(meal.toMap());
      } catch (e) {
        debugPrint('❌ MealRepository.saveMeal error: $e');
      }
    }
    return meal;
  }

  Future<void> deleteMeal(String mealId) async {
    final col = _mealsCol;
    if (col != null) {
      try {
        await col.doc(mealId).delete();
      } catch (e) {
        debugPrint('❌ MealRepository.deleteMeal error: $e');
      }
    }
  }

  /// Uploads a meal photo to Firebase Storage and returns its download URL,
  /// or null if not signed in / on error.
  Future<String?> uploadMealImage(File image) async {
    final uid = _uid;
    if (uid == null) return null;
    try {
      final name = '${DateTime.now().millisecondsSinceEpoch}_${p.basename(image.path)}';
      final ref = _storage.ref('meal-photos/$uid/$name');
      await ref.putFile(image);
      return await ref.getDownloadURL();
    } catch (e) {
      debugPrint('❌ MealRepository.uploadMealImage error: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Goals
  // ---------------------------------------------------------------------------
  Future<NutritionGoals> loadGoals({Map<String, dynamic>? cloudProfile}) async {
    final prefs = await SharedPreferences.getInstance();

    if (cloudProfile != null && cloudProfile['nutrition_goals'] is Map) {
      try {
        final g = NutritionGoals.fromMap(
            Map<String, dynamic>.from(cloudProfile['nutrition_goals'] as Map));
        await prefs.setString(_goalsKey, jsonEncode(g.toMap()));
        return g;
      } catch (_) {}
    }

    final raw = prefs.getString(_goalsKey);
    if (raw != null) {
      try {
        return NutritionGoals.fromMap(
            jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {}
    }
    return const NutritionGoals();
  }

  Future<void> saveGoals(NutritionGoals goals) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_goalsKey, jsonEncode(goals.toMap()));

    final uid = _uid;
    if (uid != null) {
      try {
        await _db.collection('users').doc(uid).set({
          'nutrition_goals': goals.toMap(),
          'updated_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('❌ MealRepository.saveGoals error: $e');
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Local cache
  // ---------------------------------------------------------------------------
  Future<void> _cacheMeals(List<Meal> meals) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = meals.map((m) {
        final map = m.toMap();
        map['id'] = m.id;
        return map;
      }).toList();
      await prefs.setString(_cacheKey, jsonEncode(list));
    } catch (e) {
      debugPrint('❌ MealRepository cache write error: $e');
    }
  }

  Future<List<Meal>> _loadCachedMeals() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) {
            final m = Map<String, dynamic>.from(e as Map);
            return Meal.fromMap(m['id'] as String? ?? 'm', m);
          })
          .toList();
    } catch (e) {
      debugPrint('❌ MealRepository cache read error: $e');
      return [];
    }
  }
}
