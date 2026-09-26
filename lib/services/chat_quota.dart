import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pro_access.dart';

/// Daily message allowance for the free tier's chat with the Wellness Pal.
///
/// Free users get [freeDailyMessages] messages a day; Premium is unlimited.
/// The count is per calendar day in the user's own timezone and resets at
/// midnight — not a rolling window, because "you get three a day" is something
/// a user can hold in their head, and a rolling window is not.
///
/// Stored locally rather than in Firestore. A determined user could reset it by
/// reinstalling, which is an acceptable trade: the quota exists to shape the
/// free experience toward upgrading, not to defend revenue against attackers,
/// and a local check costs nothing and works offline.
class ChatQuota {
  ChatQuota._();

  /// Messages a free user may send per day.
  static const int freeDailyMessages = 3;

  static const String _countKey = 'aiwellnesspal_chat_messages_today';
  static const String _dateKey = 'aiwellnesspal_chat_messages_date';

  /// Today as `YYYY-MM-DD` in local time — the key the count is scoped to.
  static String _todayKey() {
    final now = DateTime.now();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '${now.year}-$m-$d';
  }

  /// Messages already sent today. Returns 0 on a new day or any read failure.
  static Future<int> usedToday() async {
    if (ProAccess.isPro) return 0;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_dateKey) != _todayKey()) return 0;
      return prefs.getInt(_countKey) ?? 0;
    } catch (e) {
      debugPrint('⚠️ ChatQuota.usedToday failed: $e');
      return 0;
    }
  }

  /// Messages left today. Unlimited for Premium, reported as a large number so
  /// callers never have to special-case it.
  static Future<int> remainingToday() async {
    if (ProAccess.isPro) return 1 << 20;
    final used = await usedToday();
    final left = freeDailyMessages - used;
    return left < 0 ? 0 : left;
  }

  /// Whether another message may be sent right now.
  static Future<bool> canSend() async =>
      ProAccess.isPro || (await remainingToday()) > 0;

  /// Records one sent message. No-op for Premium.
  ///
  /// Call only after a message is actually accepted, so a blocked attempt or a
  /// failed send never costs the user part of their allowance.
  static Future<void> recordSend() async {
    if (ProAccess.isPro) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = _todayKey();
      final isToday = prefs.getString(_dateKey) == today;
      final next = (isToday ? (prefs.getInt(_countKey) ?? 0) : 0) + 1;
      await prefs.setString(_dateKey, today);
      await prefs.setInt(_countKey, next);
    } catch (e) {
      // Losing a count is better than blocking a legitimate message.
      debugPrint('⚠️ ChatQuota.recordSend failed: $e');
    }
  }
}
