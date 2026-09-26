import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/journal_discussion.dart';
import '../models/journal_entry.dart';
import '../providers/app_state.dart';
import '../services/ai_service.dart';
import '../services/journal_discussion_store.dart';
import '../utils/wellnesspal_snackbar.dart';

class JournalAiDiscussionScreen extends StatefulWidget {
  final JournalEntry entry;

  const JournalAiDiscussionScreen({super.key, required this.entry});

  @override
  State<JournalAiDiscussionScreen> createState() => _JournalAiDiscussionScreenState();
}

class _JournalAiDiscussionScreenState extends State<JournalAiDiscussionScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final JournalDiscussionStore _store = JournalDiscussionStore();

  final List<DiscussionMessage> _messages = [];

  /// True while the stored transcript is being fetched — before this finishes
  /// we show a spinner rather than the opener, so a restored conversation
  /// never flashes a "let's start" message first.
  bool _isRestoring = true;

  /// True while waiting on an AI reply (drives the typing indicator).
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _restoreConversation();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// The AI's grounding message, used only when there's no stored history.
  DiscussionMessage _openerMessage() {
    final title = widget.entry.title.trim();
    final opener = title.isNotEmpty
        ? "I've read your entry “$title”. What feels most alive for you in it right now, and how are you doing with it?"
        : "I've read your journal entry. What feels most alive for you in it right now, and how are you doing with it?";
    return DiscussionMessage(text: opener, isAi: true);
  }

  /// Loads any previous discussion for this reflection, falling back to a
  /// fresh conversation when there's nothing saved (or the read failed).
  Future<void> _restoreConversation() async {
    final stored = await _store.load(widget.entry.id);
    if (!mounted) return;

    setState(() {
      _messages
        ..clear()
        ..addAll(stored?.messages ?? [_openerMessage()]);
      _isRestoring = false;
    });

    // A restored conversation should open at the latest message, like any
    // messaging app — jump rather than animate, so it's already in place.
    _scrollToBottom(animate: false);

    // Persist the opener so a conversation the user never replies to is still
    // the same one next time they open it.
    if (stored == null) {
      await _store.save(widget.entry.id, _messages);
    }
  }

  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (animate) {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(target);
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending || _isRestoring) return;

    setState(() {
      _messages.add(DiscussionMessage(text: text, isAi: false));
      _messageController.clear();
      _isSending = true;
    });
    _scrollToBottom();

    try {
      // Build the prior conversation (everything except the message we just
      // added) so the AI can respond in context.
      final history = _messages
          .take(_messages.length - 1)
          .map((m) => {'role': m.isAi ? 'ai' : 'user', 'text': m.text})
          .toList();

      final reply = await AIService().discussJournalEntry(
        entryTitle: widget.entry.title,
        entryContent: widget.entry.content,
        history: history,
        userMessage: text,
      );

      if (!mounted) return;
      setState(() {
        _messages.add(DiscussionMessage(
          text: reply ??
              "I'm having trouble responding right now. Could you try rephrasing, or check your connection?",
          isAi: true,
        ));
        _isSending = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      // Show the real reason both inline (so the conversation reflects it) and
      // via a snackbar. `e` is already a friendly Exception message from
      // AIService.discussJournalEntry.
      final reason = e.toString().replaceFirst('Exception: ', '');
      setState(() {
        _messages.add(DiscussionMessage(text: reason, isAi: true));
        _isSending = false;
      });
      _scrollToBottom();
      WellnessPalSnackBar.show(context, message: reason, isError: true);
    }

    // Save the exchange (user message + reply, or the error we showed) so it
    // survives closing the screen.
    await _store.save(widget.entry.id, _messages);
  }

  /// Marks an AI message as saved and persists that, so the "Saved" badge
  /// survives reopening the discussion.
  Future<void> _markSaved(DiscussionMessage message) async {
    setState(() => message.isSaved = true);
    await _store.save(widget.entry.id, _messages);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.entry.title.isNotEmpty ? widget.entry.title : "Discussion",
          style: const TextStyle(fontSize: 18),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: _isRestoring
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : _buildTranscript(),
          ),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildTranscript() {
    // One extra row at the end holds the typing indicator while we wait.
    final itemCount = _messages.length + (_isSending ? 1 : 0);

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index >= _messages.length) return const _TypingIndicator();

        final message = _messages[index];
        final previous = index == 0 ? null : _messages[index - 1];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Date separator whenever the day changes, as in a messaging app.
            if (_needsDateSeparator(previous, message))
              _DateSeparator(date: message.timestamp),
            _ChatBubble(
              message: message,
              sourceEntryId: widget.entry.id,
              onSaved: () => _markSaved(message),
            ),
          ],
        );
      },
    );
  }

  bool _needsDateSeparator(DiscussionMessage? previous, DiscussionMessage current) {
    if (previous == null) return true;
    final a = previous.timestamp;
    final b = current.timestamp;
    return a.year != b.year || a.month != b.month || a.day != b.day;
  }

  Widget _buildInputArea() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          )
        ],
      ),
      // Keeps the field clear of the home indicator without adding dead space
      // when the keyboard is up.
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                enabled: !_isRestoring,
                minLines: 1,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.send,
                decoration: InputDecoration(
                  hintText: "Type your thoughts...",
                  filled: true,
                  fillColor: isDark
                      ? Colors.white.withOpacity(0.05)
                      : Colors.grey.shade100,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 10),
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            CircleAvatar(
              backgroundColor:
                  _isSending ? Colors.purple.withOpacity(0.4) : Colors.purple,
              child: IconButton(
                icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                onPressed: _isSending ? null : _sendMessage,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Thin day divider between messages sent on different dates.
class _DateSeparator extends StatelessWidget {
  final DateTime date;

  const _DateSeparator({required this.date});

  String _label() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(date.year, date.month, date.day);
    final difference = today.difference(that).inDays;

    if (difference == 0) return 'Today';
    if (difference == 1) return 'Yesterday';
    if (difference < 7) return DateFormat('EEEE').format(date);
    return DateFormat('MMM d, y').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.grey.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            _label(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
        ),
      ),
    );
  }
}

/// Three-dot "Pal is typing" bubble, shown in the transcript while waiting.
class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: isDark ? Colors.grey.shade900 : Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(20),
          ),
          border: Border.all(color: Colors.grey.withOpacity(0.2)),
        ),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                // Each dot peaks a third of a cycle after the previous one.
                final t = (_controller.value - (i * 0.2)) % 1.0;
                final opacity = t < 0.5 ? 0.3 + (t * 1.4) : 1.0 - ((t - 0.5) * 1.4);
                return Padding(
                  padding: EdgeInsets.only(right: i == 2 ? 0 : 5),
                  child: Opacity(
                    opacity: opacity.clamp(0.3, 1.0),
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: Colors.purple,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final DiscussionMessage message;
  final String sourceEntryId;
  final VoidCallback onSaved;

  const _ChatBubble({
    required this.message,
    required this.sourceEntryId,
    required this.onSaved,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isAi = message.isAi;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment:
            isAi ? CrossAxisAlignment.start : CrossAxisAlignment.end,
        children: [
          Container(
            constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isAi
                  ? (isDark ? Colors.grey.shade900 : Colors.white)
                  : Colors.purple.withOpacity(isDark ? 0.3 : 0.12),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(20),
                topRight: const Radius.circular(20),
                bottomLeft: Radius.circular(isAi ? 4 : 20),
                bottomRight: Radius.circular(isAi ? 20 : 4),
              ),
              border: isAi
                  ? Border.all(color: Colors.grey.withOpacity(0.2))
                  : null,
              boxShadow: isAi
                  ? [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.02),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      )
                    ]
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MarkdownBody(
                  data: message.text,
                  styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)),
                ),
                if (isAi) ...[
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: message.isSaved
                            ? null
                            : () => _saveToJournal(context),
                        icon: Icon(
                          message.isSaved
                              ? Icons.check_circle_rounded
                              : Icons.bookmark_add_outlined,
                          size: 16,
                          color: message.isSaved ? Colors.blue : Colors.purple,
                        ),
                        label: Text(
                          message.isSaved ? "Saved" : "Save as Insight",
                          style: TextStyle(
                            fontSize: 12,
                            color: message.isSaved ? Colors.blue : Colors.purple,
                            fontWeight: message.isSaved
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          // Timestamp under each bubble, aligned to its side.
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 6, right: 6),
            child: Text(
              DateFormat('h:mm a').format(message.timestamp),
              style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
            ),
          ),
        ],
      ),
    );
  }

  void _saveToJournal(BuildContext context) {
    final appState = Provider.of<AppState>(context, listen: false);
    final newEntry = JournalEntry(
      title: "AI Insight: ${DateTime.now().month}/${DateTime.now().day}",
      content: message.text,
      type: JournalEntryType.note,
      color: Colors.purple.shade50.value,
      isSaved: true,
      tags: ["AI Discussion"],
      sourceEntryId: sourceEntryId,
    );
    appState.addJournalEntry(newEntry);

    onSaved();

    WellnessPalSnackBar.show(context,
        message: "Saved to Journal", icon: Icons.check_circle_rounded);
  }
}
