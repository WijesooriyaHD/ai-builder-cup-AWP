import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The wellness-tool summary cards a user can add to the Home screen.
///
/// These ids are stable and used as Home card ids (so the existing pin /
/// re-arrange / order-persistence machinery treats them exactly like the
/// default Home cards). Keep the string values stable across releases.
class HomeToolCard {
  const HomeToolCard._();

  static const String nutrition = 'tool_nutrition_progress';
  static const String mealPlanner = 'tool_meal_today';
  static const String calorieBudget = 'tool_calorie_ring';
  static const String periodTracker = 'tool_period_ring';
  static const String hydration = 'tool_hydration_ring';
  static const String bodyWeight = 'tool_body_weight';

  /// All addable tool-card ids.
  static const List<String> all = [
    nutrition,
    mealPlanner,
    calorieBudget,
    periodTracker,
    hydration,
    bodyWeight,
  ];

  /// Human-readable title for a tool card id (used in menus and the Home
  /// re-arrange tiles).
  static String titleFor(String id) {
    switch (id) {
      case nutrition:
        return "Today's Progress";
      case mealPlanner:
        return "Today's Meals";
      case calorieBudget:
        return 'Calorie Budget';
      case periodTracker:
        return 'Period Tracker';
      case hydration:
        return 'Hydration';
      case bodyWeight:
        return 'Body Weight';
      default:
        return 'Wellness Card';
    }
  }

  static bool isToolCard(String id) => all.contains(id);

  /// Representative icon for a tool card id (used in the Home section header so
  /// tool cards match the default Home cards' icon + title formatting).
  static IconData iconFor(String id) {
    switch (id) {
      case nutrition:
        return Icons.restaurant_rounded;
      case mealPlanner:
        return Icons.restaurant_menu_rounded;
      case calorieBudget:
        return Icons.local_fire_department_rounded;
      case periodTracker:
        return Icons.female_rounded;
      case hydration:
        return Icons.water_drop_rounded;
      case bodyWeight:
        return Icons.monitor_weight_rounded;
      default:
        return Icons.dashboard_customize_rounded;
    }
  }
}

/// Single source of truth for WHICH wellness-tool cards the user has added to
/// their Home screen. Shared by the tool screens (which add/remove) and the
/// Home screen (which renders them).
///
/// Persists the enabled set to SharedPreferences (instant, offline) and mirrors
/// it to the user's Firestore profile doc so it follows them across devices —
/// matching how the Home card ORDER is persisted.
class HomeToolCardsService extends ChangeNotifier {
  HomeToolCardsService({FirebaseFirestore? db, FirebaseAuth? auth})
      : _db = db ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  static const String _prefsKey = 'wellness_home_tool_cards';
  static const String _firestoreField = 'home_tool_cards';

  final Set<String> _enabled = {};
  bool _loaded = false;

  /// The tool-card ids currently on Home, in the order they were added.
  /// (Home ordering/pinning is layered on top by the Home screen.)
  List<String> get enabled => _enabled.toList();

  bool isEnabled(String id) => _enabled.contains(id);

  bool get isLoaded => _loaded;

  /// Loads the enabled set: local cache first (instant), then reconcile with
  /// the cloud copy so the set follows the user across devices.
  Future<void> load({Map<String, dynamic>? cloudProfile}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final local = prefs.getStringList(_prefsKey);
      if (local != null) {
        _enabled
          ..clear()
          ..addAll(local.where(HomeToolCard.isToolCard));
      }
    } catch (e) {
      debugPrint('HomeToolCardsService: local load failed: $e');
    }

    // Reconcile with the cloud copy if provided (or fetched).
    try {
      List<dynamic>? cloud;
      if (cloudProfile != null) {
        cloud = cloudProfile[_firestoreField] as List<dynamic>?;
      } else {
        final uid = _auth.currentUser?.uid;
        if (uid != null) {
          final doc = await _db.collection('users').doc(uid).get();
          cloud = doc.data()?[_firestoreField] as List<dynamic>?;
        }
      }
      if (cloud != null) {
        _enabled
          ..clear()
          ..addAll(cloud.map((e) => e.toString()).where(HomeToolCard.isToolCard));
        // Keep local cache in step with the cloud.
        unawaited(_writeLocal());
      }
    } catch (e) {
      debugPrint('HomeToolCardsService: cloud load failed: $e');
    }

    _loaded = true;
    notifyListeners();
  }

  /// Adds [id] to Home (idempotent) and persists.
  Future<void> add(String id) async {
    if (!HomeToolCard.isToolCard(id) || _enabled.contains(id)) return;
    _enabled.add(id);
    notifyListeners();
    await _persist();
  }

  /// Removes [id] from Home (idempotent) and persists.
  Future<void> remove(String id) async {
    if (!_enabled.remove(id)) return;
    notifyListeners();
    await _persist();
  }

  /// Toggles [id]'s presence on Home. Returns the new enabled state.
  Future<bool> toggle(String id) async {
    if (_enabled.contains(id)) {
      await remove(id);
      return false;
    }
    await add(id);
    return true;
  }

  Future<void> _persist() async {
    await _writeLocal();
    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      try {
        await _db.collection('users').doc(uid).set(
          {_firestoreField: _enabled.toList()},
          SetOptions(merge: true),
        );
      } catch (e) {
        debugPrint('HomeToolCardsService: Firestore mirror failed: $e');
      }
    }
  }

  Future<void> _writeLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefsKey, _enabled.toList());
    } catch (e) {
      debugPrint('HomeToolCardsService: local write failed: $e');
    }
  }
}
