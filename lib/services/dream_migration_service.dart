import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/dream.dart';
import '../models/wellness_intention.dart';

/// Migrates existing Dream objects to WellnessIntention objects.
///
/// This service runs once per user on first launch after the pivot.
/// and Firestore (`users/{uid}/wellness_intentions`), converts any that
/// lack a `category` field using [WellnessIntention.fromDream], writes the
/// migrated records to Firestore, and sets a local flag to prevent re-running.
///
/// Preserves ALL existing Dream fields per Requirement 5.8.
class DreamMigrationService {
  static const String _migrationFlagKey = 'wellness_migration_v1_done';
  static const String _dreamsKey = 'aiwellnesspal_dreams';

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  DreamMigrationService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  /// Returns true if migration has already been completed for this device.
  Future<bool> isMigrationCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_migrationFlagKey) ?? false;
  }

  /// Runs the Dream → WellnessIntention migration.
  ///
  /// This method is idempotent: it checks the migration flag first and
  /// returns immediately if migration has already been completed.
  ///
  /// Steps:
  /// 1. Check if migration is already done (SharedPreferences flag).
  /// 3. Load existing intentions from Firestore to avoid duplicates.
  /// 4. For each Dream without a corresponding WellnessIntention, convert
  ///    using `WellnessIntention.fromDream()` and write to Firestore.
  /// 5. Mark migration as complete in SharedPreferences.
  Future<void> migrate() async {
    // Step 1: Check if already done
    final prefs = await SharedPreferences.getInstance();
    final alreadyDone = prefs.getBool(_migrationFlagKey) ?? false;
    if (alreadyDone) {
      debugPrint('DreamMigrationService: Migration already completed, skipping.');
      return;
    }

    final user = _auth.currentUser;
    if (user == null) {
      debugPrint('DreamMigrationService: No authenticated user, skipping migration.');
      return;
    }

    final uid = user.uid;
    debugPrint('DreamMigrationService: Starting migration for user $uid');

    try {
      // Step 2: Load dreams from local cache
      final localDreams = await _loadLocalDreams(prefs);

      // Step 3: Load existing wellness intentions from Firestore
      final existingIntentionIds = await _loadExistingIntentionIds(uid);

      // Step 4: Convert and write unmigrated dreams
      final dreamsToMigrate = localDreams
          .where((dream) => !existingIntentionIds.contains(dream.id))
          .toList();

      if (dreamsToMigrate.isNotEmpty) {
        await _writeMigratedIntentions(uid, dreamsToMigrate);
        debugPrint(
            'DreamMigrationService: Migrated ${dreamsToMigrate.length} dreams.');
      } else {
        debugPrint('DreamMigrationService: No dreams to migrate.');
      }

      // Step 5: Mark migration as complete
      await prefs.setBool(_migrationFlagKey, true);
      debugPrint('DreamMigrationService: Migration complete.');
    } catch (e) {
      debugPrint('DreamMigrationService: Migration failed: $e');
      // Don't mark as complete so it retries next time
    }
  }

  /// Loads dreams from the local SharedPreferences cache.
  Future<List<Dream>> _loadLocalDreams(SharedPreferences prefs) async {
    final data = prefs.getString(_dreamsKey);
    if (data == null || data.isEmpty) return [];

    try {
      final List<dynamic> jsonList = jsonDecode(data) as List<dynamic>;
      return jsonList
          .map((e) => Dream.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      debugPrint('DreamMigrationService: Error parsing local dreams: $e');
      return [];
    }
  }

  /// Loads the IDs of existing WellnessIntention documents from Firestore.
  Future<Set<String>> _loadExistingIntentionIds(String uid) async {
    try {
      final snapshot = await _db
          .collection('users')
          .doc(uid)
          .collection('wellness_intentions')
          .get();

      return snapshot.docs.map((doc) => doc.id).toSet();
    } catch (e) {
      debugPrint(
          'DreamMigrationService: Error loading existing intentions: $e');
      return {};
    }
  }

  /// Writes migrated WellnessIntention documents to Firestore in a batch.
  ///
  /// Each dream is converted using [WellnessIntention.fromDream] which
  /// sets category to 'general' and isActive to true, preserving all
  /// original Dream fields.
  Future<void> _writeMigratedIntentions(
      String uid, List<Dream> dreams) async {
    final batch = _db.batch();

    for (final dream in dreams) {
      final intention = WellnessIntention.fromDream(dream);
      final docRef = _db
          .collection('users')
          .doc(uid)
          .collection('wellness_intentions')
          .doc(intention.id);

      batch.set(docRef, intention.toMap(), SetOptions(merge: true));
    }

    await batch.commit();
  }
}
