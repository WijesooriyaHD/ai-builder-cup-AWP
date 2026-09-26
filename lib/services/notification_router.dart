import 'package:flutter/material.dart';

import '../main.dart' show globalNavigatorKey;
import '../screens/achievements_screen.dart';
import '../screens/check_in_screen.dart';
import 'app_navigation_service.dart';
import 'life_tool_registry.dart';
import 'notification_category.dart';

/// Turns a tapped notification into the right screen.
///
/// One central place so adding a notification category means adding a case
/// here, not hunting through the app. Every route is expressed in terms of
/// what already exists — [AppNavigationService] for the bottom tabs, and the
/// [kLifeTools] registry for the toolkit screens — so this file never becomes
/// a second, competing definition of where things live.
///
/// Payload shape (set in the OneSignal dashboard under "Additional Data"):
/// ```json
/// { "notification_type": "meal", "deep_link": "/meal-planner" }
/// ```
/// Either key alone is enough: `notification_type` is preferred, `deep_link`
/// is the fallback, and an unrecognised value simply opens the app normally
/// rather than throwing — a campaign must never be able to crash the app.
class NotificationRouter {
  NotificationRouter._();

  /// Routes from a raw OneSignal `additionalData` map.
  static void handlePayload(
    Map<String, dynamic>? data,
    AppNavigationService navigation,
  ) {
    if (data == null) return;

    final category = NotificationCategory.fromId(
          data['notification_type'] as String?,
        ) ??
        NotificationCategory.fromDeepLink(data['deep_link'] as String?);

    if (category == null) {
      debugPrint('ℹ️ NotificationRouter: no route for payload $data');
      return;
    }
    route(category, navigation);
  }

  /// A tap that arrived before the app could act on it.
  ///
  /// Set when OneSignal reports a click during startup — see [capturePayload].
  /// Drained by [drainPending] once the widget tree is up.
  static Map<String, dynamic>? _pendingPayload;

  /// Records a notification tap for routing later.
  ///
  /// Registered in `main()` immediately after OneSignal initializes, because a
  /// tap that cold-starts the app is dispatched long before the widget tree —
  /// and therefore any provider-dependent listener — exists. Storing it here
  /// means the tap survives until something can act on it.
  static void capturePayload(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) return;
    _pendingPayload = data;
    debugPrint('🔔 NotificationRouter: captured pending tap $data');
  }

  /// Routes any tap captured during startup. Safe to call more than once.
  static void drainPending(AppNavigationService navigation) {
    final pending = _pendingPayload;
    if (pending == null) return;
    _pendingPayload = null;
    debugPrint('🔔 NotificationRouter: routing pending tap');
    handlePayload(pending, navigation);
  }

  /// How long to keep waiting for a Navigator before giving up.
  ///
  /// A cold start from a notification has to get through Firebase auth and the
  /// first plan load before MainWrapper mounts, which is far longer than the
  /// single frame this used to wait — so the route was simply dropped and the
  /// user landed on whatever the app opens to normally.
  static const Duration _navigatorTimeout = Duration(seconds: 12);
  static const Duration _retryInterval = Duration(milliseconds: 250);

  /// Routes to [category]'s destination, waiting for the app to be ready.
  static void route(
    NotificationCategory category,
    AppNavigationService navigation,
  ) {
    final deadline = DateTime.now().add(_navigatorTimeout);

    void attempt() {
      final navigator = globalNavigatorKey.currentState;
      if (navigator != null && navigator.mounted) {
        _navigate(category, navigation, navigator);
        return;
      }
      if (DateTime.now().isAfter(deadline)) {
        debugPrint(
            '⚠️ NotificationRouter: no navigator after '
            '${_navigatorTimeout.inSeconds}s, giving up on ${category.id}');
        return;
      }
      Future<void>.delayed(_retryInterval, attempt);
    }

    // Still start on the next frame, so a tap arriving mid-build doesn't
    // navigate underneath it.
    WidgetsBinding.instance.addPostFrameCallback((_) => attempt());
  }

  static void _navigate(
    NotificationCategory category,
    AppNavigationService navigation,
    NavigatorState navigator,
  ) {
    switch (category) {
      // --- Bottom-tab destinations -------------------------------------
      case NotificationCategory.wellnessPlan:
        // Today's Plan lives on the Home tab.
        navigation.goToTab(AppTab.home);
        break;

      case NotificationCategory.habit:
        navigation.goToTab(AppTab.habitBuilder);
        break;

      // --- Pushed screens ----------------------------------------------
      case NotificationCategory.checkIn:
        // Land on Home first so backing out of the check-in is coherent.
        navigation.goToTab(AppTab.home);
        navigator.push(
          MaterialPageRoute<void>(builder: (_) => const CheckInScreen()),
        );
        break;

      case NotificationCategory.achievement:
        navigator.push(
          MaterialPageRoute<void>(builder: (_) => const AchievementsScreen()),
        );
        break;

      // --- Life Toolkit screens, resolved through the shared registry ---
      case NotificationCategory.meal:
        _openTool('meal_planner', navigator);
        break;
      case NotificationCategory.hydration:
        _openTool('hydration', navigator);
        break;
      case NotificationCategory.meditation:
        _openTool('meditation', navigator);
        break;
      case NotificationCategory.cycle:
        _openTool('period_tracker', navigator);
        break;
    }
  }

  /// Opens a Life Toolkit screen by its registry id, reusing the same builders
  /// the home-widget deep links use.
  static void _openTool(String toolId, NavigatorState navigator) {
    final tool = lifeToolById(toolId);
    if (tool == null) {
      debugPrint('⚠️ NotificationRouter: unknown tool "$toolId"');
      return;
    }
    navigator.push(MaterialPageRoute<void>(builder: tool.builder));
  }
}
