import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/weather_config.dart';
import '../domain/weather_models.dart';

/// Persists the user's *current* weather location (single, current only) and
/// caches the latest [WeatherData] with a freshness timestamp.
///
/// Location is stored on the user doc under `weather_location`. It does NOT
/// touch the nationality field and keeps no history.
class WeatherRepository {
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  WeatherRepository({FirebaseFirestore? db, FirebaseAuth? auth})
      : _db = db ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  String? get _uid => _auth.currentUser?.uid;

  static const String _locationKey = 'weather_location';
  static const String _cacheKey = 'weather_cache';
  static const String _cacheAtKey = 'weather_cache_fetched_at';

  // ---------------------------------------------------------------------------
  // Location
  // ---------------------------------------------------------------------------
  Future<WeatherLocation?> loadLocation({Map<String, dynamic>? cloudProfile}) async {
    final prefs = await SharedPreferences.getInstance();
    if (cloudProfile != null && cloudProfile['weather_location'] is Map) {
      try {
        final loc = WeatherLocation.fromMap(
            Map<String, dynamic>.from(cloudProfile['weather_location'] as Map));
        await prefs.setString(_locationKey, loc.toJson());
        return loc;
      } catch (_) {}
    }
    final raw = prefs.getString(_locationKey);
    if (raw != null) {
      try {
        return WeatherLocation.fromJson(raw);
      } catch (_) {}
    }
    return null;
  }

  Future<void> saveLocation(WeatherLocation loc) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_locationKey, loc.toJson());
    // Changing location invalidates the weather cache.
    await clearWeatherCache();

    final uid = _uid;
    if (uid != null) {
      try {
        await _db.collection('users').doc(uid).set({
          'weather_location': loc.toMap(),
          'updated_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('❌ WeatherRepository.saveLocation: $e');
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Weather cache
  // ---------------------------------------------------------------------------

  /// Returns cached weather if present, regardless of freshness (caller decides
  /// how to use it). Use [isCacheFresh] to check validity.
  Future<WeatherData?> loadCachedWeather() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw == null) return null;
    try {
      return WeatherData.fromJson(raw);
    } catch (_) {
      return null;
    }
  }

  Future<DateTime?> cacheFetchedAt() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_cacheAtKey);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<bool> isCacheFresh() async {
    final at = await cacheFetchedAt();
    if (at == null) return false;
    return DateTime.now().difference(at) < OpenMeteoConfig.cacheDuration;
  }

  Future<void> saveWeatherCache(WeatherData data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKey, data.toJson());
    await prefs.setInt(_cacheAtKey, DateTime.now().millisecondsSinceEpoch);
  }

  Future<void> clearWeatherCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheKey);
    await prefs.remove(_cacheAtKey);
  }
}
