import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/journal_entry.dart';
import '../models/live_conversation_record.dart';
import '../providers/app_state.dart';
import 'ai_service.dart';

/// Holds the most-recent Gemini Live "Talk" conversations (capped at
/// [maxRecords], newest first) shown as cards on the Wellness Assistant page,
/// and persists them to `users/{uid}/live_conversations/{id}`.
///
/// Also owns turning a saved conversation into a pinned wellness reflection
/// (a [JournalEntry] in the Reflection tab), so the card's "Generate
/// Reflection" button and any other caller share one implementation.
class ConversationStore extends ChangeNotifier {
  ConversationStore({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  /// Only ever keep this many conversation cards. Saving a new one when full
  /// drops the oldest (FIFO).
  static const int maxRecords = 3;

  /// Soft lavender used for saved-conversation reflection cards.
  static const int reflectionColor = 0xFFB0A2F2;

  final List<LiveConversationRecord> _records = [];

  /// Current conversations, newest first (already capped at [maxRecords]).
  List<LiveConversationRecord> get records => List.unmodifiable(_records);

  String? get _uid => _auth.currentUser?.uid;

  CollectionReference<Map<String, dynamic>>? _collection() {
    final uid = _uid;
    if (uid == null) return null;
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('live_conversations');
  }

  /// Loads saved conversations from Firestore (call after sign-in / on open).
  Future<void> load() async {
    final col = _collection();
    if (col == null) return;
    try {
      final snap = await col
          .orderBy('createdAt', descending: true)
          .limit(maxRecords)
          .get()
          .timeout(const Duration(seconds: 8));
      _records
        ..clear()
        ..addAll(snap.docs.map((d) => LiveConversationRecord.fromMap(d.data())));
      notifyListeners();
    } catch (e) {
      debugPrint('❌ ConversationStore.load error: $e');
    }
  }

  /// Adds a new conversation, enforcing the FIFO cap of [maxRecords] both
  /// locally and in Firestore. When [generateTitle] is true, an AI title is
  /// generated in the background and the card updated once ready (the passed-in
  /// title is shown immediately as a fallback).
  Future<void> add(
    LiveConversationRecord record, {
    bool generateTitle = false,
  }) async {
    _records.insert(0, record);

    // Enforce the cap: anything beyond maxRecords is the oldest — drop it.
    final overflow = <LiveConversationRecord>[];
    while (_records.length > maxRecords) {
      overflow.add(_records.removeLast());
    }
    notifyListeners();

    final col = _collection();
    if (col != null) {
      try {
        await col
            .doc(record.id)
            .set(record.toMap())
            .timeout(const Duration(seconds: 8));
        // Remove the dropped oldest records from Firestore too.
        for (final old in overflow) {
          try {
            await col.doc(old.id).delete().timeout(const Duration(seconds: 5));
          } catch (_) {}
        }
      } catch (e) {
        debugPrint('❌ ConversationStore.add error: $e');
      }
    }

    if (generateTitle) {
      unawaited(_generateTitle(record));
    }
  }

  /// Generates an AI title for [record] and updates it in place (local +
  /// Firestore). Best-effort — leaves the fallback title on any failure.
  Future<void> _generateTitle(LiveConversationRecord record) async {
    final aiTitle =
        await AIService().generateConversationTitle(record.transcriptText);
    if (aiTitle == null || aiTitle.trim().isEmpty) return;

    final index = _records.indexWhere((r) => r.id == record.id);
    if (index == -1) return; // dropped/deleted meanwhile
    final updated = _records[index].copyWith(title: aiTitle.trim());
    _records[index] = updated;
    notifyListeners();

    final col = _collection();
    if (col == null) return;
    try {
      await col
          .doc(updated.id)
          .set(updated.toMap())
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('❌ ConversationStore._generateTitle sync error: $e');
    }
  }

  /// Deletes a conversation card by [id].
  Future<void> delete(String id) async {
    _records.removeWhere((r) => r.id == id);
    notifyListeners();
    final col = _collection();
    if (col == null) return;
    try {
      await col.doc(id).delete().timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('❌ ConversationStore.delete error: $e');
    }
  }

  /// Turns a saved conversation into a short pinned wellness reflection (a
  /// [JournalEntry] in the Reflection tab). Returns true on success.
  ///
  /// The summary + two tags + mood emoji come from [AIService]; the transcript
  /// is stored in the entry body so the reflection's "Discuss" flow has full
  /// context. Needs [appState] to add the entry (local + notify); Firestore
  /// sync mirrors the journal-entry pattern.
  Future<bool> generateReflection(
    LiveConversationRecord record,
    AppState appState,
  ) async {
    try {
      final transcriptText = record.transcriptText;
      final result = await AIService()
          .summarizeConversationDetailed(transcript: transcriptText);

      final content = StringBuffer()
        ..writeln(result.summary)
        ..writeln()
        ..writeln('— Conversation —')
        ..write(transcriptText);

      // Reuse the title already generated for the conversation card so the
      // reflection matches what the user saw. Fall back to the summarizer's
      // title only if the card has no meaningful title yet.
      final cardTitle = record.title.trim();
      final title = cardTitle.isNotEmpty ? cardTitle : result.title;

      final tags = _buildTags(title, result.tags, transcriptText);

      final entry = JournalEntry(
        title: title,
        content: content.toString().trim(),
        type: JournalEntryType.note,
        color: reflectionColor,
        mood: result.mood,
        tags: tags,
        isPinned: true,
      );

      await appState.addJournalEntry(entry);
      final synced = await _syncJournalEntry(entry);
      if (!synced) appState.markEntryNeedsSync(entry.id);
      return true;
    } catch (e) {
      debugPrint('❌ ConversationStore.generateReflection error: $e');
      return false;
    }
  }

  /// Words too generic to be useful reflection tags.
  static const Set<String> _genericTagWords = {
    'reflection', 'reflections', 'conversation', 'voice', 'chat', 'wellness',
    'talk', 'discussion', 'the', 'and', 'a', 'an', 'of', 'to', 'for', 'my',
    'your', 'with', 'on', 'in', 'about',
  };

  /// Builds the reflection's two tags: the FIRST is the most SIGNIFICANT
  /// keyword from the [title]/subject (ranked by how central it was to the
  /// conversation, using [transcript]); the SECOND is a distinct AI content
  /// keyword (from [aiTags]). Backfills from remaining words if needed.
  List<String> _buildTags(String title, List<String> aiTags, String transcript) {
    final subjectWords = _keywordsFrom(title, transcript);
    final contentTags = aiTags
        .where((t) => t.trim().isNotEmpty && !_isGeneric(t))
        .toList();

    final tags = <String>[];

    // 1) One keyword from the subject/title.
    if (subjectWords.isNotEmpty) tags.add(subjectWords.first);

    // 2) One distinct content keyword from the AI tags.
    for (final t in contentTags) {
      if (!tags.any((x) => x.toLowerCase() == t.toLowerCase())) {
        tags.add(t);
        break;
      }
    }

    // Backfill from remaining subject words, then remaining content tags.
    for (final w in [...subjectWords.skip(1), ...contentTags]) {
      if (tags.length >= 2) break;
      if (!tags.any((x) => x.toLowerCase() == w.toLowerCase())) tags.add(w);
    }

    if (tags.isEmpty) tags.add('Reflection');
    return tags.take(2).toList();
  }

  bool _isGeneric(String tag) =>
      _genericTagWords.contains(tag.toLowerCase().trim());

  /// Meaningful words from [text] (drops generic/stop words), ranked by
  /// SIGNIFICANCE rather than position: a word that recurs in [transcript] (the
  /// actual subject discussed) ranks higher, with word length as a tiebreaker.
  /// Returned Title-Cased.
  List<String> _keywordsFrom(String text, [String transcript = '']) {
    final lowerTranscript = transcript.toLowerCase();
    final words = RegExp(r"[A-Za-z][A-Za-z']{2,}")
        .allMatches(text)
        .map((m) => m[0]!)
        .where((w) => !_genericTagWords.contains(w.toLowerCase()))
        .toList();
    if (words.isEmpty) return const [];

    // Deduplicate (case-insensitive) preserving order.
    final seen = <String>{};
    final unique = <String>[];
    for (final w in words) {
      final key = w.toLowerCase();
      if (seen.add(key)) unique.add(w);
    }

    int freq(String w) {
      if (lowerTranscript.isEmpty) return 0;
      return RegExp('\\b${RegExp.escape(w.toLowerCase())}')
          .allMatches(lowerTranscript)
          .length;
    }

    // Stable sort by (transcript frequency desc, length desc).
    unique.sort((a, b) {
      final byFreq = freq(b).compareTo(freq(a));
      if (byFreq != 0) return byFreq;
      return b.length.compareTo(a.length);
    });

    return unique
        .map((w) => '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
        .toList();
  }

  Future<bool> _syncJournalEntry(JournalEntry entry) async {
    final uid = _uid;
    if (uid == null) return false;
    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('journal_entries')
          .doc(entry.id)
          .set(entry.toMap())
          .timeout(const Duration(seconds: 5));
      return true;
    } catch (e) {
      debugPrint('❌ ConversationStore._syncJournalEntry error: $e');
      return false;
    }
  }
}
