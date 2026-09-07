import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/meal_planner_models.dart';

/// Persists meal plans to Firestore under `users/{userId}/mealPlans/{planId}`,
/// with the user profile and favorites on the user doc plus a local cache of
/// the active plan for instant/offline loads.
class MealPlanRepository {
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  MealPlanRepository({FirebaseFirestore? db, FirebaseAuth? auth})
      : _db = db ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  String? get _uid => _auth.currentUser?.uid;

  static const String _activePlanKey = 'meal_planner_active_plan';
  static const String _profileKey = 'meal_planner_profile';
  static const String _favMealsKey = 'meal_planner_fav_meals';
  static const String _prefsKey = 'meal_planner_prefs'; // personalization

  CollectionReference<Map<String, dynamic>>? get _plansCol {
    final uid = _uid;
    if (uid == null) return null;
    return _db.collection('users').doc(uid).collection('mealPlans');
  }

  // ---------------------------------------------------------------------------
  // Profile
  // ---------------------------------------------------------------------------
  Future<UserProfile?> loadProfile({Map<String, dynamic>? cloudProfile}) async {
    final prefs = await SharedPreferences.getInstance();
    if (cloudProfile != null && cloudProfile['meal_planner_profile'] is Map) {
      try {
        final p = UserProfile.fromMap(Map<String, dynamic>.from(
            cloudProfile['meal_planner_profile'] as Map));
        await prefs.setString(_profileKey, p.toJson());
        return p;
      } catch (_) {}
    }
    final raw = prefs.getString(_profileKey);
    if (raw != null) {
      try {
        return UserProfile.fromJson(raw);
      } catch (_) {}
    }
    return null;
  }

  Future<void> saveProfile(UserProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profileKey, profile.toJson());
    final uid = _uid;
    if (uid != null) {
      try {
        await _db.collection('users').doc(uid).set({
          'meal_planner_profile': profile.toMap(),
          'updated_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('❌ MealPlanRepository.saveProfile: $e');
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Active plan
  // ---------------------------------------------------------------------------
  Future<MealPlan?> loadActivePlan() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_activePlanKey);
    if (raw != null) {
      try {
        return MealPlan.fromJson(raw);
      } catch (_) {}
    }
    // Fall back to the most recent Firestore plan.
    final col = _plansCol;
    if (col != null) {
      try {
        final snap =
            await col.orderBy('createdAt', descending: true).limit(1).get();
        if (snap.docs.isNotEmpty) {
          final plan = MealPlan.fromMap(snap.docs.first.id, snap.docs.first.data());
          await _cacheActivePlan(plan);
          return plan;
        }
      } catch (e) {
        debugPrint('❌ MealPlanRepository.loadActivePlan: $e');
      }
    }
    return null;
  }

  Future<void> savePlan(MealPlan plan, {bool setActive = true}) async {
    if (setActive) await _cacheActivePlan(plan);
    final col = _plansCol;
    if (col != null) {
      try {
        await col.doc(plan.id).set(plan.toMap());
      } catch (e) {
        debugPrint('❌ MealPlanRepository.savePlan: $e');
      }
    }
  }

  /// Persists an in-place update (meal swap, grocery toggle) to the active plan.
  Future<void> updatePlan(MealPlan plan) => savePlan(plan, setActive: true);

  Future<List<MealPlan>> loadSavedPlans({int limit = 20}) async {
    final col = _plansCol;
    if (col == null) return [];
    try {
      final snap =
          await col.orderBy('createdAt', descending: true).limit(limit).get();
      return snap.docs.map((d) => MealPlan.fromMap(d.id, d.data())).toList();
    } catch (e) {
      debugPrint('❌ MealPlanRepository.loadSavedPlans: $e');
      return [];
    }
  }

  /// Clears the locally-cached active plan (does not delete saved Firestore
  /// plans or favorites).
  Future<void> clearActivePlan() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_activePlanKey);
  }

  Future<void> _cacheActivePlan(MealPlan plan) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_activePlanKey, plan.toJson());
    } catch (e) {
      debugPrint('❌ MealPlanRepository cache write: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Favorite meals
  // ---------------------------------------------------------------------------
  Future<List<PlannedMeal>> loadFavoriteMeals() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_favMealsKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => PlannedMeal.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveFavoriteMeals(List<PlannedMeal> meals) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _favMealsKey, jsonEncode(meals.map((m) => m.toMap()).toList()));
    final uid = _uid;
    if (uid != null) {
      try {
        await _db.collection('users').doc(uid).set({
          'favorite_meals': meals.map((m) => m.toMap()).toList(),
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('❌ MealPlanRepository.saveFavoriteMeals: $e');
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Personalization (frequently chosen / skipped meal names)
  // ---------------------------------------------------------------------------
  Future<Map<String, int>> loadPreferenceCounts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return {};
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return m.map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (_) {
      return {};
    }
  }

  Future<void> savePreferenceCounts(Map<String, int> counts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(counts));
  }
}
