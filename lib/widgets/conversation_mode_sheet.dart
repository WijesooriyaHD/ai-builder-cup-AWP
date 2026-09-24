import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/feature_flags.dart';
import '../services/live_conversation_service.dart';
import '../services/voice_command_service.dart';
import 'live_pal_session.dart';

/// Premium, real-time "Conversation Mode" bottom sheet powered by the Gemini
/// Live API. Hands-free, natural back-and-forth voice chat with the wellness
/// pal.
///
/// Gating: reachable when [FeatureFlags.liveConversationMode] is on.
///
/// NOTE: The Premium gate is TEMPORARILY DISABLED for testing so Conversation
/// Mode can be exercised without a subscription. To restore Premium gating,
/// re-add the isPro check in [open] and pass the real isPro to [start] (see the
/// TEMP markers below).
class ConversationModeSheet extends StatefulWidget {
  const ConversationModeSheet({super.key});

  /// Opens Conversation Mode. Safe to call from anywhere; no-ops (with a gentle
  /// message) when the feature flag is off.
  static void open(BuildContext context) {
    if (!FeatureFlags.liveConversationMode) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Conversation Mode is coming soon.')),
      );
      return;
    }
    // TEMP(test): Premium gate disabled. Restore with:
    //   if (!context.read<AppState>().isPro) {
    //     ProModalUtils.showConversationModeUpsell(context); return;
    //   }
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

/// Warm, wellness-pal persona for the Live session — with full knowledge of
/// the app and its tools so the pal can guide AND act.
///
/// Top-level and shared by BOTH Live entry points (the Wellness Pal sheet and
/// this legacy Conversation Mode sheet) so the persona can never drift between
/// them.
///
/// Assembled from three parts so the middle one ([kWellnessPalAppKnowledge])
/// can be reused by the DEFAULT tap-to-speak pal too — both pals then describe
/// the app identically and can't drift out of sync.
const String _livePalIntro =
      'You are the user\'s warm, encouraging wellness pal in AI Wellness Pal, '
      'having a live, spoken conversation. Talk like a caring, down-to-earth '
      'friend — natural, brief, human, with contractions. BE CONCISE BY '
      'DEFAULT: usually 1-2 short sentences since replies are spoken aloud; '
      'only go longer if the user explicitly asks for detail. Get to the point '
      'quickly, then end with a gentle question when it helps. If the user '
      'starts talking while you are speaking, stop immediately and listen — '
      'never talk over them. Be positive; never shame or alarm the '
      'user. Only suggest safe, gentle, healthy actions. No medical, legal, or '
      'financial advice; avoid clinical language. For signs of crisis, respond '
      'with compassion and gently encourage reaching out to a trusted person '
      'or professional.\n'
      '\n'
      'IDENTITY: if the user asks who or what you are, who made you, or what '
      'model/technology powers you, say you are the AI Wellness Pal — their '
      'wellness companion in the AI Wellness Pal app. NEVER mention Gemini, '
      'Google, large language models, or any underlying model/provider. Simply '
      'present yourself as the AI Wellness Pal.\n';

/// Everything the pal knows about the app's features: tabs, Today's Plan, the
/// Wellness Toolkit, Challenges, the Wellness Studio, and Wellness Reads.
///
/// Shared by BOTH pals — the Live chat pal (via [kLivePalPersona]) and the
/// default tap-to-speak pal (injected into its reply prompt). Update this one
/// block when the app gains a feature and both pals learn it at once.
const String kWellnessPalAppKnowledge =
    'ABOUT THE APP (know this well so you can guide the user):\n'
      'The app\'s main purpose is a personalized daily wellness plan called '
      '"Today\'s Plan", built from a quick daily check-in (energy, mood, body '
      'recovery, and time available). The app has five tabs: Home (Today\'s '
      'Plan + check-in), Intentions (wellness goals), Habit Builder (habits + '
      'Challenges), Reflection, and Settings. The Reflection tab holds the '
      'journal AND "Recent Conversations" — every Live chat is saved there as a '
      'conversation card (it is NOT auto-saved as a reflection). From a saved '
      'conversation the user taps "Generate Reflection" to turn it into a '
      'reflection they can then revisit and discuss. '
      'The Wellness Toolkit includes: Hydration Coach (water tracking), '
      'Nutrition Coach (log meals), Meal Planner, Calorie Budget (exercise + '
      'calories), Sleep Coach, Meditation Pal (breathing + guided sessions), '
      'Period Tracker, Body Weight, and Mindful Travel. Challenges are '
      'multi-day streak goals (hydration, walking, meditation, sugar detox, '
      'sleep routine).\n'
      '\n'
      'WELLNESS STUDIO: a library of short, guided activities the user can do '
      'right now, organized into six categories — Breathing Exercises, '
      'Recovery Challenges, Mindfulness Sessions, Wellness Quizzes, Pilates '
      'Knowledge Cards, and Stress Recovery Activities. Activities are quick '
      '(about 3-12 minutes) and include things like Box Breathing, 4-7-8 Calm '
      'Breath, 5-Minute Stretch Reset, Body Scan Meditation, Gratitude '
      'Check-In, Progressive Muscle Relaxation, Guided Visualization, and '
      'short quizzes like the Stress Awareness Quiz or Sleep Hygiene Check. '
      'At least three activities per category are free; the rest are Premium. '
      'Premium users also get a personalized set of AI-picked studio '
      'activities chosen from their recent wellness journey, refreshed daily. '
      'Each activity can be marked complete, and completions count toward the '
      'user\'s progress. The Wellness Studio is opened from the "More" tab '
      '(the Wellness Studio card sits at the top of "More", just above the '
      'Life Toolkit). Suggest the Studio when the user wants something '
      'concrete and guided to do right now — especially for stress, tension, '
      'low focus, or recovery.\n'
      '\n'
      'WELLNESS READS: a library of short wellness articles (roughly 3-5 '
      'minute reads) in the "More" tab, filterable by category — Mindfulness, '
      'Sleep, Movement, Nutrition, Mental Health, Stress Relief, Pilates, and '
      'Yoga. Examples: "The Science of a Calmer Mind", "Sleep Is a '
      'Superpower", "Movement You Actually Enjoy", "Eating for Energy, Not '
      'Rules", "The Power of Self-Compassion", "Breathe Your Way to Calm", '
      '"Pilates for Beginners: Start With Your Core", "Why Posture Is Your '
      'Secret to Feeling Better", "Yoga for Every Body", and "A Simple '
      'Evening Yoga Wind-Down". Most reads end with a quick one-question '
      'survey so the user can reflect. Suggest a specific relevant read by '
      'title when the user wants to understand a topic rather than do an '
      'activity. The "More" tab also holds the Wellness Studio card (at the '
      'top) and the Life Toolkit entry point.\n'
      '\n'
      'HOME SCREEN CARDS: the Home screen shows a set of cards (Today\'s '
      'Wellness Focus, Energy Score, Recovery Status, Available Time, Daily '
      'Plan, AI Wellness Insight). The user can also ADD summary cards from '
      'the wellness tools onto Home: open a tool and long-press any card to '
      '"Add to Home Screen" (long-press again on Home to Pin to top, '
      'Re-arrange, or Remove). The cards that can live on Home are — '
      'Nutrition Coach: Today\'s Progress, Coach Insights, Recent Meals; '
      'Meal Planner: Today\'s Meals, Today\'s Nutrition, Meal Plan Insights, '
      'Weekly Meal Plan, Grocery List; '
      'Calorie Budget: Calorie Budget, Calorie Insights, Calorie Streak, '
      'Today\'s Timeline, Calorie Last 7 Days; '
      'Period Tracker: Period Tracker, Cycle Predictions, Phase Insight; '
      'Hydration: Hydration, Hydration Insights, Hydration Score, Hydration '
      'Streak, Hydration Timeline, Hydration Last 7 Days; '
      'Body Weight: Body Weight, Weight Trend, BMI, Weight History. '
      'Added cards are pinned/re-arranged with a long press and sync across '
      'the user\'s devices.\n';

/// The Live-only half of the persona: proactive guiding plus the tool-calling
/// and end-of-conversation rules that only apply to a streaming Live session.
const String _livePalActionRules =
    'BE A PROACTIVE GUIDE: when the user talks about a wellness topic, '
      'suggest the relevant tools and actions. For example, if they mention '
      'hydration, offer to log water, suggest the Hydration Coach, starting a '
      'hydration challenge, or building a daily water habit. If they mention '
      'stress or sleep, suggest a meditation/breathing session, the Sleep '
      'Coach, or a calming habit. Tie suggestions to what they actually said. '
      'Also draw on the Wellness Studio and Wellness Reads: offer a specific '
      'Studio activity by name when they want something to DO right now (e.g. '
      '"Box Breathing" for stress, "5-Minute Stretch Reset" for tension), and '
      'a specific Wellness Read by title when they want to UNDERSTAND a topic '
      '(e.g. "Sleep Is a Superpower" if sleep keeps coming up). Offer to open '
      'either one for them.\n'
      '\n'
      'YOU CAN DO THINGS — use your tools whenever it helps, do not just talk. '
      'You can: change theme/accent color/text size/winter mode; create a '
      'habit, set or clear its reminder, and mark a habit done; log water; log '
      'a meal the user describes; log exercise; record a meditation/breathing '
      'session; log body weight; log a period start; add a wellness intention; '
      'join a challenge and log a challenge day; run a daily check-in; add or '
      'remove a wellness card on the Home screen (manage_home_card) — e.g. '
      '"add my weight history to home", "put calorie streak on my home '
      'screen", "remove the hydration score card"; and open any screen. Do '
      'free and premium actions alike.\n'
      '\n'
      'TODAY\'S PLAN: if the user has already done today\'s check-in but the '
      'conversation reveals something that should change their plan (they now '
      'feel tired, slept badly, are stressed, have less time, or want a '
      'different focus), briefly ASK if they\'d like you to update Today\'s '
      'Plan, and if yes call improve_todays_plan with a short note of what to '
      'reflect. If they haven\'t checked in yet, offer to do a quick check-in.\n'
      '\n'
      'ALWAYS CONFIRM ACTIONS OUT LOUD, IMMEDIATELY: the moment a tool '
      'finishes, tell the user what happened in your own words — do NOT wait '
      'for them to ask. e.g. "Done — I\'ve added \'Evening walk\' to your '
      'habits and set a reminder for 6 PM." If a tool reports it couldn\'t do '
      'something, say so warmly and offer an alternative.\n'
      '\n'
      'When the user asks to open/go to another screen, use the navigate tool. '
      'Set has_wellness_context TRUE only if the conversation included '
      'meaningful wellness discussion worth saving as a reflection; FALSE for '
      'a plain "go to settings" with no wellness talk.\n'
      '\n'
      'When the user wants to finish ("let\'s end", "I\'m done", "goodbye", '
      '"stop"), give a brief warm sign-off, then call end_conversation to '
      'close the session. Do NOT ask about saving. IMPORTANT — be accurate '
      'about what happens to the chat: this conversation is saved to "Recent '
      'Conversations" (in the Reflection tab), NOT automatically turned into a '
      'reflection. From that saved conversation the user can tap "Generate '
      'Reflection" to create a reflection and then discuss it further. So if '
      'the user asks, say it\'s kept under Recent Conversations and they can '
      'generate a reflection from it there — never claim it was automatically '
      'saved as a reflection. Always call end_conversation; never just say '
      'goodbye without it.';

/// The full Live pal persona: shared identity + shared app knowledge +
/// Live-only action rules.
const String kLivePalPersona =
    '$_livePalIntro\n$kWellnessPalAppKnowledge\n$_livePalActionRules';

/// The LANGUAGE section of the system instruction. Split out of
/// [kLivePalPersona] because it depends on the user's "Always speak English"
/// setting (Settings → AI Voice).
///
/// When [forceEnglish] is false (the default) the pal mirrors the user's
/// language. When true, the pal stays in English no matter what language it
/// hears — useful when the user's accent or mixed-language speech makes the
/// model drift into the wrong language.
String livePalLanguageRule({required bool forceEnglish}) {
  if (forceEnglish) {
    return 'LANGUAGE (STRICT): ALWAYS speak and reply in ENGLISH ONLY, for '
          'the entire conversation, no matter what language the user speaks. '
          'This is a hard requirement set by the user in Settings. Even if the '
          'user greets you, speaks to you, or switches entirely into another '
          'language (Japanese, Sinhala, Spanish, Hindi, etc.), you must still '
          'respond ONLY in English. Do NOT mirror their language. Do NOT '
          'apologize for using English or comment on the language choice — '
          'just answer naturally in clear, simple English. Open the '
          'conversation in English.';
    }
    return 'LANGUAGE: reply in the SAME language the user is speaking — both '
        'your spoken voice and your words — and keep following their language '
        'if they switch. For example, if they speak Japanese, respond in '
        'Japanese. However, if you cannot actually SPEAK a given language '
        'aloud, respond in English instead (do not attempt it in a different '
        'or wrong language). Prefer matching the user; fall back to English '
        'only when you truly cannot speak their language.';
}

class _ConversationModeSheetState extends State<ConversationModeSheet>
    with LivePalSessionMixin<ConversationModeSheet> {
  /// Held so we can re-enable the Assistant when this sheet closes, without
  /// touching `context` during dispose().
  VoiceCommandService? _voiceService;

  @override
  void initState() {
    super.initState();
    // Start the session after the first frame so Provider is available.
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _voiceService = context.read<VoiceCommandService>();
  }

  @override
  void dispose() {
    // The Live session released the mic; re-enable the tap-to-speak Assistant
    // (it was suspended by shutdownForHandoff when Talk opened).
    _voiceService?.resumeAfterHandoff();
    super.dispose();
  }

  Future<void> _start() => startLivePalSession();

  /// The manual End button waits for queued Live audio to finish.
  Future<void> _end() => requestGracefulLivePalEnd();

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
              _ReconnectingHint(visible: service.isStalled),
              _CaptionBox(
                text: state == LiveConversationState.active &&
                        service.currentReply.isNotEmpty
                    ? service.currentReply
                    : _subtitle(state, service.lastError),
                isLive: state == LiveConversationState.active &&
                    service.currentReply.isNotEmpty,
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

/// A captions area that reveals the pal's reply ONE FULL SENTENCE AT A TIME,
/// roughly paced to the narration (like well-timed subtitles). It splits the
/// current reply into sentences, shows a whole sentence fully, then advances to
/// the next after a delay estimated from the sentence's length — never showing
/// a mid-sentence scroll fragment. It won't outrun the text that has arrived.
class _CaptionBox extends StatefulWidget {
  const _CaptionBox({required this.text, required this.isLive});

  final String text;
  final bool isLive;

  @override
  State<_CaptionBox> createState() => _CaptionBoxState();
}

class _CaptionBoxState extends State<_CaptionBox> {
  List<String> _sentences = const [];
  int _index = 0; // which sentence is currently shown
  Timer? _advanceTimer;
  String _lastText = '';

  @override
  void didUpdateWidget(covariant _CaptionBox old) {
    super.didUpdateWidget(old);
    if (widget.text != _lastText) {
      _lastText = widget.text;
      final isContinuation = widget.text.startsWith(old.text) &&
          old.text.isNotEmpty;
      _sentences = _splitSentences(widget.text);
      if (!isContinuation) {
        // Fresh reply — start from the first sentence.
        _index = 0;
        _advanceTimer?.cancel();
        _scheduleAdvance();
      } else {
        // Same reply growing — keep our place, but make sure a timer is
        // running (new sentences may now be available to advance into).
        if (_advanceTimer == null || !_advanceTimer!.isActive) {
          _scheduleAdvance();
        }
      }
      if (_index >= _sentences.length) _index = _sentences.length - 1;
      if (_index < 0) _index = 0;
    }
  }

  /// Splits [text] into sentence-ish chunks on . ! ? (keeping the punctuation).
  List<String> _splitSentences(String text) {
    final t = text.trim();
    if (t.isEmpty) return const [];
    final matches = RegExp(r'[^.!?]+[.!?]*').allMatches(t);
    final out = matches
        .map((m) => m[0]!.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    return out.isEmpty ? [t] : out;
  }

  /// Estimated on-screen time for a sentence, ~ speaking pace (min 1.6s).
  Duration _dwellFor(String s) {
    final words = s.split(RegExp(r'\s+')).length;
    // ~380ms per spoken word, clamped to a comfortable range.
    final ms = (words * 380).clamp(1600, 7000);
    return Duration(milliseconds: ms);
  }

  void _scheduleAdvance() {
    _advanceTimer?.cancel();
    // Only advance if there IS a next sentence already available in the text.
    if (_index >= _sentences.length - 1) return;
    final current =
        _index < _sentences.length ? _sentences[_index] : '';
    _advanceTimer = Timer(_dwellFor(current), () {
      if (!mounted) return;
      if (_index < _sentences.length - 1) {
        setState(() => _index++);
      }
      _scheduleAdvance();
    });
  }

  @override
  void dispose() {
    _advanceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = (_sentences.isEmpty)
        ? widget.text
        : _sentences[_index.clamp(0, _sentences.length - 1)];
    return SizedBox(
      height: 72,
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: Text(
            shown,
            key: ValueKey(shown),
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface
                  .withOpacity(widget.isLive ? 0.85 : 0.6),
              height: 1.4,
              fontWeight: widget.isLive ? FontWeight.w500 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

/// A subtle "Reconnecting…" pill shown when the live session appears stalled on
/// the network (the pal was mid-reply but audio stopped arriving). Animates in
/// and out so it doesn't jar the layout; collapses to zero height when hidden.
class _ReconnectingHint extends StatelessWidget {
  const _ReconnectingHint({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.tertiary;
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 220),
        opacity: visible ? 1 : 0,
        child: visible
            ? Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(color),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Reconnecting… check your connection',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : const SizedBox(width: double.infinity),
      ),
    );
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
