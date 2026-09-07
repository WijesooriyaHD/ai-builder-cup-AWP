class JournalEntry {
  final String id;
  final String title;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;
  final JournalEntryType type;
  final int color; // Store as int for serialization
  final List<TodoItem> todos;
  final bool isPinned; // Pin to top
  final bool isSaved; // Saved/Favorite
  final String? aiInsight; // Stored AI response
  final String? mood; // Emoji mood
  final List<String> tags; // Organization tags
  final String? sourceEntryId; // Link to original entry for insights
  final String? groupId; // Journal group this entry belongs to

  JournalEntry({
    String? id,
    required this.title,
    required this.content,
    DateTime? createdAt,
    DateTime? updatedAt,
    required this.type,
    required this.color,
    List<TodoItem>? todos,
    this.isPinned = false,
    this.isSaved = false,
    this.aiInsight,
    this.mood,
    List<String>? tags,
    this.sourceEntryId,
    this.groupId,
  })  : id = id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now(),
        todos = todos ?? [],
        tags = tags ?? [];

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'type': type.toString(),
      'color': color,
      'todos': todos.map((t) => t.toMap()).toList(),
      'isPinned': isPinned,
      'isSaved': isSaved,
      'aiInsight': aiInsight,
      'mood': mood,
      'tags': tags,
      'sourceEntryId': sourceEntryId,
      'groupId': groupId,
    };
  }

  factory JournalEntry.fromMap(Map<String, dynamic> map) {
    return JournalEntry(
      id: map['id'],
      title: map['title'],
      content: map['content'],
      createdAt: DateTime.parse(map['createdAt']),
      updatedAt: DateTime.parse(map['updatedAt']),
      type: JournalEntryType.values.firstWhere(
        (e) => e.toString() == map['type'],
        orElse: () => JournalEntryType.note,
      ),
      color: map['color'],
      todos: (map['todos'] as List<dynamic>?)
              ?.map((t) => TodoItem.fromMap(t))
              .toList() ??
          [],
      isPinned: map['isPinned'] ?? false,
      isSaved: map['isSaved'] ?? false,
      aiInsight: map['aiInsight'],
      mood: map['mood'],
      tags: List<String>.from(map['tags'] ?? []),
      sourceEntryId: map['sourceEntryId'],
      groupId: map['groupId'],
    );
  }

  JournalEntry copyWith({
    String? title,
    String? content,
    DateTime? updatedAt,
    JournalEntryType? type,
    int? color,
    List<TodoItem>? todos,
    bool? isPinned,
    bool? isSaved,
    String? aiInsight,
    String? mood,
    List<String>? tags,
    String? sourceEntryId,
    String? groupId,
  }) {
    return JournalEntry(
      id: id,
      title: title ?? this.title,
      content: content ?? this.content,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      type: type ?? this.type,
      color: color ?? this.color,
      todos: todos ?? this.todos,
      isPinned: isPinned ?? this.isPinned,
      isSaved: isSaved ?? this.isSaved,
      aiInsight: aiInsight ?? this.aiInsight,
      mood: mood ?? this.mood,
      tags: tags ?? this.tags,
      sourceEntryId: sourceEntryId ?? this.sourceEntryId,
      groupId: groupId ?? this.groupId,
    );
  }
}

enum JournalEntryType { note, todo }

class TodoItem {
  final String id;
  final String text;
  final bool isCompleted;

  TodoItem({
    String? id,
    required this.text,
    this.isCompleted = false,
  }) : id = id ?? "${DateTime.now().microsecondsSinceEpoch}_${(100 + (DateTime.now().millisecond % 900))}";

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'text': text,
      'isCompleted': isCompleted,
    };
  }

  factory TodoItem.fromMap(Map<String, dynamic> map) {
    return TodoItem(
      id: map['id'],
      text: map['text'],
      isCompleted: map['isCompleted'] ?? false,
    );
  }

  TodoItem copyWith({
    String? text,
    bool? isCompleted,
  }) {
    return TodoItem(
      id: id,
      text: text ?? this.text,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }
}
