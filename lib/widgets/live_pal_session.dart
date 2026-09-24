import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
import '../screens/wellness_studio_screen.dart';
import '../services/app_navigation_service.dart';
import '../services/conversation_store.dart';
import '../services/home_tool_cards_service.dart';
import '../services/live_conversation_service.dart';
import '../services/live_tool_bridge.dart';
import 'conversation_mode_sheet.dart' show kLivePalPersona, livePalLanguageRule;

/// Builds a short "what I know about you right now" block appended to the
/// persona, so the pal has memory of the user's profile, today's plan/
/// check-in, recent plans, active habits, and intentions.
///
/// Top-level (rather than a widget method) so every Live entry point seeds the
/// pal with identical context.
String buildLivePalContextMemory(BuildContext context) {
  final appState = context.read<AppState>();
  final plan = context.read<WellnessPlanState>();
  final checkIn = context.read<CheckInState>();
  final habits = context.read<HabitBuilderState>();

  final b = StringBuffer('WHAT YOU KNOW ABOUT THIS USER RIGHT NOW '
      '(use it naturally; do not read it back verbatim):\n');

  // Prefer the first name for a warm, human feel — the pal should sprinkle it
  // in the way a friend would rather than every sentence.
  final firstName = _resolveUserFirstName();
  if (firstName != null) {
    b.writeln('- The user\'s first name is $firstName. Address them by name '
        'in greetings, encouragement, and moments of care — but do not use '
        'it in every sentence, and avoid sounding scripted.');
  }

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

  final intentions = appState.intentions.map((i) => i.title).take(4).toList();
  if (intentions.isNotEmpty) {
    b.writeln('- Wellness intentions: ${intentions.join(', ')}.');
  }

  return b.toString().trim();
}

/// Resolves a friendly first name for the current user, or null when nothing
/// usable is available. Prefers Firebase Auth's `displayName` (which the app
/// keeps in sync when the user edits their profile), and falls back to the
/// capitalised local part of the email so the pal at least has something warmer
/// than "there" to say. Kept synchronous so `buildLivePalContextMemory` never
/// waits on I/O — the value the Live session needs is already in memory.
String? _resolveUserFirstName() {
  final user = FirebaseAuth.instance.currentUser;
  final display = user?.displayName?.trim();
  if (display != null && display.isNotEmpty) {
    // First whitespace-separated token: "Viraj Patel" → "Viraj". Also handles
    // single-word display names cleanly.
    return display.split(RegExp(r'\s+')).first;
  }
  final email = user?.email;
  if (email != null && email.contains('@')) {
    // Strip out address separators so "first.last" reads as "First" rather
    // than "First.last" or "First_last".
    final prefix = email.split('@').first.split(RegExp(r'[._\-+]')).first;
    if (prefix.isNotEmpty) {
      return prefix[0].toUpperCase() + prefix.substring(1);
    }
  }
  return null;
}

/// Shared orchestration for hosting a Gemini Live "pal" conversation inside a
/// widget: wires the tool bridge, builds the system instruction, starts the
/// session, and handles teardown (auto-saving the transcript as a conversation
/// card) plus any navigation the pal requested.
///
/// Two hosts mix this in:
///  - `VoiceAssistantSheet` (the "Wellness Pal" sheet) — stays open after the
///    session ends so the user can tap the orb to start a new one.
///  - `ConversationModeSheet` (legacy standalone sheet) — pops on end.
///
/// Hosts control that difference via [popHostOnSessionEnd].
mixin LivePalSessionMixin<T extends StatefulWidget> on State<T> {
  /// Whether teardown should pop the hosting route. Sheets that exist ONLY to
  /// run the conversation return true; hosts that remain useful afterwards
  /// (offering a restart) return false.
  bool get popHostOnSessionEnd => true;

  /// Called right after the session has been torn down and saved, before any
  /// navigation. Hosts override to refresh their own UI (e.g. re-show the orb).
  void onLiveSessionEnded() {}

  /// Guards against re-entrancy: the End button, a pal navigate(), and a pal
  /// end_conversation() can all trigger teardown; only run it once per session.
  bool _ending = false;

  /// True while a teardown is in flight or has completed for this session.
  bool get isEndingLiveSession => _ending;

  /// Wires tools + system instruction and starts the Live session.
  Future<void> startLivePalSession() async {
    final service = context.read<LiveConversationService>();

    // A fresh session can be started after a previous one ended.
    _ending = false;

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
      homeCards: context.read<HomeToolCardsService>(),
      onNavigate: _onNavRequested,
      onEndConversation: _onEndRequested,
    );
    service.tools = bridge.tools;
    service.onToolCall = bridge.handleToolCall;
    // The Live model is unreliable at calling end_conversation for spoken
    // goodbyes, so also end when the user's transcribed speech says so.
    service.onUserEndIntent = () {
      if (mounted) finalizeLivePalSession();
    };

    // Seed the pal with the user's current context (profile + plan + habits)
    // so it remembers who it's talking to and what's going on today. The
    // language rule is injected separately because it depends on the user's
    // "Always speak English" setting (Settings → AI Voice).
    final forceEnglish = context.read<AppState>().forceEnglishVoice;
    final systemInstruction = '$kLivePalPersona\n\n'
        '${livePalLanguageRule(forceEnglish: forceEnglish)}\n\n'
        '${buildLivePalContextMemory(context)}';

    // The pal's voice is fixed when the session is created, so a change in
    // Settings applies to the NEXT conversation.
    final voiceName = context.read<AppState>().livePalVoice;

    // TEMP(test): pass isPremium: true unconditionally (Premium gate disabled).
    // Restore with `isPremium: context.read<AppState>().isPro`.
    await service.start(
      isPremium: true,
      systemInstruction: systemInstruction,
      voiceName: voiceName,
      openingPrompt: _buildOpeningGreetingPrompt(),
    );
  }

  /// Builds the one-off prompt that makes the pal open with a warm, spoken
  /// greeting — by name when we know it and matched to the time of day. It's a
  /// SYSTEM-EVENT instruction (not words the user said), kept short so the pal
  /// greets and then hands the floor straight back to the user.
  String _buildOpeningGreetingPrompt() {
    final name = _resolveUserFirstName();
    final hour = DateTime.now().hour;
    final partOfDay = hour < 12
        ? 'morning'
        : (hour < 17 ? 'afternoon' : 'evening');
    final nameClause = name != null
        ? 'Greet them by name ($name).'
        : 'Greet them warmly.';
    final example =
        name != null ? '"Hi $name, how are you today?"' : '"Hi, how are you today?"';
    return '[SYSTEM EVENT: The conversation just opened. $nameClause Give a '
        'short, warm spoken greeting suited to the $partOfDay and ask how '
        'they are today (for example, $example). Keep it to one sentence, '
        'sound natural (not scripted), then stop and wait for their reply. Do '
        'not imply the user said anything yet.]';
  }

  /// Called (from the tool bridge) when the pal wants to navigate somewhere.
  /// The conversation is saved automatically; then we navigate.
  void _onNavRequested(LiveNavRequest request) {
    if (!mounted) return;
    finalizeLivePalSession(navRequest: request);
  }

  /// Called (from the tool bridge) when the pal ENDS the conversation via the
  /// `end_conversation` tool. Route through [LiveConversationService.deferEnd]
  /// so we wait for the pal's spoken goodbye to actually finish playing out of
  /// the speaker before tearing the session down. The service will fire
  /// `onUserEndIntent` when the audio has drained, which routes to
  /// [finalizeLivePalSession].
  void _onEndRequested(LiveEndRequest request) {
    if (!mounted) return;
    if (_ending) return;
    context.read<LiveConversationService>().deferEnd();
  }

  /// Requests an end without cutting off audio already queued for playback.
  /// [LiveConversationService.deferEnd] waits for the current model turn (or a
  /// pal sign-off) to drain, then calls the existing end callback which runs
  /// [finalizeLivePalSession] exactly once.
  Future<void> requestGracefulLivePalEnd() async {
    if (_ending) return;
    context.read<LiveConversationService>().deferEnd();
  }

  /// Unified teardown: stop the session, auto-save the conversation as a card
  /// (max 3, FIFO) with NO prompt/dialog/voice ask, then optionally pop and
  /// navigate. Turning a conversation into a reflection happens later, from the
  /// card's "Generate Reflection" button.
  Future<void> finalizeLivePalSession({LiveNavRequest? navRequest}) async {
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
    onLiveSessionEnded();

    if (navRequest != null) {
      // A navigation request always means we're leaving the sheet AND any
      // pushed inner page. applyLiveNav pops the root navigator back to the tab
      // scaffold (clearing the sheet + any pushed page in one shot), then
      // switches tabs or pushes the destination. So we must NOT pop the host
      // separately here — that's what applyLiveNav's popUntil already does.
      applyLiveNav(navRequest, nav, rootNavigator);
    } else if (popHostOnSessionEnd) {
      navigator.pop();
    }
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
  void applyLiveNav(
    LiveNavRequest request,
    AppNavigationService nav,
    NavigatorState rootNavigator,
  ) {
    final dest = request.destination;
    // Bottom tabs. A tab switch only changes what MainWrapper shows — it does
    // NOT dismiss any full-screen route pushed ON TOP of MainWrapper (e.g. the
    // Hydration Coach page). If we just switch tabs while such a page is up,
    // the user keeps seeing that page and the pal appears to "do nothing".
    // So for every tab destination we first pop back to the tab scaffold.
    switch (dest) {
      case LiveNavDestination.home:
      case LiveNavDestination.checkIn:
        _popToTabScaffold(rootNavigator);
        nav.goToTab(AppTab.home);
        return;
      case LiveNavDestination.intentions:
        _popToTabScaffold(rootNavigator);
        nav.goToTab(AppTab.intentions);
        return;
      case LiveNavDestination.habitBuilder:
        _popToTabScaffold(rootNavigator);
        nav.goToTab(AppTab.habitBuilder);
        return;
      case LiveNavDestination.reflection:
        _popToTabScaffold(rootNavigator);
        nav.goToTab(AppTab.reflection);
        return;
      case LiveNavDestination.wellnessReads:
        // Wellness Reads lives on the Home screen's "More" sub-tab.
        _popToTabScaffold(rootNavigator);
        nav.goToHomeSubTab(1);
        return;
      default:
        break;
    }
    // Pushed full-screen routes. Pop any existing pushed page back to the tab
    // scaffold FIRST, so navigating (say) Hydration → Nutrition replaces the
    // current inner page instead of stacking a second one behind the sheet.
    final screen = screenForLiveDestination(dest);
    if (screen != null) {
      _popToTabScaffold(rootNavigator);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        rootNavigator.push(MaterialPageRoute(builder: (_) => screen));
      });
    }
  }

  /// Pops every full-screen route pushed on top of the tab scaffold
  /// ([MainWrapper], which is always the first route on the root navigator),
  /// so a subsequent tab switch or push is actually visible to the user.
  /// Safe when nothing is pushed — `popUntil` simply stops at the first route.
  void _popToTabScaffold(NavigatorState rootNavigator) {
    rootNavigator.popUntil((route) => route.isFirst);
  }

  /// Maps a pushed-screen destination to its widget (tabs return null).
  Widget? screenForLiveDestination(LiveNavDestination dest) {
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
      case LiveNavDestination.wellnessStudio:
        return const WellnessStudioScreen();
      default:
        return null;
    }
  }
}
