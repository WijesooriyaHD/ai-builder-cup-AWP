import 'dart:async';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

/// Thin wrapper over Firebase Remote Config for values we may want to change
/// without shipping a new build (e.g. the Gemini Live model id, which is a
/// fast-moving preview model that gets renamed/retired).
///
/// Fail-safe by design: initialization never throws to the caller, and every
/// getter falls back to a hardcoded default, so the app works fine offline or
/// if Remote Config is unavailable.
class RemoteConfigService {
  RemoteConfigService._();
  static final RemoteConfigService instance = RemoteConfigService._();

  /// Remote Config parameter keys.
  static const String keyLiveModelId = 'live_conversation_model_id';

  /// Built-in defaults used until (and unless) remote values are fetched.
  /// Keep in sync with the code-level fallbacks.
  static const Map<String, dynamic> _defaults = {
    keyLiveModelId: 'gemini-2.5-flash-native-audio-preview-12-2025',
  };

  FirebaseRemoteConfig? _rc;
  bool _initialized = false;

  /// Initializes Remote Config with defaults and kicks off a fetch.
  ///
  /// Call once during app startup (after Firebase.initializeApp). Safe to call
  /// more than once. Never throws — logs and no-ops on failure.
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final rc = FirebaseRemoteConfig.instance;
      await rc.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        // Values are static-ish; refresh at most hourly in production.
        minimumFetchInterval:
            kDebugMode ? Duration.zero : const Duration(hours: 1),
      ));
      await rc.setDefaults(_defaults);
      _rc = rc;
      _initialized = true;
      // Fetch in the background — don't block startup on the network.
      unawaited(_safeFetch(rc));
    } catch (e) {
      debugPrint('RemoteConfigService: initialize failed: $e');
    }
  }

  Future<void> _safeFetch(FirebaseRemoteConfig rc) async {
    try {
      await rc.fetchAndActivate();
    } catch (e) {
      debugPrint('RemoteConfigService: fetch failed (using defaults): $e');
    }
  }

  /// The Gemini Live model id to use for Conversation Mode. Returns the remote
  /// value when available and non-empty, otherwise [fallback].
  String liveModelId({
    String fallback = 'gemini-2.5-flash-native-audio-preview-12-2025',
  }) {
    try {
      final v = _rc?.getString(keyLiveModelId).trim();
      if (v != null && v.isNotEmpty) return v;
    } catch (_) {}
    return fallback;
  }
}
