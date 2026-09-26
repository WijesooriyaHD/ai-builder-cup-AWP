import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/live_conversation_record.dart';
import '../providers/app_state.dart';
import '../services/app_navigation_service.dart';
import '../services/conversation_store.dart';
import '../screens/achievement_completion_page.dart';
import 'ai_wellness_loader.dart';

/// A bottom sheet that shows the full two-sided transcript of a saved Live
/// conversation, with the same Delete + Generate Reflection actions as the
/// card it opened from.
class ConversationTranscriptSheet extends StatefulWidget {
  const ConversationTranscriptSheet({super.key, required this.record});

  final LiveConversationRecord record;

  /// Opens the transcript for [record] as a modal bottom sheet.
  static Future<void> open(BuildContext context, LiveConversationRecord record) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ConversationTranscriptSheet(record: record),
    );
  }

  @override
  State<ConversationTranscriptSheet> createState() =>
      _ConversationTranscriptSheetState();
}

class _ConversationTranscriptSheetState
    extends State<ConversationTranscriptSheet> {
  bool _generating = false;

  Future<void> _generateReflection() async {
    if (_generating) return;
    setState(() => _generating = true);

    final store = context.read<ConversationStore>();
    final appState = context.read<AppState>();
    final nav = context.read<AppNavigationService>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final result = await store.generateReflection(widget.record, appState);
    if (!mounted) return;
    setState(() => _generating = false);

    messenger.showSnackBar(
      SnackBar(
        content: Text(result.ok
            ? 'Reflection added to your Reflections.'
            : "Couldn't create the reflection. Please try again."),
      ),
    );
    if (result.ok) {
      // Show any newly-unlocked achievement (e.g. "Inner Voice") before
      // navigating away, so the user sees the badge celebration.
      for (final achievement in result.achievements) {
        if (!mounted) break;
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) =>
              AchievementCompletionPage(achievement: achievement),
          fullscreenDialog: true,
        ));
      }
      if (mounted) {
        navigator.pop(); // close the transcript sheet
        nav.goToTab(AppTab.reflection);
      }
    }
  }

  Future<void> _delete() async {
    final store = context.read<ConversationStore>();
    final navigator = Navigator.of(context);
    await store.delete(widget.record.id);
    if (mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1A27) : Colors.white,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[400],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Icon(Icons.forum_rounded,
                    size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.record.title,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: widget.record.turns.length,
              itemBuilder: (context, index) {
                final turn = widget.record.turns[index];
                return _TranscriptBubble(turn: turn, isDark: isDark);
              },
            ),
          ),
          _buildActions(theme),
        ],
      ),
    );
  }

  Widget _buildActions(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _generating ? null : _delete,
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: const Text('Delete'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red.shade400,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              onPressed: _generating ? null : _generateReflection,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              child: _generating
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AiWellnessLoader(
                          color: theme.colorScheme.onPrimary,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        const Text('Creating…'),
                      ],
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.auto_awesome_rounded, size: 18),
                        SizedBox(width: 8),
                        Text('Reflection'),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TranscriptBubble extends StatelessWidget {
  const _TranscriptBubble({required this.turn, required this.isDark});

  final ConversationTurn turn;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = turn.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        decoration: BoxDecoration(
          color: isUser
              ? theme.colorScheme.primary.withOpacity(0.12)
              : (isDark ? Colors.white.withOpacity(0.06) : Colors.grey.shade100),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isUser ? 'You' : 'Pal',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary.withOpacity(0.8),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              turn.text,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
            ),
          ],
        ),
      ),
    );
  }
}
