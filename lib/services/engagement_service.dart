import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'achievement_service.dart';
import 'notification_category.dart';
import 'notification_preferences_store.dart';
import 'notification_service.dart';
import 'onesignal_service.dart';

/// Events the app reports, which OneSignal Journeys and campaigns can act on.
///
/// The names are the contract with the OneSignal dashboard — changing one
/// silently breaks whatever Journey is listening for it, so they are fixed
/// strings here rather than derived from Dart identifiers.
enum EngagementEvent {
  appOpened('app_opened'),
  onboardingCompleted('onboarding_completed', unique: true),
  checkinCompleted('checkin_completed'),
  planGenerated('plan_generated'),
  planStarted('plan_started'),
  planCompleted('plan_completed'),
  achievementUnlocked('achievement_unlocked'),
  streakReached('streak_reached'),
  meditationCompleted('meditation_completed'),
  challengeCompleted('challenge_completed'),
  premiumUpgraded('premium_upgraded', unique: true);

  const EngagementEvent(this.name, {this.unique = false});

  /// The event name sent to OneSignal.
  final String name;

  /// Whether this should only ever count once per user (a first-time moment
  /// like finishing onboarding), rather than every time it happens.
  final bool unique;
}

/// The decision layer of the engagement system.
///
/// This is where "should we say something, and how?" is answered. It owns two
/// rules and nothing else:
///
///  1. **Never send what the user turned off.** Every send goes through
///     [NotificationPreferencesStore], so a disabled category is impossible to
///     deliver by mistake.
///  2. **Interrupt the right way.** A moment worth celebrating becomes an
///     In-App Message when the user is looking at the app, and a notification
///     when they are not — never both for the same event.
///
/// Delivery itself is deliberately kept elsewhere: [NotificationService] for
/// on-device notifications and [OneSignalService] for in-app messages and
/// Journey events. That separation is what lets remote push be added later
/// (a Cloud Function calling the OneSignal REST API) without touching any of
/// the eligibility logic here.
class EngagementService {
  EngagementService({
    required NotificationPreferencesStore preferences,
    OneSignalService? oneSignal,
    NotificationService? notifications,
  })  : _preferences = preferences,
        _oneSignal = oneSignal ?? OneSignalService(),
        _notifications = notifications ?? NotificationService();

  final NotificationPreferencesStore _preferences;
  final OneSignalService _oneSignal;
  final NotificationService _notifications;

  /// Trigger key the dashboard's In-App Messages listen on. A single key with
  /// different values keeps dashboard setup simple: one message can match
  /// `any value`, or a specific one can match `achievement_unlocked`.
  static const String inAppTriggerKey = 'wellness_moment';

  // ---------------------------------------------------------------------------
  // Is the user watching?
  // ---------------------------------------------------------------------------

  /// Whether the app is in the foreground right now.
  ///
  /// This is what decides in-app message vs notification. `resumed` is the
  /// only state where the user can actually see an in-app message; anything
  /// else (inactive, paused, detached, hidden) means a notification is the
  /// honest choice.
  bool get isUserActive =>
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  // ---------------------------------------------------------------------------
  // Events (Journeys)
  // ---------------------------------------------------------------------------

  /// Reports an event to OneSignal so Journeys and campaigns can react.
  ///
  /// Fire-and-forget and never throws: analytics must not be able to break a
  /// user flow.
  Future<void> trackEvent(EngagementEvent event) async {
    if (event.unique) {
      await _oneSignal.trackUniqueOutcome(event.name);
    } else {
      await _oneSignal.trackOutcome(event.name);
    }
  }

  /// Records a piece of user state as a OneSignal tag, for segment targeting
  /// (e.g. `current_streak`, `last_checkin_date`).
  void setUserProperty(String key, String value) =>
      _oneSignal.setTag(key, value);

  // ---------------------------------------------------------------------------
  // Celebrations
  // ---------------------------------------------------------------------------

  /// Celebrates a newly-unlocked achievement.
  ///
  /// In-app message when the user is looking, notification when they are not —
  /// one or the other, never both, which is the difference between feeling
  /// celebrated and feeling spammed.
  ///
  /// Returns true when the in-app path was taken, so the caller can skip its
  /// own full-screen celebration if it would otherwise double up.
  Future<bool> celebrateAchievement(Achievement achievement) async {
    // The event is always reported, even if the user has muted the category —
    // muting is about being interrupted, not about analytics.
    await trackEvent(EngagementEvent.achievementUnlocked);
    setUserProperty('last_achievement', achievement.id);

    if (!_preferences.isCategoryEnabled(NotificationCategory.achievement)) {
      return false;
    }

    if (isUserActive) {
      // Dashboard-authored In-App Message. The values give the dashboard
      // enough to personalize copy without an app release.
      await _oneSignal.addInAppTrigger(inAppTriggerKey, 'achievement_unlocked');
      setUserProperty('last_achievement_title', achievement.name);
      return true;
    }

    await _notifications.showEngagementNotification(
      categoryId: NotificationCategory.achievement.id,
      title: '${achievement.emoji} Achievement Unlocked',
      body: achievement.name,
    );
    return false;
  }

  /// Streak lengths worth saying something about.
  ///
  /// The union of the achievement ladder (1/7/30/50/100) and the shorter
  /// early-habit milestones (3/14) — the first fortnight is when a habit is
  /// most fragile, so it earns more encouragement than later on.
  static const List<int> streakMilestones = [1, 3, 7, 14, 30, 50, 100];

  static const String _lastCelebratedStreakKey =
      'aiwellnesspal_last_celebrated_streak';

  /// Call whenever the streak is recalculated.
  ///
  /// Always records the streak as a OneSignal property (so segments and
  /// Journeys can target it), but only celebrates on a milestone — and only
  /// once per milestone, so reopening the app on the same day doesn't
  /// re-congratulate the user.
  Future<void> handleStreakUpdate(int days) async {
    setUserProperty('current_streak', days.toString());
    if (!streakMilestones.contains(days)) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getInt(_lastCelebratedStreakKey) == days) return;
      await prefs.setInt(_lastCelebratedStreakKey, days);
    } catch (e) {
      // If we can't read the guard, prefer celebrating over staying silent.
      debugPrint('⚠️ Streak celebration guard unavailable: $e');
    }

    await celebrateStreak(days);
  }

  /// Celebrates a streak milestone.
  ///
  /// Same in-app/notification split as [celebrateAchievement]. Prefer
  /// [handleStreakUpdate], which adds the milestone and duplicate checks.
  Future<void> celebrateStreak(int days) async {
    await trackEvent(EngagementEvent.streakReached);
    setUserProperty('current_streak', days.toString());

    if (!_preferences.isCategoryEnabled(NotificationCategory.achievement)) {
      return;
    }

    if (isUserActive) {
      await _oneSignal.addInAppTrigger(inAppTriggerKey, 'streak_reached');
      setUserProperty('last_streak_milestone', days.toString());
      return;
    }

    await _notifications.showEngagementNotification(
      categoryId: NotificationCategory.achievement.id,
      title: '🔥 $days-Day Streak',
      body: "You've checked in $days days running. Keep growing.",
    );
  }

  // ---------------------------------------------------------------------------
  // Contextual reminders
  // ---------------------------------------------------------------------------

  /// Sends a reminder for [category], but only if the user allows it.
  ///
  /// [condition] carries the business rule — "today's check-in isn't done",
  /// "the plan hasn't been viewed". Evaluating it here rather than at the call
  /// site means every reminder in the app is gated the same way, and the
  /// preference check can never be forgotten.
  ///
  /// [when] schedules for later; omit it to deliver now.
  Future<bool> sendReminder({
    required NotificationCategory category,
    required String title,
    required String body,
    bool condition = true,
    DateTime? when,
  }) async {
    if (!condition) return false;
    if (!_preferences.isCategoryEnabled(category)) {
      debugPrint('ℹ️ Reminder "${category.id}" suppressed by preferences');
      return false;
    }

    if (when == null) {
      await _notifications.showEngagementNotification(
        categoryId: category.id,
        title: title,
        body: body,
      );
    } else {
      await _notifications.scheduleEngagementNotification(
        categoryId: category.id,
        title: title,
        body: body,
        when: when,
      );
    }
    return true;
  }

  /// Cancels a pending reminder — call when the user does the thing it was
  /// about, so it never arrives after the fact.
  Future<void> cancelReminder(NotificationCategory category) =>
      _notifications.cancelEngagementNotification(category.id);

  // ---------------------------------------------------------------------------
  // "Your plan is ready"
  //
  // The plan is generated seconds after a check-in, and most users are still
  // looking at the app when it lands — they need no telling. The ones worth
  // reminding are those who closed the app in that gap and never saw it.
  //
  // Rather than guessing that at generation time, this arms a short delayed
  // reminder and [markPlanViewed] disarms it. Whoever sees the plan never
  // hears about it; whoever doesn't, does.
  // ---------------------------------------------------------------------------

  /// How long after generation the reminder fires, if the plan is still
  /// unseen. Long enough that someone reading their plan right now is never
  /// interrupted; short enough to still be about today.
  static const Duration planReminderDelay = Duration(minutes: 10);

  /// Call when a plan has just been generated.
  ///
  /// Arms the unseen-plan reminder, and — if the user is still in the app —
  /// also sets an in-app trigger, so a dashboard message can surface the plan
  /// to someone who has navigated away from Home.
  Future<void> handlePlanGenerated() async {
    await trackEvent(EngagementEvent.planGenerated);

    if (isUserActive) {
      await _oneSignal.addInAppTrigger(inAppTriggerKey, 'plan_ready');
    }

    await sendReminder(
      category: NotificationCategory.wellnessPlan,
      title: 'Your plan is ready 🌿',
      body: 'Your personalized wellness plan is waiting for you.',
      when: DateTime.now().add(planReminderDelay),
    );
  }

  /// Call when the user actually sees their plan.
  ///
  /// Disarms the reminder above — this is what stops it announcing something
  /// already in front of them — and clears the in-app trigger so the message
  /// can fire again for tomorrow's plan.
  Future<void> markPlanViewed() async {
    await cancelReminder(NotificationCategory.wellnessPlan);
    await clearInAppMoment();
  }

  /// Shows an in-app moment without any notification fallback, for things only
  /// meaningful while the app is open (e.g. "Your plan is ready" when the user
  /// has navigated away from Home).
  Future<void> showInAppMoment(String value) async {
    if (!isUserActive) return;
    await _oneSignal.addInAppTrigger(inAppTriggerKey, value);
  }

  /// Clears the in-app trigger so the same moment can fire again later.
  Future<void> clearInAppMoment() =>
      _oneSignal.removeInAppTrigger(inAppTriggerKey);
}
