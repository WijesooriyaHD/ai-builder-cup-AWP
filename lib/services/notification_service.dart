import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:permission_handler/permission_handler.dart';

/// Service responsible for scheduling and managing local push notifications.
///
/// Schedules a daily gentle check-in reminder at 18:00 local time if the user
/// hasn't completed a Check_In for that day. Cancels the pending notification
/// once the user completes a check-in.
///
/// Requirements: 3.9
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Notification ID used for the daily 6pm check-in reminder.
  /// Using a fixed ID so we can easily cancel and reschedule.
  static const int _dailyCheckInNotificationId = 1001;

  /// Notification channel for Android.
  static const String _channelId = 'wellness_check_in_reminder';
  static const String _channelName = 'Check-In Reminders';
  static const String _channelDescription =
      'Gentle daily reminder to complete your wellness check-in';

  bool _isInitialized = false;

  /// Whether the service has been initialized.
  bool get isInitialized => _isInitialized;

  /// Initializes the notification plugin and timezone data.
  ///
  /// Must be called once during app startup (e.g., in `main()`).
  Future<void> initialize() async {
    if (_isInitialized) return;

    // Initialize timezone database and point tz.local at the device's zone.
    // Without this, tz.local stays UTC and zonedSchedule would fire reminders
    // at the wrong wall-clock time (e.g. "8:00 AM" scheduled as 8:00 UTC).
    tz_data.initializeTimeZones();
    _configureLocalTimeZone();

    const androidSettings =
        AndroidInitializationSettings('@mipmap/launcher_icon');

    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      // Show notifications as banners even while the app is in the foreground
      // (otherwise iOS silently suppresses them when the app is open, which
      // makes them look "missing" during testing).
      defaultPresentAlert: true,
      defaultPresentSound: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    _isInitialized = true;
    debugPrint('✅ NotificationService initialized');
  }

  /// Sets [tz.local] to a timezone matching the device's current UTC offset.
  ///
  /// We avoid adding a native timezone plugin by finding a tz database location
  /// whose *current* offset matches the device offset. This gets the wall-clock
  /// scheduling right (which is what reminders need); it won't perfectly track a
  /// specific region's future DST transitions, but for a fixed daily/weekly
  /// reminder time that's an acceptable trade-off.
  void _configureLocalTimeZone() {
    try {
      final deviceOffset = DateTime.now().timeZoneOffset;

      // If UTC, keep the default.
      if (deviceOffset == Duration.zero) {
        tz.setLocalLocation(tz.getLocation('UTC'));
        return;
      }

      final now = DateTime.now().toUtc();
      for (final location in tz.timeZoneDatabase.locations.values) {
        final tzNow = tz.TZDateTime.from(now, location);
        if (tzNow.timeZoneOffset == deviceOffset) {
          tz.setLocalLocation(location);
          debugPrint('🕒 tz.local set to ${location.name} '
              '(offset $deviceOffset)');
          return;
        }
      }
      debugPrint('⚠️ No tz location matched device offset $deviceOffset; '
          'falling back to UTC');
    } catch (e) {
      debugPrint('⚠️ _configureLocalTimeZone failed: $e');
    }
  }

  /// Requests notification permission from the user.
  ///
  /// On Android 13+ (API 33+), POST_NOTIFICATIONS permission is required.
  /// On iOS, requests alert, badge, and sound permissions.
  /// Returns true if permission was granted.
  Future<bool> requestPermission() async {
    // Prefer the plugin's own platform APIs — these actually trigger the iOS
    // system prompt and the Android 13+ dialog. permission_handler's status can
    // lag behind a fresh grant on iOS, so we don't rely on it as the source of
    // truth here.
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final ios = _plugin.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
        final granted = await ios?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        return granted ?? false;
      }

      if (defaultTargetPlatform == TargetPlatform.android) {
        final android = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        // Android 13+ runtime permission. Returns null on older versions where
        // notifications are granted by default.
        final granted = await android?.requestNotificationsPermission();
        if (granted != null) return granted;
        // Fallback for older Android / edge cases.
        final status = await Permission.notification.request();
        return status.isGranted;
      }
    } catch (e) {
      debugPrint('⚠️ requestPermission via plugin failed: $e');
    }

    // Fallback for any other platform.
    final status = await Permission.notification.request();
    return status.isGranted;
  }

  /// Whether notifications are currently authorized, checked via the plugin's
  /// platform APIs (more reliable on iOS than permission_handler).
  Future<bool> hasNotificationPermission() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final ios = _plugin.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
        final settings = await ios?.checkPermissions();
        return settings?.isEnabled ?? false;
      }
      if (defaultTargetPlatform == TargetPlatform.android) {
        final android = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        final enabled = await android?.areNotificationsEnabled();
        return enabled ?? true;
      }
    } catch (e) {
      debugPrint('⚠️ hasNotificationPermission failed: $e');
    }
    return Permission.notification.isGranted;
  }

  /// Schedules a daily check-in reminder at 18:00 local time.
  ///
  /// If the current time is already past 18:00 today, the notification
  /// is scheduled for 18:00 tomorrow. Uses [AndroidScheduleMode.inexactAllowWhileIdle]
  /// for battery-friendly scheduling.
  ///
  /// Call this method:
  /// - On app launch (if no check-in exists for today)
  /// - After midnight (new day begins)
  Future<void> scheduleDailyCheckInReminder() async {
    if (!_isInitialized) {
      debugPrint('⚠️ NotificationService not initialized');
      return;
    }

    // Check if permission is granted
    final hasPermission = await Permission.notification.isGranted;
    if (!hasPermission) {
      debugPrint('⚠️ Notification permission not granted, skipping schedule');
      return;
    }

    final scheduledTime = _nextSixPm();

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      styleInformation: BigTextStyleInformation(''),
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false,
      presentSound: true,
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // Cancel any existing scheduled notification before rescheduling
    await _plugin.cancel(_dailyCheckInNotificationId);

    await _plugin.zonedSchedule(
      _dailyCheckInNotificationId,
      'Time for a wellness check-in 🌿',
      'Take a moment to notice how you\'re feeling today.',
      scheduledTime,
      notificationDetails,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: null, // One-shot, we reschedule manually
    );

    debugPrint(
        '🔔 Check-in reminder scheduled for: ${scheduledTime.toString()}');
  }

  /// Cancels the pending daily check-in reminder.
  ///
  /// Call this when the user completes a Check_In for today.
  Future<void> cancelDailyCheckInReminder() async {
    if (!_isInitialized) return;

    await _plugin.cancel(_dailyCheckInNotificationId);
    debugPrint('🔕 Check-in reminder cancelled');
  }

  /// Computes the next occurrence of 18:00 in the user's local timezone.
  ///
  /// If it's currently before 18:00 today, returns today at 18:00.
  /// If it's 18:00 or later, returns tomorrow at 18:00.
  tz.TZDateTime _nextSixPm() {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      18, // 6:00 PM
      0,
      0,
    );

    // If 6pm has already passed today, schedule for tomorrow
    if (scheduled.isBefore(now) || scheduled.isAtSameMomentAs(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    return scheduled;
  }

  /// Handles notification tap — currently a no-op since the app opens
  /// naturally and the user will be prompted for check-in if needed.
  void _onNotificationTapped(NotificationResponse response) {
    debugPrint('Notification tapped: ${response.payload}');
    // The app will naturally prompt for check-in when opened
  }

  // ---------------------------------------------------------------------------
  // Meditation & Mindfulness reminders
  //
  // Weekly repeating reminders. flutter_local_notifications schedules a weekly
  // repeat per (reminder × weekday), so each active weekday gets its own stable
  // notification id derived from the reminder. Rescheduling is idempotent:
  // callers cancel then reschedule.
  // ---------------------------------------------------------------------------

  static const String _meditationChannelId = 'meditation_reminders';
  static const String _meditationChannelName = 'Mindfulness Reminders';
  static const String _meditationChannelDescription =
      'Gentle reminders to take a mindful moment';

  /// Base offset for meditation notification ids to avoid colliding with the
  /// check-in reminder (id 1001) or other features.
  static const int _meditationIdBase = 20000;

  /// Deterministic notification id for a reminder on a given weekday (1–7).
  int _meditationNotificationId(String reminderId, int weekday) {
    // Stable hash of the reminder id, kept small and combined with the weekday.
    final h = reminderId.hashCode & 0x7fffffff;
    return _meditationIdBase + (h % 1000) * 10 + weekday;
  }

  static const NotificationDetails _meditationDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      _meditationChannelId,
      _meditationChannelName,
      channelDescription: _meditationChannelDescription,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      styleInformation: BigTextStyleInformation(''),
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false,
      presentSound: true,
    ),
  );

  /// Schedules (or reschedules) all weekly occurrences for a single reminder.
  ///
  /// [reminderId] is the stable id, [label] the notification title suffix,
  /// [hour]/[minute] the local time, and [weekdays] the ISO weekdays (1=Mon …
  /// 7=Sun). Cancels any existing occurrences first so this is safe to call on
  /// every save. If [enabled] is false or [weekdays] is empty, it only cancels.
  Future<void> scheduleMeditationReminder({
    required String reminderId,
    required String label,
    required int hour,
    required int minute,
    required List<int> weekdays,
    required bool enabled,
    bool? assumeAuthorized,
  }) async {
    if (!_isInitialized) {
      debugPrint('⚠️ NotificationService not initialized');
      return;
    }

    // Always clear existing occurrences for this reminder (all 7 weekdays).
    await cancelMeditationReminder(reminderId);

    if (!enabled || weekdays.isEmpty) return;

    // Trust an explicit grant from the caller (e.g. right after requesting
    // permission), otherwise check via the plugin's platform APIs.
    final hasPermission =
        assumeAuthorized ?? await hasNotificationPermission();
    if (!hasPermission) {
      debugPrint('⚠️ Notification permission not granted, skipping schedule');
      return;
    }

    for (final weekday in weekdays) {
      final scheduled = _nextWeekdayTime(weekday, hour, minute);
      await _plugin.zonedSchedule(
        _meditationNotificationId(reminderId, weekday),
        '$label 🧘',
        'Take a mindful moment for yourself.',
        scheduled,
        _meditationDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        // Repeat weekly at the same weekday + time.
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    }

    debugPrint('🔔 Meditation reminder "$label" scheduled for weekdays '
        '$weekdays at $hour:${minute.toString().padLeft(2, '0')}');
  }

  /// Fires a one-off test notification a few seconds from now so the full
  /// permission → schedule → delivery pipeline can be verified without waiting
  /// for a real weekly reminder time. Returns false if permission is missing.
  Future<bool> sendTestMeditationNotification(
      {Duration delay = const Duration(seconds: 5)}) async {
    if (!_isInitialized) {
      debugPrint('⚠️ NotificationService not initialized');
      return false;
    }
    final granted = await hasNotificationPermission();
    if (!granted) {
      debugPrint('⚠️ Test notification skipped — permission not granted');
      return false;
    }
    final when = tz.TZDateTime.now(tz.local).add(delay);
    await _plugin.zonedSchedule(
      _meditationIdBase - 1, // dedicated id for the test notification
      'Mindfulness reminder 🧘',
      'This is a test. Reminders are working.',
      when,
      _meditationDetails,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
    debugPrint('🔔 Test notification scheduled for $when');
    return true;
  }

  /// Cancels every weekday occurrence for a reminder id.
  Future<void> cancelMeditationReminder(String reminderId) async {
    if (!_isInitialized) return;
    for (var weekday = 1; weekday <= 7; weekday++) {
      await _plugin.cancel(_meditationNotificationId(reminderId, weekday));
    }
  }

  // ---------------------------------------------------------------------------
  // Habit reminders
  // ---------------------------------------------------------------------------

  /// Base offset for habit notification ids (kept away from check-in/meditation).
  static const int _habitIdBase = 40000;

  int _habitNotificationId(String habitId, int weekday) {
    final h = habitId.hashCode & 0x7fffffff;
    return _habitIdBase + (h % 1000) * 10 + weekday;
  }

  /// Schedules a daily habit reminder at [hour]:[minute] on the given ISO
  /// [weekdays] (1=Mon … 7=Sun). Cancels existing occurrences first, so it's
  /// safe to call on every save. If [weekdays] is empty it only cancels.
  ///
  /// When [skipToday] is true, today's reminder is suppressed (e.g. because the
  /// habit is already completed): today's weekday occurrence is scheduled to
  /// begin next week instead of firing again today. The weekly repeat then
  /// resumes normally. Other weekdays are unaffected.
  Future<void> scheduleHabitReminder({
    required String habitId,
    required String label,
    required int hour,
    required int minute,
    required List<int> weekdays,
    bool skipToday = false,
    bool? assumeAuthorized,
  }) async {
    if (!_isInitialized) {
      debugPrint('⚠️ NotificationService not initialized');
      return;
    }

    await cancelHabitReminder(habitId);

    if (weekdays.isEmpty) return;

    final hasPermission =
        assumeAuthorized ?? await hasNotificationPermission();
    if (!hasPermission) {
      debugPrint('⚠️ Notification permission not granted, skipping habit schedule');
      return;
    }

    final now = tz.TZDateTime.now(tz.local);

    for (final weekday in weekdays) {
      var scheduled = _nextWeekdayTime(weekday, hour, minute);

      // Suppress today's reminder when requested: if the first occurrence lands
      // today (same date), push it a week out so nothing fires again today.
      // The weekly repeat still resumes on schedule afterward.
      if (skipToday &&
          scheduled.year == now.year &&
          scheduled.month == now.month &&
          scheduled.day == now.day) {
        scheduled = scheduled.add(const Duration(days: 7));
      }

      await _plugin.zonedSchedule(
        _habitNotificationId(habitId, weekday),
        '$label ⏰',
        'Time for your habit. Keep the streak going!',
        scheduled,
        _meditationDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    }

    debugPrint('🔔 Habit reminder "$label" scheduled for weekdays '
        '$weekdays at $hour:${minute.toString().padLeft(2, '0')}'
        '${skipToday ? " (today skipped)" : ""}');
  }

  /// Cancels every weekday occurrence for a habit reminder.
  Future<void> cancelHabitReminder(String habitId) async {
    if (!_isInitialized) return;
    for (var weekday = 1; weekday <= 7; weekday++) {
      await _plugin.cancel(_habitNotificationId(habitId, weekday));
    }
  }

  // ---------------------------------------------------------------------------
  // Today's Plan reminder (one-time, non-repeating)
  //
  // A single, one-shot reminder to do today's wellness plan. Unlike habit /
  // meditation reminders this does NOT repeat — it fires once at the chosen
  // time today and is gone. Uses a single fixed id so setting a new time just
  // replaces the previous one.
  // ---------------------------------------------------------------------------

  /// Fixed notification id for the one-time Today's Plan reminder.
  static const int _planReminderNotificationId = 50000;

  /// Schedules a one-time (non-repeating) reminder for today's plan at
  /// [hour]:[minute] local time. If that time has already passed today, the
  /// caller should decide how to handle it; here we simply schedule for the
  /// next occurrence of that wall-clock time today only when it's still ahead.
  ///
  /// Returns the resolved [tz.TZDateTime] it was scheduled for, or null if the
  /// time is in the past today or permission is missing.
  Future<tz.TZDateTime?> schedulePlanReminderOnce({
    required int hour,
    required int minute,
    String? focusLabel,
    bool? assumeAuthorized,
  }) async {
    if (!_isInitialized) {
      debugPrint('⚠️ NotificationService not initialized');
      return null;
    }

    // Replace any existing plan reminder.
    await cancelPlanReminder();

    final hasPermission =
        assumeAuthorized ?? await hasNotificationPermission();
    if (!hasPermission) {
      debugPrint('⚠️ Notification permission not granted, skipping plan reminder');
      return null;
    }

    final now = tz.TZDateTime.now(tz.local);
    final scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    // One-time within the same day: don't schedule a time already in the past.
    if (!scheduled.isAfter(now)) {
      debugPrint('⚠️ Plan reminder time already passed today; not scheduling');
      return null;
    }

    final body = (focusLabel != null && focusLabel.trim().isNotEmpty)
        ? 'Time for your plan: ${focusLabel.trim()} 🌿'
        : 'Take a moment for today\'s wellness plan. 🌿';

    await _plugin.zonedSchedule(
      _planReminderNotificationId,
      'Today\'s Plan reminder ⏰',
      body,
      scheduled,
      _meditationDetails,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: null, // One-shot — never repeats.
    );

    debugPrint('🔔 One-time plan reminder scheduled for $scheduled');
    return scheduled;
  }

  /// Cancels the one-time Today's Plan reminder if scheduled.
  Future<void> cancelPlanReminder() async {
    if (!_isInitialized) return;
    await _plugin.cancel(_planReminderNotificationId);
  }

  /// Computes the next occurrence of [weekday] (1=Mon … 7=Sun) at [hour]:[minute]
  /// in the user's local timezone.
  tz.TZDateTime _nextWeekdayTime(int weekday, int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    // Advance to the requested weekday.
    while (scheduled.weekday != weekday || !scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}
