import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../widgets/frosted_container.dart';
import 'wellness_library_screen.dart';

/// Displays a Short Read content item in a scrollable view.
///
/// Tracks scroll position. When the user scrolls within 50px of the bottom,
/// writes `completion_timestamp` to Firestore
/// `users/{uid}/wellness_library_completions/{itemId}` and marks as read.
///
/// Uses the partial-success pattern: if the timestamp write succeeds but the
/// status write fails (or vice versa), the app retains whichever write
/// succeeded and does not roll back the successful operation.
///
/// Requirements: 7.2, 7.4
class ShortReadScreen extends StatefulWidget {
  final WellnessLibraryItem item;

  const ShortReadScreen({super.key, required this.item});

  @override
  State<ShortReadScreen> createState() => _ShortReadScreenState();
}

class _ShortReadScreenState extends State<ShortReadScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _hasMarkedComplete = false;
  bool _isWriting = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  /// Checks if user has scrolled within 50px of the bottom.
  void _onScroll() {
    if (_hasMarkedComplete || _isWriting) return;

    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;

    if (maxScroll - currentScroll <= 50) {
      _writeCompletion();
    }
  }

  /// Writes completion to Firestore using partial-success pattern.
  ///
  /// Two independent writes:
  /// 1. `completion_timestamp` field
  /// 2. `status: 'read'` field
  ///
  /// If one succeeds and the other fails, the successful write is retained.
  Future<void> _writeCompletion() async {
    if (_hasMarkedComplete) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _isWriting = true);

    final docRef = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('wellness_library_completions')
        .doc(widget.item.id);

    bool timestampWriteSucceeded = false;
    bool statusWriteSucceeded = false;

    // Write 1: completion_timestamp
    try {
      await docRef.set(
        {
          'completion_timestamp': FieldValue.serverTimestamp(),
          'itemId': widget.item.id,
          'title': widget.item.title,
          'format': widget.item.format,
          'category': widget.item.category,
        },
        SetOptions(merge: true),
      );
      timestampWriteSucceeded = true;
    } catch (e) {
      debugPrint('ShortRead: completion_timestamp write failed: $e');
    }

    // Write 2: mark as read status
    try {
      await docRef.set(
        {'status': 'read'},
        SetOptions(merge: true),
      );
      statusWriteSucceeded = true;
    } catch (e) {
      debugPrint('ShortRead: status write failed: $e');
    }

    // Partial success: retain whichever write succeeded
    if (timestampWriteSucceeded || statusWriteSucceeded) {
      setState(() {
        _hasMarkedComplete = true;
        _isWriting = false;
      });
    } else {
      setState(() => _isWriting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0F1115) : const Color(0xFFF8F9FB),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_rounded,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Short Read',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title and metadata
            FrostedContainer(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.article_rounded,
                            size: 24,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.item.category,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withOpacity(0.8),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${widget.item.durationMinutes} min read',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? Colors.grey[400]
                                      : Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      widget.item.title,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).colorScheme.onSurface,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.item.description,
                      style: TextStyle(
                        fontSize: 15,
                        color: isDark ? Colors.grey[300] : Colors.grey[700],
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Main content body
            FrostedContainer(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  _getContentBody(),
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.7,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Completion indicator
            if (_hasMarkedComplete)
              Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle_rounded,
                        color: Colors.green[600],
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Completed',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.green[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  /// Returns expanded content body based on the item description.
  /// In production this would come from Firestore or a CMS. For now we
  /// generate meaningful placeholder content from the item's metadata.
  String _getContentBody() {
    return '''${widget.item.description}

Taking a moment for yourself is one of the most impactful things you can do for your overall wellness. Whether you have five minutes or thirty, the quality of your attention matters more than the quantity of time.

Research consistently shows that small, intentional pauses throughout the day can significantly reduce stress hormones and improve cognitive function. This isn't about adding more to your plate — it's about being present with what's already there.

Consider how this relates to your own daily rhythm. What moments naturally lend themselves to a brief pause? Perhaps it's the transition between work tasks, or the quiet moment before your household wakes up.

The key is consistency over intensity. A gentle daily practice will serve you far better than an occasional marathon effort. Start where you are, use what you have, do what you can.

Remember: wellness isn't a destination to arrive at. It's a way of moving through your day with awareness and intention. Every small choice adds up to something meaningful over time.

Take what resonates from this reading and leave the rest. Your wellness journey is uniquely yours, and there's no single right way to walk it.''';
  }
}
