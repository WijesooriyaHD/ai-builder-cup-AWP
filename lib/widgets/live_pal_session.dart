import 'dart:async';

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

    // TEMP(test): pass isPremium: true unconditionally (Premium gate disabled).
    // Restore with `isPremium: context.read<AppState>().isPro`.
    await service.start(isPremium: true, systemInstruction: systemInstruction);
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
    if (popHostOnSessionEnd) {
      navigator.pop();
    }
    if (navRequest != null) {
      applyLiveNav(navRequest, nav, rootNavigator);
      // A navigation request always means we're leaving; close the host even if
      // it would normally stay open.
      if (!popHostOnSessionEnd && navigator.canPop()) navigator.pop();
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
      case LiveNavDestination.wellnessReads:
        // Wellness Reads lives on the Home screen's "More" sub-tab.
        nav.goToHomeSubTab(1);
        return;
      default:
        break;
    }
    // Pushed full-screen routes.
    final screen = screenForLiveDestination(dest);
    if (screen != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        rootNavigator.push(MaterialPageRoute(builder: (_) => screen));
      });
    }
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
