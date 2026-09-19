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
      'friend — natural, brief, human, with contractions. Keep replies short '
      '(usually 1-3 sentences) since they are spoken aloud, and end with a '
      'gentle question when it helps. Be positive; never shame or alarm the '
      'user. Only suggest safe, gentle, healthy actions. No medical, legal, or '
      'financial advice; avoid clinical language. For signs of crisis, respond '
      'with compassion and gently encourage reaching out to a trusted person '
      'or professional.\n'
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

    // TEMP(test): pass isPremium: true unconditionally (Premium gate disabled).
    // Restore with `isPremium: context.read<AppState>().isPro`.
    await service.start(isPremium: true, systemInstruction: _persona);
  }

  /// Called (from the tool bridge) when the pal wants to navigate somewhere.
  /// The conversation is saved automatically; then we navigate.
  void _onNavRequested(LiveNavRequest request) {
    if (!mounted) return;
    _finalize(navRequest: request);
  }

  /// Called (from the tool bridge) when the pal ENDS the conversation.
  void _onEndRequested(LiveEndRequest request) {
    if (!mounted) return;
    _finalize();
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
