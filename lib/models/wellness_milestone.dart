import 'travel_memory.dart';
import 'wellness_enums.dart';

/// A [WellnessMilestone] is a type alias for [TravelMemory] preserving backward
/// compatibility with the existing data model while adding wellness semantics.
///
/// Field mapping:
///   place       → milestone name (e.g., "First Plan Completed")
///   latitude    → milestone type enum ordinal (numeric metadata)
///   longitude   → completedPlanCount at time of milestone
///   visitedDate → achievementDate
///   memory      → supporting message
///   note        → optional user annotation
typedef WellnessMilestone = TravelMemory;

/// Helper class providing factory creation and lookup utilities for
/// [WellnessMilestone] instances.
class WellnessMilestoneHelper {
  WellnessMilestoneHelper._();

  /// Predefined supporting messages for each [MilestoneType].
  static const Map<MilestoneType, String> _supportingMessages = {
    MilestoneType.firstPlan:
        'You took the first step on your wellness journey. That takes courage.',
    MilestoneType.fivePlans:
        'Five plans completed — you\'re building a rhythm that works for you.',
    MilestoneType.tenPlans:
        'Ten plans down. Your consistency is something to be proud of.',
    MilestoneType.twentyFivePlans:
        'Twenty-five plans! You\'ve made wellness a natural part of your life.',
    MilestoneType.fiftyPlans:
        'Fifty plans completed. Your dedication to yourself is truly inspiring.',
  };

  /// Maps milestone trigger counts to their corresponding [MilestoneType].
  static const Map<int, MilestoneType> _thresholds = {
    1: MilestoneType.firstPlan,
    5: MilestoneType.fivePlans,
    10: MilestoneType.tenPlans,
    25: MilestoneType.twentyFivePlans,
    50: MilestoneType.fiftyPlans,
  };

  /// Creates a [WellnessMilestone] (i.e., a [TravelMemory]) from wellness
  /// milestone data, mapping semantic fields to [TravelMemory] fields.
  static TravelMemory create({
    required String milestoneName,
    required MilestoneType type,
    required int completedPlanCount,
    required DateTime achievementDate,
    required String supportingMessage,
  }) =>
      TravelMemory(
        place: milestoneName,
        latitude: type.index.toDouble(),
        longitude: completedPlanCount.toDouble(),
        visitedDate: achievementDate,
        memory: supportingMessage,
      );

  /// Returns the predefined supporting message for the given [type].
  static String supportingMessageFor(MilestoneType type) =>
      _supportingMessages[type]!;

  /// Returns the [MilestoneType] corresponding to the given [planCount]
  /// if it matches a milestone threshold (1, 5, 10, 25, 50), or `null`
  /// otherwise.
  static MilestoneType? getMilestoneForCount(int planCount) =>
      _thresholds[planCount];
}
