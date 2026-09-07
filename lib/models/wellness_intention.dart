import 'dream.dart';
import 'wellness_enums.dart';

/// A long-term wellness direction chosen by the user.
///
/// Extends [Dream] to preserve backward compatibility with existing data,
/// adding a [category] tag and an [isActive] flag for the AI Wellness Pal
/// feature set.
class WellnessIntention extends Dream {
  final WellnessCategory category;
  final bool isActive;

  WellnessIntention({
    super.id,
    required super.title,
    super.description,
    super.startDate,
    super.deadline,
    super.themeColor,
    super.themeIcon,
    super.backgroundImagePath,
    super.steps,
    required this.category,
    this.isActive = true,
  });

  /// Returns progress based on this intention's own task steps as a value
  /// between 0.0 and 1.0: completed steps / total steps.
  ///
  /// Returns 0.0 when there are no steps (nothing to complete yet).
  double get stepProgress {
    if (steps.isEmpty) return 0.0;
    final completed = steps.where((s) => s.isCompleted).length;
    return completed / steps.length;
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      ...super.toMap(),
      'category': category.name,
      'isActive': isActive,
    };
  }

  factory WellnessIntention.fromMap(Map<String, dynamic> map) {
    final dream = Dream.fromMap(map);
    return WellnessIntention(
      id: dream.id,
      title: dream.title,
      description: dream.description,
      startDate: dream.startDate,
      deadline: dream.deadline,
      themeColor: dream.themeColor,
      themeIcon: dream.themeIcon,
      backgroundImagePath: dream.backgroundImagePath,
      steps: dream.steps,
      category: WellnessCategory.values.firstWhere(
        (c) => c.name == (map['category'] ?? 'general'),
        orElse: () => WellnessCategory.general,
      ),
      isActive: map['isActive'] ?? true,
    );
  }

  /// Converts a raw [Dream] to a [WellnessIntention] for migration purposes.
  ///
  /// Defaults to [WellnessCategory.general] and [isActive] = true.
  /// See Requirement 5.8 — retains all existing Dream fields without data loss.
  factory WellnessIntention.fromDream(Dream dream) {
    return WellnessIntention(
      id: dream.id,
      title: dream.title,
      description: dream.description,
      startDate: dream.startDate,
      deadline: dream.deadline,
      themeColor: dream.themeColor,
      themeIcon: dream.themeIcon,
      backgroundImagePath: dream.backgroundImagePath,
      steps: dream.steps,
      category: WellnessCategory.general,
      isActive: true,
    );
  }
}
