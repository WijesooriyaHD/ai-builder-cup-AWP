/// A saved record of a completed Gemini Live "Talk" conversation.
///
/// These are shown as cards on the Wellness Assistant page (most-recent 3).
/// Tapping a card views the full transcript; from there the user can delete it
/// or generate a wellness reflection out of it.
///
/// Persisted at `users/{uid}/live_conversations/{id}`. Serialization mirrors
/// the app's other models (hand-rolled toMap/fromMap, ISO-8601 dates,
/// client-supplied millisecond id).
class LiveConversationRecord {
  final String id;

  /// Short auto-generated label for the card (e.g. first thing the user said).
  final String title;

  /// The ordered two-sided transcript.
  final List<ConversationTurn> turns;

  final DateTime createdAt;

  LiveConversationRecord({
    String? id,
    required this.title,
    List<ConversationTurn>? turns,
    DateTime? createdAt,
  })  : id = id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        turns = turns ?? const [],
        createdAt = createdAt ?? DateTime.now();

  /// The transcript rendered as plain text with role labels
  /// ("You: ...\nPal: ..."), for summarization or display.
  String get transcriptText => turns
      .where((t) => t.text.trim().isNotEmpty)
      .map((t) => '${t.isUser ? 'You' : 'Pal'}: ${t.text}')
      .join('\n');

  LiveConversationRecord copyWith({String? title}) => LiveConversationRecord(
        id: id,
        title: title ?? this.title,
        turns: turns,
        createdAt: createdAt,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'turns': turns.map((t) => t.toMap()).toList(),
        'createdAt': createdAt.toIso8601String(),
      };

  factory LiveConversationRecord.fromMap(Map<String, dynamic> map) {
    return LiveConversationRecord(
      id: map['id'] as String?,
      title: (map['title'] as String?) ?? 'Conversation',
      turns: (map['turns'] as List<dynamic>?)
              ?.map((t) =>
                  ConversationTurn.fromMap(Map<String, dynamic>.from(t as Map)))
              .toList() ??
          const [],
      createdAt: _parseDate(map['createdAt']),
    );
  }

  static DateTime _parseDate(dynamic value) {
    if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
    return DateTime.now();
  }
}

/// One turn of a saved conversation.
class ConversationTurn {
  final bool isUser;
  final String text;

  const ConversationTurn({required this.isUser, required this.text});

  Map<String, dynamic> toMap() => {'isUser': isUser, 'text': text};

  factory ConversationTurn.fromMap(Map<String, dynamic> map) => ConversationTurn(
        isUser: map['isUser'] == true,
        text: (map['text'] as String?) ?? '',
      );
}
