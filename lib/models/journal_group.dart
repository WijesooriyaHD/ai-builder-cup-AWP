class JournalGroup {
  final String id;
  final String name;
  final int color;
  final int iconCodePoint; // Store icon as codePoint
  final DateTime createdAt;

  JournalGroup({
    String? id,
    required this.name,
    required this.color,
    this.iconCodePoint = 0xe2c7, // Default to folder icon
    DateTime? createdAt,
  })  : id = id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'color': color,
      'iconCodePoint': iconCodePoint,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory JournalGroup.fromMap(Map<String, dynamic> map) {
    return JournalGroup(
      id: map['id'],
      name: map['name'],
      color: map['color'],
      iconCodePoint: map['iconCodePoint'] ?? 0xe2c7,
      createdAt: DateTime.parse(map['createdAt']),
    );
  }

  JournalGroup copyWith({
    String? name,
    int? color,
    int? iconCodePoint,
  }) {
    return JournalGroup(
      id: id,
      name: name ?? this.name,
      color: color ?? this.color,
      iconCodePoint: iconCodePoint ?? this.iconCodePoint,
      createdAt: createdAt,
    );
  }
}
