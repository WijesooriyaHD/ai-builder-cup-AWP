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

  /// How this conversation happened — spoken via the Live pal, or typed in the
  /// Chat pal. Both kinds share the same "Recent Conversations" list (and its
  /// 3-record cap); this only decides the card's icon and whether tapping it
  /// resumes a chat or opens a read-only transcript.
  ///
  /// Defaults to [ConversationSource.voice] so records written before Chat
  /// existed keep behaving exactly as they did.
  final ConversationSource source;

  LiveConversationRecord({
    String? id,
    required this.title,
    List<ConversationTurn>? turns,
    DateTime? createdAt,
    this.source = ConversationSource.voice,
  })  : id = id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        turns = turns ?? const [],
        createdAt = createdAt ?? DateTime.now();

  bool get isChat => source == ConversationSource.chat;

  /// The transcript rendered as plain text with role labels
  /// ("You: ...\nPal: ..."), for summarization or display.
  String get transcriptText => turns
      .where((t) => t.text.trim().isNotEmpty)
      .map((t) => '${t.isUser ? 'You' : 'Pal'}: ${t.text}')
      .join('\n');

  LiveConversationRecord copyWith({
    String? title,
    List<ConversationTurn>? turns,
  }) =>
      LiveConversationRecord(
        id: id,
        title: title ?? this.title,
        turns: turns ?? this.turns,
        createdAt: createdAt,
        source: source,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'turns': turns.map((t) => t.toMap()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'source': source.name,
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
      source: ConversationSource.values.firstWhere(
        (s) => s.name == map['source'],
        // Records saved before Chat existed have no 'source' — they're voice.
        orElse: () => ConversationSource.voice,
      ),
    );
  }

  static DateTime _parseDate(dynamic value) {
    if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
    return DateTime.now();
  }
}

/// Where a saved conversation came from.
enum ConversationSource {
  /// Spoken with the Live pal (Gemini Live audio).
  voice,

  /// Typed in the Chat pal.
  chat,
}

/// One turn of a saved conversation.
class ConversationTurn {
  final bool isUser;
  final String text;

  /// When the turn happened, so a resumed Chat shows the times the messages
  /// were actually sent rather than the moment it was reloaded.
  ///
  /// Null for spoken Live turns, which are captured as a continuous transcript
  /// and never re-rendered as timestamped bubbles — so the Live pal keeps
  /// writing exactly what it wrote before.
  final DateTime? timestamp;

  const ConversationTurn({
    required this.isUser,
    required this.text,
    this.timestamp,
  });

  Map<String, dynamic> toMap() => {
        'isUser': isUser,
        'text': text,
        if (timestamp != null) 'timestamp': timestamp!.toIso8601String(),
      };

  factory ConversationTurn.fromMap(Map<String, dynamic> map) => ConversationTurn(
        isUser: map['isUser'] == true,
        text: (map['text'] as String?) ?? '',
        timestamp: map['timestamp'] is String
            ? DateTime.tryParse(map['timestamp'] as String)
            : null,
      );
}
