import 'wellness_enums.dart';

/// A single action within a [DailyPlan].
///
/// Each action has a category, intensity level, and estimated duration.
/// Actions can be marked as completed by the user via the plan card or widget.
class WellnessAction {
  final String id;
  final String title;
  final int durationMinutes;
  final WellnessCategory category;
  final IntensityLevel intensityLevel;
  final bool isCompleted;

  WellnessAction({
    required this.id,
    required this.title,
    required this.durationMinutes,
    required this.category,
    required this.intensityLevel,
    this.isCompleted = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'durationMinutes': durationMinutes,
      'category': category.name,
      'intensityLevel': intensityLevel.name,
      'isCompleted': isCompleted,
    };
  }

  factory WellnessAction.fromMap(Map<String, dynamic> map) {
    return WellnessAction(
      id: map['id'],
      title: map['title'],
      durationMinutes: map['durationMinutes'],
      category: WellnessCategory.values.firstWhere(
        (c) => c.name == map['category'],
        orElse: () => WellnessCategory.general,
      ),
      intensityLevel: IntensityLevel.values.firstWhere(
        (i) => i.name == map['intensityLevel'],
        orElse: () => IntensityLevel.low,
      ),
      isCompleted: map['isCompleted'] ?? false,
    );
  }

  WellnessAction copyWith({bool? isCompleted}) {
    return WellnessAction(
      id: id,
      title: title,
      durationMinutes: durationMinutes,
      category: category,
      intensityLevel: intensityLevel,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }
}
