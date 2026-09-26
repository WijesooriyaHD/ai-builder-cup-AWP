import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/journal_discussion.dart';

/// Persists the "Discuss" conversations held about wellness reflections.
///
/// One document per reflection at `users/{uid}/journal_discussions/{entryId}`,
/// so reopening Discuss on the same reflection restores the previous
/// conversation and its saved insights.
///
/// Mirrors [ConversationStore]'s conventions: the same `users/{uid}/...`
/// layout, an 8-second timeout on every call, and failures that degrade to a
/// debugPrint rather than throwing — a discussion that can't be reached should
/// still open as a fresh conversation, never crash the screen.
///
/// The existing recursive Firestore rule (`users/{userId}/{document=**}`)
/// already covers this collection, so no rules change is needed.
class JournalDiscussionStore {
  JournalDiscussionStore({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  /// Hard cap on stored messages per discussion. Beyond this the oldest are
  /// dropped (keeping the newest [maxMessages]) so a long-running discussion
  /// can't grow the document toward Firestore's 1 MB limit.
  static const int maxMessages = 200;

  static const Duration _timeout = Duration(seconds: 8);

  String? get _uid => _auth.currentUser?.uid;

  DocumentReference<Map<String, dynamic>>? _doc(String entryId) {
    final uid = _uid;
    if (uid == null || uid.isEmpty || entryId.isEmpty) return null;
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('journal_discussions')
        .doc(entryId);
  }

  /// Loads the stored discussion for [entryId].
  ///
  /// Returns null when there's nothing saved yet, the user is signed out, or
  /// the read fails — all of which the caller treats the same way: start a
  /// fresh conversation.
  Future<JournalDiscussion?> load(String entryId) async {
    final ref = _doc(entryId);
    if (ref == null) return null;
    try {
      final snap = await ref.get().timeout(_timeout);
      final data = snap.data();
      if (!snap.exists || data == null) return null;
      final discussion = JournalDiscussion.fromMap(data);
      return discussion.isEmpty ? null : discussion;
    } catch (e) {
      debugPrint('❌ JournalDiscussionStore.load error: $e');
      return null;
    }
  }

  /// Writes the whole transcript for [entryId], replacing what's there.
  ///
  /// The conversation is short and always saved as a unit, so a single set()
  /// is simpler and cheaper than diffing individual messages.
  Future<void> save(String entryId, List<DiscussionMessage> messages) async {
    final ref = _doc(entryId);
    if (ref == null) return;

    // Keep only the newest [maxMessages] so the document stays well inside
    // Firestore's per-document size limit.
    final trimmed = messages.length > maxMessages
        ? messages.sublist(messages.length - maxMessages)
        : messages;

    try {
      final discussion = JournalDiscussion(
        entryId: entryId,
        messages: trimmed,
        updatedAt: DateTime.now(),
      );
      await ref.set(discussion.toMap()).timeout(_timeout);
    } catch (e) {
      // Non-fatal: the conversation stays usable in memory for this session.
      debugPrint('❌ JournalDiscussionStore.save error: $e');
    }
  }

  /// Removes the stored discussion for [entryId] (e.g. when its reflection is
  /// deleted), so it doesn't linger as an orphan.
  Future<void> delete(String entryId) async {
    final ref = _doc(entryId);
    if (ref == null) return;
    try {
      await ref.delete().timeout(_timeout);
    } catch (e) {
      debugPrint('❌ JournalDiscussionStore.delete error: $e');
    }
  }
}
