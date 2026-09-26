import 'package:flutter/foundation.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

/// Centralized wrapper around the OneSignal SDK.
///
/// This is the SINGLE place that talks to OneSignal directly — initialization,
/// user identity (login/logout), tags, and notification listeners all go
/// through here so the rest of the app never imports the SDK. This keeps the
/// integration testable and makes future SDK updates a one-file change.
///
/// The App ID is passed in from [main] so no secret/key is hardcoded in the
/// widget tree; the App ID itself is a public client identifier (safe to ship).
class OneSignalService {
  OneSignalService._internal();
  static final OneSignalService _instance = OneSignalService._internal();
  factory OneSignalService() => _instance;

  bool _initialized = false;
  bool get isInitialized => _initialized;

  /// Initializes the SDK. Safe to call more than once (subsequent calls no-op).
  ///
  /// Deliberately does NOT request notification permission here — permission is
  /// requested from the push-subscription verification dialog's button, which
  /// is the app's single permission entry point.
  void initialize(String appId) {
    if (_initialized) return;
    // Verbose logs while integrating; quiet in release builds.
    OneSignal.Debug.setLogLevel(kDebugMode ? OSLogLevel.verbose : OSLogLevel.none);
    OneSignal.initialize(appId);
    _initialized = true;
  }

  /// Associates the current OneSignal user with a stable app-side identity
  /// (the Firebase UID), so backend/dashboard sends can target this user and
  /// their subscriptions stay merged across devices and reinstalls.
  void login(String externalId) {
    if (externalId.isEmpty) return;
    OneSignal.login(externalId);
  }

  /// Detaches the current external identity (call on sign-out).
  void logout() {
    OneSignal.logout();
  }

  /// Adds/updates a single user tag (used for segmentation, e.g. streak count,
  /// last check-in date, cycle phase, isPro).
  void setTag(String key, String value) {
    OneSignal.User.addTagWithKey(key, value);
  }

  /// Adds/updates multiple user tags at once.
  void setTags(Map<String, String> tags) {
    if (tags.isEmpty) return;
    OneSignal.User.addTags(tags);
  }

  /// Removes a previously-set tag.
  void removeTag(String key) {
    OneSignal.User.removeTag(key);
  }

  /// Requests notification permission. Only called from the verification
  /// dialog's "Got it" button or the push-notifications Settings row. Returns
  /// whether permission was granted.
  Future<bool> requestPermission() {
    return OneSignal.Notifications.requestPermission(true);
  }

  /// Whether push notifications are currently opted in on this device.
  bool get optedIn => OneSignal.User.pushSubscription.optedIn ?? false;

  /// Opts the user back into push notifications (re-subscribes them in
  /// OneSignal without re-showing the OS permission sheet).
  void optIn() => OneSignal.User.pushSubscription.optIn();

  /// Opts the user out of push notifications (keeps the subscription record
  /// in OneSignal but stops delivery until they opt back in).
  void optOut() => OneSignal.User.pushSubscription.optOut();

  /// Prompts for push permission if it hasn't been requested yet this install.
  /// Returns immediately (false) when permission has already been requested
  /// so we don't nag the user.  Meant to be called once, after the user has
  /// seen value (e.g. after sign-in).
  Future<bool> requestPermissionIfNeeded() async {
    // If already granted/denied, don't ask again.
    final current = await OneSignal.Notifications.permissionNative();
    if (current != OSNotificationPermission.notDetermined) return false;
    return OneSignal.Notifications.requestPermission(true);
  }

  /// The current push subscription id, or null. A real, server-assigned id is
  /// non-empty and NOT prefixed with `local-` (the SDK's pre-registration
  /// placeholder). See [isRegistered].
  String? get pushSubscriptionId => OneSignal.User.pushSubscription.id;

  /// Whether [id] is a real, server-assigned subscription id (device
  /// registered), rather than the `local-` placeholder minted before
  /// registration completes.
  static bool isRegistered(String? id) =>
      id != null && id.isNotEmpty && !id.startsWith('local-');

  /// Registers a push-subscription state observer. [onChange] receives the
  /// current subscription id whenever it changes.
  void addPushSubscriptionObserver(void Function(String? id) onChange) {
    OneSignal.User.pushSubscription.addObserver((state) {
      onChange(state.current.id);
    });
  }

  /// Registers a handler for notification taps (app opened from a push).
  void setNotificationClickListener(
      void Function(OSNotificationClickEvent) handler) {
    OneSignal.Notifications.addClickListener(handler);
  }

  /// Registers a handler for notifications arriving while the app is in the
  /// foreground (lets the app decide whether/how to display them).
  void setNotificationForegroundListener(
      void Function(OSNotificationWillDisplayEvent) handler) {
    OneSignal.Notifications.addForegroundWillDisplayListener(handler);
  }

  // ---------------------------------------------------------------------------
  // In-App Messages
  //
  // The MESSAGE ITSELF is authored in the OneSignal dashboard, not in code.
  // The app's job is only to set a trigger; the dashboard decides which
  // message (if any) that trigger shows. That split is the point — copy and
  // design can change without an app release.
  // ---------------------------------------------------------------------------

  /// Sets a trigger that may cause a dashboard-authored In-App Message to show.
  ///
  /// Nothing appears unless a message in the dashboard is configured to listen
  /// for this key/value, so calling it is always safe.
  Future<void> addInAppTrigger(String key, String value) async {
    try {
      await OneSignal.InAppMessages.addTrigger(key, value);
    } catch (e) {
      debugPrint('⚠️ OneSignal addInAppTrigger failed: $e');
    }
  }

  /// Clears a trigger, so its message can fire again next time.
  Future<void> removeInAppTrigger(String key) async {
    try {
      await OneSignal.InAppMessages.removeTrigger(key);
    } catch (e) {
      debugPrint('⚠️ OneSignal removeInAppTrigger failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Outcomes (Journey / campaign events)
  // ---------------------------------------------------------------------------

  /// Records a named event, which OneSignal Journeys and analytics can act on.
  ///
  /// Use for things that can happen repeatedly (`checkin_completed`).
  Future<void> trackOutcome(String name) async {
    try {
      await OneSignal.Session.addOutcome(name);
    } catch (e) {
      debugPrint('⚠️ OneSignal trackOutcome("$name") failed: $e');
    }
  }

  /// Records an event that should only ever count once per user, such as
  /// `onboarding_completed` or a first-time achievement.
  Future<void> trackUniqueOutcome(String name) async {
    try {
      await OneSignal.Session.addUniqueOutcome(name);
    } catch (e) {
      debugPrint('⚠️ OneSignal trackUniqueOutcome("$name") failed: $e');
    }
  }
}
