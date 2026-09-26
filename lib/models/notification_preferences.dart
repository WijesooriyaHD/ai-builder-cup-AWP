import '../services/notification_category.dart';

/// What the user has agreed to be notified about.
///
/// Two levels, deliberately:
///  - [masterEnabled] is the single "Push Notifications" switch. Off means the
///    app sends nothing at all, whatever the individual switches say.
///  - [categories] holds one switch per [NotificationCategory].
///
/// [isCategoryEnabled] is the ONLY thing callers should ask — it applies both
/// levels, so no caller can accidentally check one and forget the other.
///
/// Persisted at `users/{uid}.notification_preferences` and mirrored into
/// OneSignal tags (see [toOneSignalTags]) so dashboard campaigns and Journeys
/// can respect the same choices without the app being open.
class NotificationPreferences {
  /// The master switch. When false nothing is sent, regardless of [categories].
  final bool masterEnabled;

  /// Per-category switches, keyed by [NotificationCategory.id].
  final Map<String, bool> categories;

  const NotificationPreferences({
    required this.masterEnabled,
    required this.categories,
  });

  /// Sensible defaults for a brand-new user: reminders on, but nothing that
  /// depends on data they have not entered yet (cycle) and nothing
  /// high-frequency enough to feel spammy on day one (hydration, meals).
  factory NotificationPreferences.defaults() {
    return NotificationPreferences(
      masterEnabled: true,
      categories: {
        for (final category in NotificationCategory.values)
          category.id: switch (category) {
            // Opt-in rather than opt-out: these fire often, so let the user
            // reach for them instead of having to turn them off.
            NotificationCategory.hydration => false,
            NotificationCategory.meal => false,
            // Never on until the user has logged cycle data.
            NotificationCategory.cycle => false,
            _ => true,
          },
      },
    );
  }

  /// The one question callers should ask before sending anything.
  bool isCategoryEnabled(NotificationCategory category) {
    if (!masterEnabled) return false;
    return categories[category.id] ?? false;
  }

  NotificationPreferences copyWith({
    bool? masterEnabled,
    Map<String, bool>? categories,
  }) {
    return NotificationPreferences(
      masterEnabled: masterEnabled ?? this.masterEnabled,
      categories: categories ?? Map<String, bool>.from(this.categories),
    );
  }

  /// Returns a copy with one category switched.
  NotificationPreferences withCategory(
    NotificationCategory category,
    bool enabled,
  ) {
    final next = Map<String, bool>.from(categories);
    next[category.id] = enabled;
    return copyWith(categories: next);
  }

  Map<String, dynamic> toMap() => {
        'master_enabled': masterEnabled,
        'categories': categories,
      };

  /// Rebuilds from Firestore, filling in any category added by a newer app
  /// build with its default rather than treating it as "off".
  factory NotificationPreferences.fromMap(Map<String, dynamic>? map) {
    if (map == null) return NotificationPreferences.defaults();

    final defaults = NotificationPreferences.defaults();
    final stored = (map['categories'] as Map?)?.cast<String, dynamic>() ?? {};

    return NotificationPreferences(
      masterEnabled: map['master_enabled'] as bool? ?? defaults.masterEnabled,
      categories: {
        for (final category in NotificationCategory.values)
          category.id: stored[category.id] as bool? ??
              defaults.categories[category.id] ??
              false,
      },
    );
  }

  /// The tag set mirrored into OneSignal, so dashboard segments can filter on
  /// exactly what the app enforces locally.
  ///
  /// Values are `'true'`/`'false'` strings because OneSignal tags are strings.
  /// Category tags reflect the EFFECTIVE value (master applied), so a segment
  /// only has to test one tag rather than two.
  Map<String, String> toOneSignalTags() {
    return {
      'notifications_enabled': masterEnabled.toString(),
      for (final category in NotificationCategory.values)
        category.tagKey: isCategoryEnabled(category).toString(),
    };
  }
}
