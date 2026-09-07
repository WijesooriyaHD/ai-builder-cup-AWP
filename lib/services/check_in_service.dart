import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/check_in.dart';
import '../models/wellness_enums.dart';

/// Service responsible for loading and saving daily wellness check-ins.
///
/// Firestore path: `users/{uid}/check_ins/{checkInId}`
/// Local cache key: `wellness_todays_check_in`
class CheckInService {
  final FirebaseFirestore? _injectedDb;

  /// Creates a [CheckInService].
  ///
  /// If [firestore] is not provided, `FirebaseFirestore.instance` is used
  /// lazily on the first Firestore operation. This allows instantiation
  /// without an initialized Firebase app (useful for testing).
  CheckInService({FirebaseFirestore? firestore}) : _injectedDb = firestore;

  FirebaseFirestore get _db => _injectedDb ?? FirebaseFirestore.instance;

  static const String _todaysCheckInKey = 'wellness_todays_check_in';

  /// Loads a check-in for a specific date.
  ///
  /// Queries Firestore `users/{uid}/check_ins` where the date field
  /// matches the given [date] by comparing YYYY-MM-DD strings.
  /// Returns `null` if no check-in exists for that date.
  Future<CheckIn?> loadCheckInForDate(String userId, DateTime date) async {
    try {
      final dateString = _formatDate(date);

      final snapshot = await _db
          .collection('users')
          .doc(userId)
          .collection('check_ins')
          .where('date', isGreaterThanOrEqualTo: '${dateString}T00:00:00')
          .where('date', isLessThan: '${dateString}T23:59:60')
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) return null;

      return CheckIn.fromMap(snapshot.docs.first.data());
    } catch (e) {
      debugPrint('CheckInService.loadCheckInForDate error: $e');
      return null;
    }
  }

  /// Saves a check-in to Firestore and caches it locally in SharedPreferences.
  ///
  /// Writes to `users/{uid}/check_ins/{checkIn.id}` and stores the
  /// JSON-encoded check-in under the `wellness_todays_check_in` key.
  /// Also persists `latest_energy_score` and `latest_recovery_status` on the
  /// user's root document for cross-device availability.
  Future<void> saveCheckIn(String userId, CheckIn checkIn) async {
    try {
      // Write to Firestore check_ins subcollection
      await _db
          .collection('users')
          .doc(userId)
          .collection('check_ins')
          .doc(checkIn.id)
          .set(checkIn.toMap());

      // Persist latest energy score and recovery status on the user doc
      // so they can be retrieved even if SharedPreferences are cleared.
      await _db.collection('users').doc(userId).set({
        'latest_energy_score': checkIn.energyScore,
        'latest_recovery_status': checkIn.recoveryStatus?.name,
        'latest_check_in_date': checkIn.date.toIso8601String(),
      }, SetOptions(merge: true));

      // Cache locally in SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_todaysCheckInKey, jsonEncode(checkIn.toMap()));

      debugPrint('✅ CheckIn saved: ${checkIn.id}');
    } catch (e) {
      debugPrint('❌ CheckInService.saveCheckIn error: $e');
      rethrow;
    }
  }

  /// Loads the most recent check-ins for a user, ordered by date descending.
  ///
  /// Defaults to the last 14 check-ins (used for pre-fill logic).
  Future<List<CheckIn>> loadRecentCheckIns(String userId, {int count = 14}) async {
    try {
      final snapshot = await _db
          .collection('users')
          .doc(userId)
          .collection('check_ins')
          .orderBy('date', descending: true)
          .limit(count)
          .get();

      return snapshot.docs
          .map((doc) => CheckIn.fromMap(doc.data()))
          .toList();
    } catch (e) {
      debugPrint('CheckInService.loadRecentCheckIns error: $e');
      return [];
    }
  }

  /// Loads today's check-in from local cache (SharedPreferences).
  ///
  /// Returns `null` if no cached check-in exists or if the cached
  /// check-in is not from today.
  Future<CheckIn?> loadCachedCheckIn() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString(_todaysCheckInKey);
      if (data == null) return null;

      final checkIn = CheckIn.fromMap(jsonDecode(data));

      // Only return if it's from today
      final today = _formatDate(DateTime.now());
      final checkInDate = _formatDate(checkIn.date);
      if (checkInDate != today) return null;

      return checkIn;
    } catch (e) {
      debugPrint('CheckInService.loadCachedCheckIn error: $e');
      return null;
    }
  }

  /// Loads the latest energy score and recovery status from the user's
  /// Firestore root document. Used as a fallback when SharedPreferences
  /// are empty (e.g. after app reinstall).
  ///
  /// Returns a partial [CheckIn] with only energyScore and recoveryStatus,
  /// or `null` if no data is available.
  Future<CheckIn?> loadLatestFromUserDoc(String userId) async {
    try {
      final doc = await _db.collection('users').doc(userId).get();
      if (!doc.exists) return null;

      final data = doc.data();
      if (data == null) return null;

      final energyScore = data['latest_energy_score'] as int?;
      final recoveryStatusName = data['latest_recovery_status'] as String?;
      final checkInDateStr = data['latest_check_in_date'] as String?;

      if (energyScore == null && recoveryStatusName == null) return null;

      RecoveryStatus? recoveryStatus;
      if (recoveryStatusName != null) {
        recoveryStatus = RecoveryStatus.values.firstWhere(
          (e) => e.name == recoveryStatusName,
          orElse: () => RecoveryStatus.wellRested,
        );
      }

      DateTime checkInDate;
      if (checkInDateStr != null) {
        checkInDate = DateTime.parse(checkInDateStr);
      } else {
        checkInDate = DateTime.now();
      }

      return CheckIn(
        id: 'from_user_doc',
        date: checkInDate,
        energyScore: energyScore,
        recoveryStatus: recoveryStatus,
      );
    } catch (e) {
      debugPrint('CheckInService.loadLatestFromUserDoc error: $e');
      return null;
    }
  }

  /// Formats a DateTime as a YYYY-MM-DD string for date comparison.
  String _formatDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }
}
