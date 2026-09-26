/// A persisted "Discuss" conversation about a single wellness reflection.
///
/// One document per journal entry, so reopening Discuss on the same reflection
/// restores exactly where the user left off. Persisted at
/// `users/{uid}/journal_discussions/{entryId}`. Serialization mirrors the app's
/// other models (hand-rolled toMap/fromMap, ISO-8601 dates).
///
/// See also [LiveConversationRecord], which stores the voice "Talk"
/// conversations under `users/{uid}/live_conversations/{id}`.
class JournalDiscussion {
  /// The id of the [JournalEntry] this discussion belongs to. Doubles as the
  /// Firestore document id, which is what makes the lookup a single get().
  final String entryId;

  /// The ordered transcript, oldest first — the same order it renders in.
  final List<DiscussionMessage> messages;

  final DateTime updatedAt;

  JournalDiscussion({
    required this.entryId,
    List<DiscussionMessage>? messages,
    DateTime? updatedAt,
  })  : messages = messages ?? const [],
        updatedAt = updatedAt ?? DateTime.now();

  bool get isEmpty => messages.isEmpty;

  Map<String, dynamic> toMap() => {
        'entryId': entryId,
        'messages': messages.map((m) => m.toMap()).toList(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory JournalDiscussion.fromMap(Map<String, dynamic> map) {
    return JournalDiscussion(
      entryId: (map['entryId'] as String?) ?? '',
      messages: (map['messages'] as List<dynamic>?)
              ?.map((m) => DiscussionMessage.fromMap(
                  Map<String, dynamic>.from(m as Map)))
              .toList() ??
          const [],
      updatedAt: _parseDate(map['updatedAt']),
    );
  }

  static DateTime _parseDate(dynamic value) {
    if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
    return DateTime.now();
  }
}

/// One message in a [JournalDiscussion].
class DiscussionMessage {
  final String text;

  /// True when the message came from the AI, false when the user wrote it.
  final bool isAi;

  /// Whether this AI message was already saved to the journal as an insight.
  /// Persisted so the "Saved" state survives reopening the discussion.
  bool isSaved;

  final DateTime timestamp;

  DiscussionMessage({
    required this.text,
    required this.isAi,
    this.isSaved = false,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'text': text,
        'isAi': isAi,
        'isSaved': isSaved,
        'timestamp': timestamp.toIso8601String(),
      };

  factory DiscussionMessage.fromMap(Map<String, dynamic> map) =>
      DiscussionMessage(
        text: (map['text'] as String?) ?? '',
        isAi: map['isAi'] == true,
        isSaved: map['isSaved'] == true,
        timestamp: JournalDiscussion._parseDate(map['timestamp']),
      );
}
