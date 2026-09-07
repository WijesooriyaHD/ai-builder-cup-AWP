import 'package:uuid/uuid.dart';

class ChallengeStep {
  final String id;
  final String title;
  final int durationMinutes;
  bool isCompleted;
  DateTime? completedAt;
  DateTime? scheduledDate;

  ChallengeStep({
    String? id,
    required this.title,
    this.durationMinutes = 10,
    this.isCompleted = false,
    this.completedAt,
    this.scheduledDate,
  }) : id = id ?? const Uuid().v4();

  ChallengeStep copyWith({
    String? title,
    int? durationMinutes,
    bool? isCompleted,
    DateTime? completedAt,
    DateTime? scheduledDate,
  }) {
    return ChallengeStep(
      id: id,
      title: title ?? this.title,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      isCompleted: isCompleted ?? this.isCompleted,
      completedAt: completedAt ?? this.completedAt,
      scheduledDate: scheduledDate ?? this.scheduledDate,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'durationMinutes': durationMinutes,
      'isCompleted': isCompleted,
      'completedAt': completedAt?.toIso8601String(),
      'scheduledDate': scheduledDate?.toIso8601String(),
    };
  }

  factory ChallengeStep.fromMap(Map<String, dynamic> map) {
    return ChallengeStep(
      id: map['id'],
      title: map['title'],
      durationMinutes: map['durationMinutes'] ?? 10,
      isCompleted: map['isCompleted'] ?? false,
      completedAt: map['completedAt'] != null
          ? DateTime.parse(map['completedAt'])
          : null,
      scheduledDate: map['scheduledDate'] != null
          ? DateTime.parse(map['scheduledDate'])
          : null,
    );
  }
}
