import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/notification_preferences.dart';
import 'notification_category.dart';
import 'onesignal_service.dart';

/// Owns the user's notification preferences: loading, saving, and keeping
/// OneSignal's tags in step with them.
///
/// Storage is deliberately in two places:
///  - **Firestore** (`users/{uid}.notification_preferences`) is the source of
///    truth, so preferences follow the user across devices and are readable by
///    Cloud Functions deciding whether a reminder may be sent.
///  - **SharedPreferences** is a local mirror, so the app can answer
///    "may I send this?" instantly and correctly while offline or before the
///    Firestore read completes. Without it, a cold start could briefly believe
///    everything is enabled and fire a notification the user turned off.
///
/// Mirrors [ConversationStore]'s conventions: 8-second timeouts, and failures
/// that degrade to a debugPrint rather than throwing.
class NotificationPreferencesStore extends ChangeNotifier {
  NotificationPreferencesStore({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    OneSignalService? oneSignal,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _oneSignal = oneSignal ?? OneSignalService();

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final OneSignalService _oneSignal;

  static const Duration _timeout = Duration(seconds: 8);
  static const String _localKey = 'aiwellnesspal_notification_preferences';
  static const String _localMasterKey =
      'aiwellnesspal_notification_master_enabled';

  NotificationPreferences _preferences = NotificationPreferences.defaults();

  /// The current preferences. Safe to read immediately — defaults until
  /// [load] completes.
  NotificationPreferences get preferences => _preferences;

  String? get _uid => _auth.currentUser?.uid;

  DocumentReference<Map<String, dynamic>>? _doc() {
    final uid = _uid;
    if (uid == null || uid.isEmpty) return null;
    return _firestore.collection('users').doc(uid);
  }

  /// Loads preferences: the local mirror first (instant, offline-safe), then
  /// Firestore, which wins if it has anything stored.
  Future<void> load() async {
    await _loadLocal();

    final ref = _doc();
    if (ref == null) return;
    try {
      final snap = await ref.get().timeout(_timeout);
      final stored = snap.data()?['notification_preferences'];
      if (stored is Map) {
        _preferences =
            NotificationPreferences.fromMap(Map<String, dynamic>.from(stored));
        await _saveLocal();
        notifyListeners();
      } else {
        // Nothing stored yet — publish the defaults so Cloud Functions and
        // dashboard segments have something concrete to read.
        await save(_preferences);
      }
    } catch (e) {
      debugPrint('❌ NotificationPreferencesStore.load error: $e');
    }
    await _reconcileWithOneSignal();

    // Always re-assert the tags: they may be stale from another device.
    _syncTags();
  }

  /// Makes the stored master switch agree with whether this device can
  /// actually receive anything.
  ///
  /// These can legitimately diverge: the user may have opted out through an
  /// older build's toggle, or revoked notifications in iOS Settings, neither of
  /// which touches Firestore. OneSignal's opt-in state wins, because it
  /// reflects reality — if the device is opted out, the app must not go on
  /// scheduling local reminders as though the user still wanted them.
  ///
  /// Only ever turns the stored value OFF. Opting *in* stays a deliberate user
  /// action, never something inferred on launch.
  Future<void> _reconcileWithOneSignal() async {
    try {
      if (_preferences.masterEnabled && !_oneSignal.optedIn) {
        debugPrint(
            'ℹ️ Device is opted out of push — syncing master switch to off.');
        await setMasterEnabled(false);
      }
    } catch (e) {
      debugPrint('⚠️ Could not reconcile master switch: $e');
    }
  }

  Future<void> _loadLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final master = prefs.getBool(_localMasterKey);
      final raw = prefs.getStringList(_localKey);
      if (master == null && raw == null) return;

      // Stored as a flat "id=bool" list so no JSON parsing is needed.
      final categories = <String, bool>{};
      for (final entry in raw ?? const <String>[]) {
        final parts = entry.split('=');
        if (parts.length == 2) categories[parts[0]] = parts[1] == 'true';
      }
      _preferences = NotificationPreferences.fromMap({
        'master_enabled': master,
        'categories': categories,
      });
      notifyListeners();
    } catch (e) {
      debugPrint('⚠️ NotificationPreferencesStore local load failed: $e');
    }
  }

  Future<void> _saveLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_localMasterKey, _preferences.masterEnabled);
      await prefs.setStringList(
        _localKey,
        _preferences.categories.entries
            .map((e) => '${e.key}=${e.value}')
            .toList(),
      );
    } catch (e) {
      debugPrint('⚠️ NotificationPreferencesStore local save failed: $e');
    }
  }

  /// Persists [next] everywhere: memory, local mirror, Firestore, OneSignal.
  ///
  /// The in-memory and local writes happen first and unconditionally, so the
  /// user's choice takes effect immediately even if the network is down.
  Future<void> save(NotificationPreferences next) async {
    _preferences = next;
    notifyListeners();
    await _saveLocal();
    _syncTags();

    final ref = _doc();
    if (ref == null) return;
    try {
      await ref.set(
        {'notification_preferences': next.toMap()},
        SetOptions(merge: true),
      ).timeout(_timeout);
    } catch (e) {
      debugPrint('❌ NotificationPreferencesStore.save error: $e');
    }
  }

  /// Stores the master switch value.
  ///
  /// Storage only — prefer [enableMaster] / [disableMaster], which also move
  /// the OneSignal subscription so the stored value and actual deliverability
  /// can never drift apart.
  Future<void> setMasterEnabled(bool enabled) =>
      save(_preferences.copyWith(masterEnabled: enabled));

  /// Turns notifications on: OS permission, OneSignal opt-in, then storage.
  ///
  /// Returns false when the OS denied permission — nothing is stored in that
  /// case, because claiming notifications are on when the OS will not deliver
  /// them is worse than the switch appearing not to work.
  ///
  /// Every master-switch UI must go through this (or [disableMaster]) rather
  /// than calling opt-in and storage separately, so the two can't disagree.
  Future<bool> enableMaster() async {
    final granted = await _oneSignal.requestPermission();
    if (!granted) return false;
    _oneSignal.optIn();
    await setMasterEnabled(true);
    return true;
  }

  /// Turns notifications off: OneSignal opt-out AND storage.
  ///
  /// Both halves matter. Opting out alone stops dashboard campaigns but not
  /// the reminders the app schedules on-device; storing alone stops the app's
  /// reminders but not the campaigns. Only doing both makes the switch mean
  /// what the user thinks it means.
  Future<void> disableMaster() async {
    _oneSignal.optOut();
    await setMasterEnabled(false);
  }

  /// Flips one category.
  Future<void> setCategoryEnabled(
    NotificationCategory category,
    bool enabled,
  ) =>
      save(_preferences.withCategory(category, enabled));

  /// The single question the rest of the app should ask before sending
  /// anything — see [NotificationPreferences.isCategoryEnabled].
  bool isCategoryEnabled(NotificationCategory category) =>
      _preferences.isCategoryEnabled(category);

  /// Pushes the current preferences into OneSignal as tags, so dashboard
  /// segments and Journeys honour the same choices the app enforces locally.
  void _syncTags() {
    try {
      _oneSignal.setTags(_preferences.toOneSignalTags());
    } catch (e) {
      // Tag sync is best-effort; the local check is what actually gates sends.
      debugPrint('⚠️ OneSignal tag sync failed: $e');
    }
  }
}
