import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/live_conversation_record.dart';
import '../providers/app_state.dart';
import '../providers/check_in_state.dart';
import '../services/ai_service.dart';
import '../services/auth_service.dart';
import '../services/conversation_store.dart';
import '../services/wellness_chat_guard.dart';
import '../utils/pro_modal_utils.dart';
import '../services/chat_quota.dart';
import '../utils/wellnesspal_snackbar.dart';

/// Typed chat with the Wellness Pal, opened from the "Chat" button on the
/// Wellness Pal screen.
///
/// The text counterpart to the Live voice pal. Conversations are saved into the
/// same [ConversationStore] as spoken ones, so they appear together under
/// "Recent Conversations" and share its 3-record cap. Tapping a saved chat card
/// reopens this screen with [existingRecord] so the conversation continues
/// where it left off.
///
/// Replies come from [AIService.chatWithPal], which follows the same approach
/// as the Reflections → Discuss flow.
class WellnessPalChatScreen extends StatefulWidget {
  /// A previously saved chat to resume. Null starts a new conversation.
  final LiveConversationRecord? existingRecord;

  const WellnessPalChatScreen({super.key, this.existingRecord});

  static Future<void> open(
    BuildContext context, {
    LiveConversationRecord? record,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WellnessPalChatScreen(existingRecord: record),
      ),
    );
  }

  @override
  State<WellnessPalChatScreen> createState() => _WellnessPalChatScreenState();
}

class _WellnessPalChatScreenState extends State<WellnessPalChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocus = FocusNode();

  final List<_ChatTurn> _turns = [];

  /// The record this chat writes to. Created on the first user message so an
  /// opened-then-abandoned chat doesn't evict a real conversation from the
  /// 3-record list.
  LiveConversationRecord? _record;

  bool _isSending = false;

  /// Starter prompts, shown only until the user says something.
  static const List<String> _starters = [
    "I'm feeling stressed",
    "I can't sleep well",
    "I have no energy today",
    "Help me build a habit",
  ];

  @override
  void initState() {
    super.initState();

    final existing = widget.existingRecord;
    if (existing != null) {
      _record = existing;
      _turns.addAll(existing.turns.map((t) => _ChatTurn(
            text: t.text,
            isUser: t.isUser,
            // Older chats (and spoken turns) have no stored time; fall back to
            // the conversation's own start so the bubbles still read sensibly.
            timestamp: t.timestamp ?? existing.createdAt,
          )));
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _scrollToBottom(animate: false));
    } else {
      _turns.add(_ChatTurn(text: _greeting(), isUser: false));
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  String get _userName {
    final user = AuthService().currentUser;
    final raw = user?.displayName ?? user?.email?.split('@').first ?? '';
    final first = raw.trim().split(' ').first;
    if (first.isEmpty) return '';
    return first[0].toUpperCase() + first.substring(1).toLowerCase();
  }

  String _greeting() {
    final name = _userName;
    return name.isEmpty
        ? "Hey! I'm your Wellness Pal. What's on your mind today?"
        : "Hey $name! I'm your Wellness Pal. What's on your mind today?";
  }

  /// A short snapshot of how the user is doing, so the Pal's first replies
  /// aren't generic. Best-effort — omitted entirely when nothing is known.
  String _wellnessContext() {
    final lines = <String>[];

    final checkIn = context.read<CheckInState>().todaysCheckIn;
    if (checkIn != null) {
      if (checkIn.energyScore != null) {
        lines.add("Today's energy: ${checkIn.energyScore}/5");
      }
      if (checkIn.moodState != null) {
        lines.add("Today's mood: ${checkIn.moodState!.name}");
      }
      if (checkIn.recoveryStatus != null) {
        lines.add('Recovery: ${checkIn.recoveryStatus!.name}');
      }
    }

    final intentions = context.read<AppState>().intentions;
    if (intentions.isNotEmpty) {
      lines.add(
          'Wellness intentions: ${intentions.take(3).map((i) => i.title).join(", ")}');
    }

    return lines.join('\n');
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

  Future<void> _send(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || _isSending) return;

    // Free tier: three messages a day. Checked BEFORE the message is added to
    // the transcript, so a blocked attempt leaves no half-sent turn behind.
    if (!await ChatQuota.canSend()) {
      if (!mounted) return;
      _showQuotaReached();
      return;
    }
    await ChatQuota.recordSend();
    if (!mounted) return;

    setState(() {
      _turns.add(_ChatTurn(text: text, isUser: true));
      _messageController.clear();
      _isSending = true;
    });
    _scrollToBottom();

    // Layer 1: obvious off-topic asks get an instant redirect, no model call.
    if (WellnessChatGuard.isOffTopic(text)) {
      setState(() {
        _turns.add(_ChatTurn(
            text: WellnessChatGuard.redirectMessage, isUser: false));
        _isSending = false;
      });
      _scrollToBottom();
      await _persist();
      return;
    }

    try {
      // Everything except the message we just added, so the Pal has context.
      final history = _turns
          .take(_turns.length - 1)
          .map((t) => {'role': t.isUser ? 'user' : 'ai', 'text': t.text})
          .toList();

      final reply = await AIService().chatWithPal(
        history: history,
        userMessage: text,
        userName: _userName,
        wellnessContext: _wellnessContext(),
      );

      if (!mounted) return;
      setState(() {
        _turns.add(_ChatTurn(
          text: reply ??
              "I'm having trouble responding right now. Could you try again, "
                  "or check your connection?",
          isUser: false,
        ));
        _isSending = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      final reason = e.toString().replaceFirst('Exception: ', '');
      setState(() {
        _turns.add(_ChatTurn(text: reason, isUser: false));
        _isSending = false;
      });
      _scrollToBottom();
      WellnessPalSnackBar.show(context, message: reason, isError: true);
    }

    await _persist();
  }

  /// Shown once a free user has used their three messages for the day.
  ///
  /// States plainly what happened, when it resets, and offers the upgrade —
  /// rather than silently refusing to send, which reads as the app being
  /// broken.
  void _showQuotaReached() {
    final theme = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: theme.brightness == Brightness.dark
              ? theme.cardColor
              : Colors.white,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.forum_rounded,
                  size: 32, color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 18),
            Text(
              "That's your ${ChatQuota.freeDailyMessages} messages for today",
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                  fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Your free chat resets tomorrow. Upgrade to Premium for '
              'unlimited conversations with your pal.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.65),
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  ProModalUtils.openUpgrade(context);
                },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Upgrade to Premium',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.pop(sheetContext),
              child: const Text('Maybe later'),
            ),
          ],
        ),
      ),
    );
  }

  /// Saves the conversation into the shared "Recent Conversations" list.
  ///
  /// Creates the record on the first exchange and updates it in place after
  /// that, so an ongoing chat occupies one card rather than a new one per
  /// message. The AI title is generated once, when the record is created.
  Future<void> _persist() async {
    // Nothing worth saving until the user has actually said something.
    if (!_turns.any((t) => t.isUser)) return;

    final store = context.read<ConversationStore>();
    final turns = _turns
        .map((t) => ConversationTurn(
              isUser: t.isUser,
              text: t.text,
              timestamp: t.timestamp,
            ))
        .toList();

    final existing = _record;
    if (existing == null) {
      final firstUserLine =
          _turns.firstWhere((t) => t.isUser, orElse: () => _turns.first).text;
      final record = LiveConversationRecord(
        title: _fallbackTitle(firstUserLine),
        turns: turns,
        source: ConversationSource.chat,
      );
      _record = record;
      // add() enforces the 3-record FIFO cap and kicks off AI titling.
      await store.add(record, generateTitle: true);
    } else {
      // Take the title from the store's copy, not ours: add() generates an AI
      // title in the background and updates the record there, so reusing our
      // local title would clobber it back to the fallback on the next save.
      final current = store.records.where((r) => r.id == existing.id);
      final title = current.isEmpty ? existing.title : current.first.title;
      _record = existing.copyWith(title: title, turns: turns);
      await store.upsert(_record!);
    }
  }

  /// Immediate card label, shown until the AI title arrives.
  String _fallbackTitle(String firstLine) {
    final trimmed = firstLine.trim();
    if (trimmed.isEmpty) return 'Chat with Pal';
    return trimmed.length <= 40 ? trimmed : '${trimmed.substring(0, 37)}...';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final showStarters = !_turns.any((t) => t.isUser) && !_isSending;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 0,
        title: Row(
          children: [
            Icon(Icons.forum_rounded,
                size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              'Chat with Pal',
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(child: _buildTranscript(isDark)),
          if (showStarters) _buildStarters(theme),
          _buildInputArea(theme, isDark),
        ],
      ),
    );
  }

  Widget _buildTranscript(bool isDark) {
    final itemCount = _turns.length + (_isSending ? 1 : 0);

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index >= _turns.length) return _TypingBubble(isDark: isDark);
        return _Bubble(turn: _turns[index], isDark: isDark);
      },
    );
  }

  /// Tappable openers so a new chat doesn't start on a blank page.
  Widget _buildStarters(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _starters
              .map((s) => ActionChip(
                    label: Text(s, style: const TextStyle(fontSize: 13)),
                    onPressed: () => _send(s),
                    backgroundColor:
                        theme.colorScheme.primary.withOpacity(0.08),
                    side: BorderSide(
                        color: theme.colorScheme.primary.withOpacity(0.25)),
                    labelStyle: TextStyle(color: theme.colorScheme.primary),
                  ))
              .toList(),
        ),
      ),
    );
  }

  Widget _buildInputArea(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          )
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                focusNode: _inputFocus,
                minLines: 1,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.send,
                decoration: InputDecoration(
                  hintText: 'Message your pal...',
                  filled: true,
                  fillColor: isDark
                      ? Colors.white.withOpacity(0.05)
                      : Colors.grey.shade100,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                ),
                onSubmitted: _send,
              ),
            ),
            const SizedBox(width: 8),
            CircleAvatar(
              backgroundColor: _isSending
                  ? theme.colorScheme.primary.withOpacity(0.4)
                  : theme.colorScheme.primary,
              child: IconButton(
                icon: const Icon(Icons.send_rounded,
                    color: Colors.white, size: 20),
                onPressed:
                    _isSending ? null : () => _send(_messageController.text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One rendered turn, with the time it was sent (persisted on
/// [ConversationTurn] so a resumed chat shows the original times).
class _ChatTurn {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  _ChatTurn({required this.text, required this.isUser, DateTime? timestamp})
      : timestamp = timestamp ?? DateTime.now();
}

class _Bubble extends StatelessWidget {
  final _ChatTurn turn;
  final bool isDark;

  const _Bubble({required this.turn, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = turn.isUser;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isUser
                  ? theme.colorScheme.primary
                  : (isDark ? Colors.grey.shade900 : Colors.white),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(20),
                topRight: const Radius.circular(20),
                bottomLeft: Radius.circular(isUser ? 20 : 4),
                bottomRight: Radius.circular(isUser ? 4 : 20),
              ),
              border: isUser
                  ? null
                  : Border.all(color: Colors.grey.withOpacity(0.2)),
            ),
            child: Text(
              turn.text,
              style: TextStyle(
                fontSize: 15,
                height: 1.45,
                color: isUser ? Colors.white : theme.colorScheme.onSurface,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 6, right: 6),
            child: Text(
              DateFormat('h:mm a').format(turn.timestamp),
              style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
            ),
          ),
        ],
      ),
    );
  }
}

/// Three-dot "pal is typing" bubble.
class _TypingBubble extends StatefulWidget {
  final bool isDark;

  const _TypingBubble({required this.isDark});

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble>
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
    final theme = Theme.of(context);

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: widget.isDark ? Colors.grey.shade900 : Colors.white,
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
                final t = (_controller.value - (i * 0.2)) % 1.0;
                final opacity =
                    t < 0.5 ? 0.3 + (t * 1.4) : 1.0 - ((t - 0.5) * 1.4);
                return Padding(
                  padding: EdgeInsets.only(right: i == 2 ? 0 : 5),
                  child: Opacity(
                    opacity: opacity.clamp(0.3, 1.0),
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
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
