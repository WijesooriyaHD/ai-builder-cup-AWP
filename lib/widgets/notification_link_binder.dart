import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../providers/check_in_state.dart';
import '../providers/wellness_plan_state.dart';
import '../features/meditation/presentation/meditation_state.dart';
import '../features/habit_builder/presentation/challenge_state.dart';
import '../services/achievement_service.dart';
import '../services/app_navigation_service.dart';
import '../services/engagement_service.dart';
import '../services/notification_category.dart';
import '../services/notification_router.dart';
import '../services/notification_service.dart';
import '../services/onesignal_service.dart';
import '../services/pro_access.dart';

/// Connects incoming notifications to in-app navigation, once.
///
/// Two sources feed the same router:
///  - **OneSignal** pushes (dashboard campaigns, Journeys, re-engagement),
///    whose destination rides in the payload's additional data.
///  - **Local** engagement notifications scheduled on-device, whose payload is
///    simply the [NotificationCategory] id.
///
/// A widget rather than a call in `main()` because the listeners need the
/// providers, which only exist inside the widget tree. It renders nothing of
/// its own — it wraps [child] purely to have a place in the tree.
///
/// Listeners are registered exactly once in [initState]; OneSignal's listener
/// registration is additive, so binding on every rebuild would route a single
/// tap many times.
class NotificationLinkBinder extends StatefulWidget {
  const NotificationLinkBinder({super.key, required this.child});

  final Widget child;

  @override
  State<NotificationLinkBinder> createState() => _NotificationLinkBinderState();
}

class _NotificationLinkBinderState extends State<NotificationLinkBinder> {
  bool _bound = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bound) return;
    _bound = true;

    final navigation = context.read<AppNavigationService>();
    final engagement = context.read<EngagementService>();

    // 1. Taps on a OneSignal push.
    //
    // main() registers its own listener first, so a tap that cold-started the
    // app is already captured. This one handles taps while the app is running,
    // and drainPending below plays back anything captured during startup.
    OneSignalService().setNotificationClickListener((event) {
      final data = event.notification.additionalData;
      debugPrint('🔔 OneSignal notification tapped: $data');
      NotificationRouter.handlePayload(data, navigation);
    });

    // Play back a tap that arrived before the app could navigate.
    NotificationRouter.drainPending(navigation);

    // 2. Taps on a local engagement notification.
    NotificationService().onEngagementTap = (categoryId) {
      final category = NotificationCategory.fromId(categoryId);
      if (category == null) return;
      NotificationRouter.route(category, navigation);
    };

    // 3. Achievement unlocks → celebration (in-app if the user is looking,
    //    notification if not). Hooked once, centrally.
    context.read<AchievementService>().onAchievementUnlocked =
        (achievement) => engagement.celebrateAchievement(achievement);

    // 4. Streak recalculation → milestone celebration (the engagement service
    //    decides whether this particular number is worth a word).
    final appState = context.read<AppState>();
    appState.onStreakUpdated =
        (streak) => engagement.handleStreakUpdate(streak);

    // 5. Check-in completed → Journey event.
    context.read<CheckInState>().onCheckInCompleted =
        () => engagement.trackEvent(EngagementEvent.checkinCompleted);

    // 6. Plan lifecycle → the three plan events.
    final planState = context.read<WellnessPlanState>();
    // Not a bare event: this also arms the "you never saw your plan" reminder
    // and, if the user is still in the app, the in-app moment.
    planState.onPlanGenerated = () => engagement.handlePlanGenerated();
    planState.onPlanStarted =
        () => engagement.trackEvent(EngagementEvent.planStarted);
    planState.onPlanCompleted =
        () => engagement.trackEvent(EngagementEvent.planCompleted);

    // 7. Meditation and challenge completions.
    context.read<MeditationState>().onSessionCompleted =
        () => engagement.trackEvent(EngagementEvent.meditationCompleted);
    context.read<ChallengeState>().onChallengeCompleted =
        () => engagement.trackEvent(EngagementEvent.challengeCompleted);

    // 8. Premium. The upgrade event fires only on a real purchase; the tier is
    //    reported separately every time so segments stay accurate.
    appState.onPremiumUpgraded =
        () => engagement.trackEvent(EngagementEvent.premiumUpgraded);
    appState.onProStatusKnown = (isPro) {
      engagement.setUserProperty('is_pro', isPro.toString());
      // Mirror it somewhere the toolkit states can read without a context —
      // their AI runs on load, before any widget could gate it.
      ProAccess.update(isPro);
    };

    // 9. Session start, so OneSignal Journeys have an entry point.
    engagement.trackEvent(EngagementEvent.appOpened);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
