import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/feature_flags.dart';
import '../features/habit_builder/presentation/habit_builder_state.dart';
import '../providers/app_state.dart';
import '../services/live_conversation_service.dart';
import '../services/live_tool_bridge.dart';
import '../utils/pro_modal_utils.dart';

/// Premium, real-time "Conversation Mode" bottom sheet powered by the Gemini
/// Live API. Hands-free, natural back-and-forth voice chat with the wellness
/// pal.
///
/// Gating: only reachable when [FeatureFlags.liveConversationMode] is on AND
/// the user is Premium. Free users get an upsell instead of a session.
class ConversationModeSheet extends StatefulWidget {
  const ConversationModeSheet({super.key});

  /// Opens Conversation Mode, or the Premium upsell for Free users. Safe to
  /// call from anywhere; no-ops (with a gentle message) when the feature flag
  /// is off.
  static void open(BuildContext context) {
    if (!FeatureFlags.liveConversationMode) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Conversation Mode is coming soon.')),
      );
      return;
    }
    final isPro = context.read<AppState>().isPro;
    if (!isPro) {
      ProModalUtils.showConversationModeUpsell(context);
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ConversationModeSheet(),
    );
  }

  @override
  State<ConversationModeSheet> createState() => _ConversationModeSheetState();
}

class _ConversationModeSheetState extends State<ConversationModeSheet> {
  /// Warm, wellness-pal persona for the Live session.
  static const String _persona =
      'You are the user\'s warm, encouraging wellness pal having a live, spoken '
      'conversation. Talk like a caring, down-to-earth friend — natural, brief, '
      'and human, with contractions. Keep replies short and conversational '
      '(usually 1-3 sentences) since they are spoken aloud, and end with a '
      'gentle question when it helps the conversation flow. Be positive and '
      'supportive; never shame or alarm the user. Only suggest safe, gentle, '
      'healthy actions. Do not give medical, legal, or financial advice, and '
      'avoid clinical language. For signs of crisis, respond with compassion '
      'and gently encourage reaching out to a trusted person or professional.';

  @override
  void initState() {
    super.initState();
    // Start the session after the first frame so Provider is available.
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    final service = context.read<LiveConversationService>();
    final isPro = context.read<AppState>().isPro;

    // Wire tool calling so the pal can create habits / set reminders mid-chat.
    final bridge = LiveToolBridge(context.read<HabitBuilderState>());
    service.tools = bridge.tools;
    service.onToolCall = bridge.handleToolCall;

    await service.start(isPremium: isPro, systemInstruction: _persona);
  }

  Future<void> _end() async {
    await context.read<LiveConversationService>().stop();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Consumer<LiveConversationService>(
      builder: (context, service, _) {
        final state = service.state;
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
          decoration: BoxDecoration(
            color: theme.brightness == Brightness.dark
                ? theme.cardColor
                : Colors.white,
            borderRadius: BorderRadius.circular(32),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),
              _StatusOrb(state: state, primary: theme.colorScheme.primary),
              const SizedBox(height: 24),
              Text(
                _title(state),
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _subtitle(state, service.lastError),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  // Barge-in / interrupt (manual; SDK VAD is "coming soon").
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: state == LiveConversationState.active
                          ? service.interrupt
                          : null,
                      icon: const Icon(Icons.pan_tool_alt_rounded),
                      label: const Text('Interrupt'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _end,
                      icon: const Icon(Icons.call_end_rounded),
                      label: const Text('End'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red.shade400,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ),
                ],
              ),
              if (state == LiveConversationState.error) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _start,
                  child: const Text('Try again'),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  String _title(LiveConversationState state) {
    switch (state) {
      case LiveConversationState.connecting:
        return 'Connecting…';
      case LiveConversationState.active:
        return 'Listening…';
      case LiveConversationState.closing:
        return 'Wrapping up…';
      case LiveConversationState.error:
        return 'Something went wrong';
      case LiveConversationState.idle:
        return 'Conversation ended';
    }
  }

  String _subtitle(LiveConversationState state, String? error) {
    switch (state) {
      case LiveConversationState.connecting:
        return 'Getting your wellness pal ready.';
      case LiveConversationState.active:
        return 'Just talk naturally — I\'m listening. Tap Interrupt if you '
            'want to jump in while I\'m speaking.';
      case LiveConversationState.closing:
        return 'One moment.';
      case LiveConversationState.error:
        return error ?? 'Please try again.';
      case LiveConversationState.idle:
        return 'Thanks for chatting.';
    }
  }
}

/// A simple animated status indicator that reflects the session state.
class _StatusOrb extends StatelessWidget {
  const _StatusOrb({required this.state, required this.primary});

  final LiveConversationState state;
  final Color primary;

  @override
  Widget build(BuildContext context) {
    final active = state == LiveConversationState.active;
    final connecting = state == LiveConversationState.connecting;
    final isError = state == LiveConversationState.error;
    final color = isError ? Colors.red.shade400 : primary;

    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(active ? 0.16 : 0.08),
        border: Border.all(color: color.withOpacity(0.5), width: 2),
      ),
      alignment: Alignment.center,
      child: connecting
          ? SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            )
          : Icon(
              isError
                  ? Icons.error_outline_rounded
                  : (active ? Icons.graphic_eq_rounded : Icons.mic_none_rounded),
              size: 40,
              color: color,
            ),
    );
  }
}
