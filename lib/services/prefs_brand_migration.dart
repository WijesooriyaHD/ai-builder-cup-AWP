import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One-time migration of legacy `bloom_*` SharedPreferences keys to the
/// rebranded `aiwellnesspal_*` keys, so existing users keep their journals,
/// settings, streaks, intentions, etc. after the brand rename.
///
/// Any preferences key that starts with `bloom_` is copied to the same key
/// with the prefix swapped to `aiwellnesspal_` (value type preserved). The old
/// key is then removed. Runs at most once, guarded by [_doneFlag].
///
/// This is prefix-based so it also covers the date-scoped families
/// (`bloom_action_lesson_*`, `bloom_plan_reminder_*`) without listing them.
class PrefsBrandMigration {
  PrefsBrandMigration._();

  static const String _oldPrefix = 'bloom_';
  static const String _newPrefix = 'aiwellnesspal_';
  static const String _doneFlag = 'aiwellnesspal_brand_migration_v1_done';

  /// Runs the migration once. Safe to call on every launch — it no-ops after
  /// the first successful run.
  static Future<void> run() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_doneFlag) == true) return;

    try {
      // Snapshot keys first (we mutate prefs while iterating).
      final legacyKeys =
          prefs.getKeys().where((k) => k.startsWith(_oldPrefix)).toList();

      var migrated = 0;
      for (final oldKey in legacyKeys) {
        final newKey = '$_newPrefix${oldKey.substring(_oldPrefix.length)}';
        // Don't clobber a value already written under the new key.
        if (prefs.containsKey(newKey)) {
          await prefs.remove(oldKey);
          continue;
        }
        final value = prefs.get(oldKey);
        if (value == null) continue;

        if (value is bool) {
          await prefs.setBool(newKey, value);
        } else if (value is int) {
          await prefs.setInt(newKey, value);
        } else if (value is double) {
          await prefs.setDouble(newKey, value);
        } else if (value is String) {
          await prefs.setString(newKey, value);
        } else if (value is List<String>) {
          await prefs.setStringList(newKey, value);
        } else {
          continue; // unknown type — leave the old key intact
        }
        await prefs.remove(oldKey);
        migrated++;
      }

      await prefs.setBool(_doneFlag, true);
      if (kDebugMode) {
        debugPrint('PrefsBrandMigration: migrated $migrated legacy key(s).');
      }
    } catch (e) {
      // Don't set the done flag on failure so it retries next launch.
      debugPrint('❌ PrefsBrandMigration failed: $e');
    }
  }
}
