/// The single source of truth for notification categories and where each one
/// takes the user.
///
/// Everything about a category lives here — its wire id (used in OneSignal
/// payloads, Firestore preference fields, and OneSignal tags), the preference
/// that gates it, and its deep-link destination. Adding a new kind of
/// notification means adding one enum value here; the preferences screen, the
/// tag sync, the deep-link router and the developer test panel all pick it up
/// automatically.
///
/// Keeping the ids as plain strings (rather than relying on enum ordering)
/// matters because they are written into Firestore documents and OneSignal
/// payloads that outlive any given app build.
library;

/// A kind of notification the app can send.
enum NotificationCategory {
  /// "How are you feeling today?" — the daily check-in nudge.
  checkIn(
    id: 'check_in',
    label: 'Daily Check-in',
    description: 'A gentle nudge if you have not checked in today.',
    deepLink: '/check-in',
  ),

  /// "Your personalized wellness plan is ready."
  wellnessPlan(
    id: 'wellness_plan',
    label: "Today's Plan",
    description: 'When your personalized plan is ready to view.',
    deepLink: '/plan',
  ),

  /// Meal logging / meal planner reminders.
  meal(
    id: 'meal',
    label: 'Meal Planner',
    description: 'Reminders to log your meals.',
    deepLink: '/meal-planner',
  ),

  /// Hydration reminders.
  hydration(
    id: 'hydration',
    label: 'Hydration',
    description: 'Reminders to log your water intake.',
    deepLink: '/hydration',
  ),

  /// Habit + challenge reminders.
  habit(
    id: 'habit',
    label: 'Habits & Challenges',
    description: 'Nudges for habits and challenges you have joined.',
    deepLink: '/habits',
  ),

  /// Meditation / mindful minute reminders.
  meditation(
    id: 'meditation',
    label: 'Meditation',
    description: 'Invitations to take a mindful minute.',
    deepLink: '/meditation',
  ),

  /// Achievement unlocked + streak milestones. One preference covers both,
  /// because to a user they are the same kind of moment.
  achievement(
    id: 'achievement',
    label: 'Achievements & Streaks',
    description: 'Celebrations when you unlock a badge or hit a streak.',
    deepLink: '/achievements',
  ),

  /// Cycle-related reminders. Only offered once the user has actually logged
  /// period data — see [requiresCycleData].
  cycle(
    id: 'cycle',
    label: 'Cycle Reminders',
    description: 'Reminders based on the cycle data you have logged.',
    deepLink: '/period-tracker',
    requiresCycleData: true,
  );

  const NotificationCategory({
    required this.id,
    required this.label,
    required this.description,
    required this.deepLink,
    this.requiresCycleData = false,
  });

  /// Stable wire id. Used as the Firestore field name, the OneSignal tag
  /// suffix (`notify_<id>`), and the `notification_type` in push payloads.
  final String id;

  /// Human-readable name shown on the preferences screen.
  final String label;

  /// One-line explanation shown under [label].
  final String description;

  /// Where tapping this notification should land the user.
  final String deepLink;

  /// When true the category is hidden from the preferences screen until the
  /// user has logged relevant data — we don't show cycle reminders to someone
  /// who has never used the period tracker.
  final bool requiresCycleData;

  /// The OneSignal tag key for this category, e.g. `notify_check_in`.
  String get tagKey => 'notify_$id';

  /// Looks up a category by its wire [id], or null when unknown.
  ///
  /// Unknown ids are expected and must not crash: a campaign created in the
  /// OneSignal dashboard can reference a category that a older app build does
  /// not know about yet.
  static NotificationCategory? fromId(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final category in NotificationCategory.values) {
      if (category.id == id) return category;
    }
    return null;
  }

  /// Looks up a category by its [deepLink] path, or null when unknown.
  static NotificationCategory? fromDeepLink(String? link) {
    if (link == null || link.isEmpty) return null;
    // Tolerate a missing leading slash and any query string.
    final path = '/${link.split('?').first.replaceFirst(RegExp(r'^/+'), '')}';
    for (final category in NotificationCategory.values) {
      if (category.deepLink == path) return category;
    }
    return null;
  }
}
