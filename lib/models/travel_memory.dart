import 'package:uuid/uuid.dart';

class TravelMemory {
  final String id;
  final String place; // Place name / city / landmark
  final double latitude;
  final double longitude;
  final DateTime visitedDate;

  /// Travel period: when the trip starts.
  final DateTime? startDate;

  /// Travel period: when the trip ends.
  final DateTime? endDate;

  final String memory; // Legacy description field
  final String? note; // User notes about the trip
  final List<String> photos; // Local paths or Firebase Storage URLs
  final bool isPublic;

  /// Cached AI wellness guidance for this trip. Stored locally so it
  /// survives app restarts without re-querying Gemini.
  final String? wellnessGuidance;

  final String? userId;
  final String? userDisplayName;
  final String? userAvatarUrl;

  TravelMemory({
    String? id,
    required this.place,
    required this.latitude,
    required this.longitude,
    DateTime? visitedDate,
    this.startDate,
    this.endDate,
    this.memory = '',
    this.note,
    this.photos = const [],
    this.isPublic = false,
    this.wellnessGuidance,
    this.userId,
    this.userDisplayName,
    this.userAvatarUrl,
  })  : id = id ?? const Uuid().v4(),
        visitedDate = visitedDate ?? DateTime.now();

  /// Whether the trip is currently active (today falls within the period).
  bool get isActiveNow {
    if (startDate == null || endDate == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start =
        DateTime(startDate!.year, startDate!.month, startDate!.day);
    final end = DateTime(endDate!.year, endDate!.month, endDate!.day);
    return !today.isBefore(start) && !today.isAfter(end);
  }

  /// True when today is before the trip start (upcoming trip).
  bool get isUpcoming {
    if (startDate == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start =
        DateTime(startDate!.year, startDate!.month, startDate!.day);
    return today.isBefore(start);
  }

  /// Returns a copy with an updated wellness guidance string.
  TravelMemory withGuidance(String guidance) => TravelMemory(
        id: id,
        place: place,
        latitude: latitude,
        longitude: longitude,
        visitedDate: visitedDate,
        startDate: startDate,
        endDate: endDate,
        memory: memory,
        note: note,
        photos: photos,
        isPublic: isPublic,
        wellnessGuidance: guidance,
        userId: userId,
        userDisplayName: userDisplayName,
        userAvatarUrl: userAvatarUrl,
      );

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'place': place,
      'latitude': latitude,
      'longitude': longitude,
      'visitedDate': visitedDate.toIso8601String(),
      'startDate': startDate?.toIso8601String(),
      'endDate': endDate?.toIso8601String(),
      'memory': memory,
      'note': note,
      'photos': photos,
      'isPublic': isPublic,
      'wellnessGuidance': wellnessGuidance,
      'userId': userId,
      'userDisplayName': userDisplayName,
      'userAvatarUrl': userAvatarUrl,
    };
  }

  factory TravelMemory.fromMap(Map<String, dynamic> map) {
    return TravelMemory(
      id: map['id'],
      place: map['place'] ?? 'Unknown Place',
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      visitedDate: DateTime.parse(
          map['visitedDate'] ?? DateTime.now().toIso8601String()),
      startDate: map['startDate'] != null
          ? DateTime.tryParse(map['startDate'] as String)
          : null,
      endDate: map['endDate'] != null
          ? DateTime.tryParse(map['endDate'] as String)
          : null,
      memory: map['memory'] ?? '',
      note: map['note'] as String?,
      photos: List<String>.from(map['photos'] ?? []),
      isPublic: map['isPublic'] ?? false,
      wellnessGuidance: map['wellnessGuidance'] as String?,
      userId: map['userId'] as String?,
      userDisplayName: map['userDisplayName'] as String?,
      userAvatarUrl: map['userAvatarUrl'] as String?,
    );
  }
}
