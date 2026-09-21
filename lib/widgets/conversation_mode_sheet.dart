import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/feature_flags.dart';
import '../features/calorie_budget/presentation/calorie_budget_screen.dart';
import '../features/calorie_budget/presentation/calorie_budget_state.dart';
import '../features/habit_builder/presentation/challenge_state.dart';
import '../features/habit_builder/presentation/habit_builder_state.dart';
import '../features/hydration/presentation/hydration_coach_screen.dart';
import '../features/hydration/presentation/hydration_state.dart';
import '../features/meal_planner/presentation/meal_planner_screen.dart';
import '../features/meditation/presentation/breathing_screen.dart';
import '../features/meditation/presentation/guided_meditation_screen.dart';
import '../features/meditation/presentation/meditation_home_screen.dart';
import '../features/meditation/presentation/meditation_state.dart';
import '../features/nutrition/presentation/nutrition_coach_screen.dart';
import '../features/nutrition/presentation/nutrition_state.dart';
import '../features/sleep/presentation/sleep_coach_screen.dart';
import '../models/live_conversation_record.dart';
import '../providers/app_state.dart';
import '../providers/check_in_state.dart';
import '../providers/wellness_plan_state.dart';
import '../screens/period_tracker_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/travel_screen.dart';
import '../screens/weight_tracker_screen.dart';
import '../services/app_navigation_service.dart';
import '../services/conversation_store.dart';
import '../services/live_conversation_service.dart';
import '../services/live_tool_bridge.dart';
import '../services/voice_command_service.dart';

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

class _ConversationModeSheetState extends State<ConversationModeSheet> {
  /// Warm, wellness-pal persona for the Live session — with full knowledge of
  /// the app and its tools so the pal can guide AND act.
  static const String _persona =
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
      'present yourself as the AI Wellness Pal.\n'
      '\n'
      'ABOUT THE APP (know this well so you can guide the user):\n'
      'The app\'s main purpose is a personalized daily wellness plan called '
      '"Today\'s Plan", built from a quick daily check-in (energy, mood, body '
      'recovery, and time available). The app has five tabs: Home (Today\'s '
      'Plan + check-in), Intentions (wellness goals), Habit Builder (habits + '
      'Challenges), Reflection (journal + saved conversations), and Settings. '
      'The Wellness Toolkit includes: Hydration Coach (water tracking), '
      'Nutrition Coach (log meals), Meal Planner, Calorie Budget (exercise + '
      'calories), Sleep Coach, Meditation Pal (breathing + guided sessions), '
      'Period Tracker, Body Weight, and Mindful Travel. Challenges are '
      'multi-day streak goals (hydration, walking, meditation, sugar detox, '
      'sleep routine).\n'
      '\n'
      'BE A PROACTIVE GUIDE: when the user talks about a wellness topic, '
      'suggest the relevant tools and actions. For example, if they mention '
      'hydration, offer to log water, suggest the Hydration Coach, starting a '
      'hydration challenge, or building a daily water habit. If they mention '
      'stress or sleep, suggest a meditation/breathing session, the Sleep '
      'Coach, or a calming habit. Tie suggestions to what they actually said.\n'
      '\n'
      'YOU CAN DO THINGS — use your tools whenever it helps, do not just talk. '
      'You can: change theme/accent color/text size/winter mode; create a '
      'habit, set or clear its reminder, and mark a habit done; log water; log '
      'a meal the user describes; log exercise; record a meditation/breathing '
      'session; log body weight; log a period start; add a wellness intention; '
      'join a challenge and log a challenge day; run a daily check-in; and '
      'open any screen. Do free and premium actions alike.\n'
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
      'close the session. Do NOT ask about saving — the conversation is kept '
      'automatically and can become a reflection later. Always call '
      'end_conversation; never just say goodbye without it.';

  /// The LANGUAGE section of the system instruction. Split out of [_persona]
  /// because it depends on the user's "Always speak English" setting
  /// (Settings → AI Voice).
  ///
  /// When [forceEnglish] is false (the default) the pal mirrors the user's
  /// language. When true, the pal stays in English no matter what language it
  /// hears — useful when the user's accent or mixed-language speech makes the
  /// model drift into the wrong language.
  static String _languageRule({required bool forceEnglish}) {
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

  Future<void> _start() async {
    final service = context.read<LiveConversationService>();

    // Wire tool calling so the pal can DO everything the tap-to-speak Assistant
    // can (appearance, habits, water, intentions, plan, check-in, navigation),
    // reusing the same providers.
    final bridge = LiveToolBridge(
      habits: context.read<HabitBuilderState>(),
      appState: context.read<AppState>(),
      navService: context.read<AppNavigationService>(),
      hydration: context.read<HydrationState>(),
      checkIn: context.read<CheckInState>(),
      plan: context.read<WellnessPlanState>(),
      nutrition: context.read<NutritionState>(),
      calorieBudget: context.read<CalorieBudgetState>(),
      meditation: context.read<MeditationState>(),
      challenges: context.read<ChallengeState>(),
      onNavigate: _onNavRequested,
      onEndConversation: _onEndRequested,
    );
    service.tools = bridge.tools;
    service.onToolCall = bridge.handleToolCall;
    // The Live model is unreliable at calling end_conversation for spoken
    // goodbyes, so also end when the user's transcribed speech says so.
    service.onUserEndIntent = () {
      if (mounted) _finalize();
    };

    // Seed the pal with the user's current context (profile + plan + habits)
    // so it remembers who it's talking to and what's going on today. The
    // language rule is injected separately because it depends on the user's
    // "Always speak English" setting (Settings → AI Voice).
    final forceEnglish = context.read<AppState>().forceEnglishVoice;
    final systemInstruction = '$_persona\n\n'
        '${_languageRule(forceEnglish: forceEnglish)}\n\n'
        '${_buildContextMemory()}';

    // TEMP(test): pass isPremium: true unconditionally (Premium gate disabled).
    // Restore with `isPremium: context.read<AppState>().isPro`.
    await service.start(isPremium: true, systemInstruction: systemInstruction);
  }

  /// Builds a short "what I know about you right now" block appended to the
  /// persona, so the pal has memory of the user's profile, today's plan/
  /// check-in, recent plans, active habits, and intentions.
  String _buildContextMemory() {
    final appState = context.read<AppState>();
    final plan = context.read<WellnessPlanState>();
    final checkIn = context.read<CheckInState>();
    final habits = context.read<HabitBuilderState>();

    final b = StringBuffer('WHAT YOU KNOW ABOUT THIS USER RIGHT NOW '
        '(use it naturally; do not read it back verbatim):\n');

    b.writeln('- Membership: ${appState.isPro ? 'Premium' : 'Free'}.');

    if (appState.preferredMethods.isNotEmpty) {
      b.writeln('- Preferred wellness approaches: '
          '${appState.preferredMethods.join(', ')}.');
    }

    final todays = plan.todaysPlan;
    final todaysCheckIn = checkIn.todaysCheckIn;
    if (todaysCheckIn == null) {
      b.writeln('- They have NOT done today\'s check-in yet.');
    } else {
      final e = todaysCheckIn.energyScore;
      b.writeln('- Today\'s check-in is done'
          '${e != null ? ' (energy $e/5)' : ''}.');
    }
    if (todays != null) {
      b.writeln('- Today\'s Plan focus: "${todays.todaysFocus}" '
          '(${todays.completedActionsCount}/${todays.actions.length} actions done).');
    } else {
      b.writeln('- No Today\'s Plan generated yet.');
    }

    final recent = plan.recentPlans.take(3).map((p) => p.todaysFocus).toList();
    if (recent.isNotEmpty) {
      b.writeln('- Recent plan focuses: ${recent.join('; ')}.');
    }

    final activeHabits =
        habits.habits.where((h) => h.isActive).map((h) => h.title).toList();
    if (activeHabits.isNotEmpty) {
      b.writeln('- Active habits: ${activeHabits.take(6).join(', ')}.');
    }

    final intentions =
        appState.intentions.map((i) => i.title).take(4).toList();
    if (intentions.isNotEmpty) {
      b.writeln('- Wellness intentions: ${intentions.join(', ')}.');
    }

    return b.toString().trim();
  }

  /// Called (from the tool bridge) when the pal wants to navigate somewhere.
  /// The conversation is saved automatically; then we navigate.
  void _onNavRequested(LiveNavRequest request) {
    if (!mounted) return;
    _finalize(navRequest: request);
  }

  /// Called (from the tool bridge) when the pal ENDS the conversation via the
  /// `end_conversation` tool. Route through [LiveConversationService.deferEnd]
  /// so we wait for the pal's spoken goodbye to actually finish playing out of
  /// the speaker before tearing the session down. The service will fire
  /// `onUserEndIntent` when the audio has drained, which routes to [_finalize].
  void _onEndRequested(LiveEndRequest request) {
    if (!mounted) return;
    if (_ending) return;
    context.read<LiveConversationService>().deferEnd();
  }

  /// Guards against re-entrancy: the End button, a pal navigate(), and a pal
  /// end_conversation() can all trigger teardown; only run it once.
  bool _ending = false;

  /// The manual End button.
  Future<void> _end() => _finalize();

  /// Unified teardown: stop the session, auto-save the conversation as a card
  /// (max 3, FIFO) with NO prompt/dialog/voice ask, then pop and optionally
  /// navigate. Turning a conversation into a reflection happens later, from the
  /// card's "Generate Reflection" button.
  Future<void> _finalize({LiveNavRequest? navRequest}) async {
    if (_ending) return;
    _ending = true;

    final service = context.read<LiveConversationService>();
    final store = context.read<ConversationStore>();
    final nav = context.read<AppNavigationService>();
    final navigator = Navigator.of(context);
    final rootNavigator = Navigator.of(context, rootNavigator: true);

    // stop() flushes the final turn, so read the transcript after it.
    await service.stop();
    final turns = service.transcript;
    final hasRealTranscript =
        service.hasTranscript && service.transcriptText.trim().isNotEmpty;

    // Auto-save the conversation as a card (fire-and-forget; the store caps at
    // 3, persists to Firestore, and generates an AI title in the background —
    // we pass a quick heuristic title as the immediate fallback).
    if (hasRealTranscript) {
      final record = LiveConversationRecord(
        title: _titleFor(turns),
        turns: turns
            .map((t) => ConversationTurn(
                  isUser: t.role == LiveSpeaker.user,
                  text: t.text,
                ))
            .toList(),
      );
      unawaited(store.add(record, generateTitle: true));
    }

    if (!mounted) return;
    navigator.pop();
    if (navRequest != null) _applyNav(navRequest, nav, rootNavigator);
  }

  /// A short card title from the first thing the user said, else a dated label.
  String _titleFor(List<LiveTranscriptTurn> turns) {
    final firstUser = turns.firstWhere(
      (t) => t.role == LiveSpeaker.user && t.text.trim().isNotEmpty,
      orElse: () => const LiveTranscriptTurn(LiveSpeaker.user, ''),
    );
    final text = firstUser.text.trim();
    if (text.isNotEmpty) {
      final words = text.split(RegExp(r'\s+'));
      final short = words.take(6).join(' ');
      return words.length > 6 ? '$short…' : short;
    }
    final now = DateTime.now();
    return 'Talk on ${now.month}/${now.day}';
  }

  /// Applies a [LiveNavRequest] after the session has ended: bottom tabs via
  /// [AppNavigationService], pushed screens via the root navigator.
  void _applyNav(
    LiveNavRequest request,
    AppNavigationService nav,
    NavigatorState rootNavigator,
  ) {
    final dest = request.destination;
    // Bottom tabs.
    switch (dest) {
      case LiveNavDestination.home:
      case LiveNavDestination.checkIn:
        nav.goToTab(AppTab.home);
        return;
      case LiveNavDestination.intentions:
        nav.goToTab(AppTab.intentions);
        return;
      case LiveNavDestination.habitBuilder:
        nav.goToTab(AppTab.habitBuilder);
        return;
      case LiveNavDestination.reflection:
        nav.goToTab(AppTab.reflection);
        return;
      default:
        break;
    }
    // Pushed full-screen routes.
    final screen = _screenForDestination(dest);
    if (screen != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        rootNavigator.push(MaterialPageRoute(builder: (_) => screen));
      });
    }
  }

  /// Maps a pushed-screen destination to its widget (tabs return null).
  Widget? _screenForDestination(LiveNavDestination dest) {
    switch (dest) {
      case LiveNavDestination.settings:
        return const SettingsScreen();
      case LiveNavDestination.nutrition:
        return const NutritionCoachScreen();
      case LiveNavDestination.mealPlanner:
        return const MealPlannerScreen();
      case LiveNavDestination.calorieBudget:
        return const CalorieBudgetScreen();
      case LiveNavDestination.hydration:
        return const HydrationCoachScreen();
      case LiveNavDestination.sleep:
        return const SleepCoachEntry();
      case LiveNavDestination.meditation:
        return const MeditationHomeScreen();
      case LiveNavDestination.periodTracker:
        return const PeriodTrackerScreen();
      case LiveNavDestination.weightTracker:
        return const WeightTrackerScreen();
      case LiveNavDestination.mindfulTravel:
        return const TravelScreen();
      case LiveNavDestination.breathing:
        return const BreathingScreen();
      case LiveNavDestination.meditationSession:
        return const GuidedMeditationScreen();
      default:
        return null;
    }
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
