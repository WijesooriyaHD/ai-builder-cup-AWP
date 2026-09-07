import 'package:uuid/uuid.dart';
import 'challenge_step.dart';

class Dream {
  final String id;
  final String title;
  final String description;
  final DateTime startDate;
  final DateTime? deadline;
  final int? themeColor; // ARGB int
  final int? themeIcon; // CodePoint
  final String? backgroundImagePath;
  List<ChallengeStep> steps;

  Dream({
    String? id,
    required this.title,
    this.description = '',
    DateTime? startDate,
    this.deadline,
    this.themeColor,
    this.themeIcon,
    this.backgroundImagePath,
    List<ChallengeStep>? steps,
  })  : id = id ?? const Uuid().v4(),
        startDate = startDate ?? DateTime.now(),
        steps = steps ?? [];

  int get completedSteps => steps.where((s) => s.isCompleted).length;
  int get totalSteps => steps.length;
  double get progress => totalSteps == 0 ? 0 : completedSteps / totalSteps;
  
  bool get isCompleted => completedSteps == totalSteps && totalSteps > 0;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'startDate': startDate.toIso8601String(),
      'deadline': deadline?.toIso8601String(),
      'themeColor': themeColor,
      'themeIcon': themeIcon,
      'backgroundImagePath': backgroundImagePath,
      'steps': steps.map((s) => s.toMap()).toList(),
    };
  }

  factory Dream.fromMap(Map<String, dynamic> map) {
    return Dream(
      id: map['id'],
      title: map['title'],
      description: map['description'] ?? '',
      startDate: DateTime.parse(map['startDate']),
      deadline: map['deadline'] != null ? DateTime.parse(map['deadline']) : null,
      themeColor: map['themeColor'],
      themeIcon: map['themeIcon'],
      backgroundImagePath: map['backgroundImagePath'],
      steps: List<ChallengeStep>.from(
        (map['steps'] as List?)?.map((x) => ChallengeStep.fromMap(x)) ?? [],
      ),
    );
  }
}
