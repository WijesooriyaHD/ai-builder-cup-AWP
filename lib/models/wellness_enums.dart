/// Categories of wellness that intentions and actions can be tagged with.
enum WellnessCategory {
  flexibility,
  stress,
  sleep,
  movement,
  recovery,
  energy,
  mentalClarity,
  mindfulness,
  general,
}

/// Intensity level for a wellness action.
enum IntensityLevel {
  low,
  medium,
  high,
}

/// Mood state options presented during the daily check-in.
enum MoodState {
  calm,
  anxious,
  tired,
  energized,
  stressed,
  content,
}

/// Physical recovery status options presented during the daily check-in.
enum RecoveryStatus {
  wellRested,
  sore,
  fatigued,
  recovering,
}

/// Available time ranges the user can select during check-in.
///
/// Each value maps to a time window. The [upperBound] getter returns
/// the maximum minutes for that range (used for plan time constraints).
enum AvailableTimeRange {
  under10,
  range10_20,
  range20_40,
  range40_60,
  over60;

  /// Returns the upper bound in minutes for this time range.
  ///
  /// Used by the plan generation and fallback selection logic to ensure
  /// the total plan time does not exceed the user's available window.
  int get upperBound {
    switch (this) {
      case AvailableTimeRange.under10:
        return 10;
      case AvailableTimeRange.range10_20:
        return 20;
      case AvailableTimeRange.range20_40:
        return 40;
      case AvailableTimeRange.range40_60:
        return 60;
      case AvailableTimeRange.over60:
        return 120;
    }
  }
}

/// Personalization tier based on check-in history and subscription status.
///
/// - [standard]: 1–13 check-ins — full manual check-in each session.
/// - [prefill]: 14–27 check-ins + Premium — pre-filled check-in values.
/// - [proactive]: 28+ check-ins + Premium — plan generated on app open.
enum PersonalizationTier {
  standard,
  prefill,
  proactive,
}

/// Types of milestones tracked on the Wellness Journey Map.
///
/// Each corresponds to a completed daily plan count threshold.
enum MilestoneType {
  firstPlan,
  fivePlans,
  tenPlans,
  twentyFivePlans,
  fiftyPlans,
}
