import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';

import '../models/voice_command.dart';
import '../models/check_in.dart';
import '../models/wellness_enums.dart';
import '../providers/app_state.dart';
import '../providers/check_in_state.dart';
import '../providers/wellness_plan_state.dart';
import '../services/ai_service.dart';
import '../services/voice_command_service.dart';
import '../services/app_navigation_service.dart';
import '../services/toolkit_context_builder.dart';
import 'voice_orb.dart';

// Tool + tab screens reachable by voice.
import '../screens/settings_screen.dart';
import '../features/nutrition/presentation/nutrition_coach_screen.dart';
import '../features/meal_planner/presentation/meal_planner_screen.dart';
import '../features/calorie_budget/presentation/calorie_budget_screen.dart';
import '../features/hydration/presentation/hydration_coach_screen.dart';
import '../features/hydration/presentation/hydration_state.dart';
import '../features/sleep/presentation/sleep_coach_screen.dart';
import '../features/meditation/presentation/meditation_home_screen.dart';
import '../features/meditation/presentation/breathing_screen.dart';
import '../features/meditation/presentation/guided_meditation_screen.dart';
import '../screens/period_tracker_screen.dart';
import '../screens/weight_tracker_screen.dart';
import '../screens/travel_screen.dart';

/// A bottom sheet that houses the voice assistant with the Siri-style orb,
/// conversation messages, and real-time speech transcription.
class VoiceAssistantSheet extends StatefulWidget {
  const VoiceAssistantSheet({super.key});

  @override
  State<VoiceAssistantSheet> createState() => _VoiceAssistantSheetState();
}

class _VoiceAssistantSheetState extends State<VoiceAssistantSheet> {
  late VoiceCommandService _voiceService;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _debugInputController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _voiceService = Provider.of<VoiceCommandService>(context, listen: false);
    _voiceService.addListener(_onServiceUpdate);
    // Honor the user's saved voice preference and Premium status for this
    // session (the assistant tailors upsell hints for free users).
    final appState = Provider.of<AppState>(context, listen: false);
    _voiceService.setVoice(appState.aiVoice);
    _voiceService.isPremium = appState.isPro;
    _voiceService.initialize().then((_) {
      // Auto-start listening when sheet opens
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) _voiceService.startListening();
      });
    });
  }

  @override
  void dispose() {
    _voiceService.removeListener(_onServiceUpdate);
    _scrollController.dispose();
    _debugInputController.dispose();
    super.dispose();
  }

  /// Submits the typed debug phrase through the voice pipeline.
  void _submitDebugText() {
    final text = _debugInputController.text.trim();
    if (text.isEmpty) return;
    _debugInputController.clear();
    _voiceService.submitTextInput(text);
  }

  void _onServiceUpdate() {
    if (!mounted) return;
    setState(() {});

    // Auto-scroll to bottom when new messages arrive
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });

    // Handle the last command
    _handleLastCommand();
  }

  void _handleLastCommand() {
    final command = _voiceService.lastCommand;
    if (command == null) return;
    _voiceService.clearLastCommand();

    final appState = context.read<AppState>();

    switch (command.type) {
      case VoiceCommandType.setThemeDark:
        appState.setThemeMode(ThemeMode.dark);
        break;
      case VoiceCommandType.setThemeLight:
        appState.setThemeMode(ThemeMode.light);
        break;
      case VoiceCommandType.setAccentColor:
        final colorValue = command.params['color'] as int?;
        if (colorValue != null) {
          appState.setThemeColor(Color(colorValue));
        }
        break;
      case VoiceCommandType.increaseTextSize:
        appState.setTextScaleFactor(appState.textScaleFactor + 0.1);
        break;
      case VoiceCommandType.decreaseTextSize:
        appState.setTextScaleFactor(appState.textScaleFactor - 0.1);
        break;
      case VoiceCommandType.resetTextSize:
        appState.setTextScaleFactor(1.0);
        break;
      case VoiceCommandType.toggleWinterMode:
        final enabled = command.params['enabled'] as bool? ?? !appState.isWinterMode;
        appState.setWinterMode(enabled);
        break;
      case VoiceCommandType.refreshPlan:
        _refreshPlan();
        break;
      case VoiceCommandType.setEnergyScore:
        final score = command.params['score'] as int?;
        if (score != null) _adjustCheckInAndRegenerate(energyScore: score);
        break;
      case VoiceCommandType.setRecoveryStatus:
        final statusStr = command.params['status'] as String?;
        if (statusStr != null) {
          final status = RecoveryStatus.values.firstWhere(
            (e) => e.name == statusStr,
            orElse: () => RecoveryStatus.wellRested,
          );
          _adjustCheckInAndRegenerate(recoveryStatus: status);
        }
        break;
      case VoiceCommandType.setAvailableTime:
        final timeStr = command.params['time'] as String?;
        if (timeStr != null) {
          final time = AvailableTimeRange.values.firstWhere(
            (e) => e.name == timeStr,
            orElse: () => AvailableTimeRange.range20_40,
          );
          _adjustCheckInAndRegenerate(availableTime: time);
        }
        break;
      case VoiceCommandType.submitCheckIn:
        _submitVoiceCheckIn();
        break;
      case VoiceCommandType.openCheckIn:
        _voiceService.startCheckInFlow();
        break;
      case VoiceCommandType.logIntention:
        final title = command.params['title'] as String?;
        if (title != null && title.trim().isNotEmpty) {
          _createIntentionByVoice(title.trim());
        }
        break;

      // ── Tab navigation ──────────────────────────────────────────────────
      case VoiceCommandType.openHome:
        _goToTab(AppTab.home);
        break;
      case VoiceCommandType.openIntentions:
        _goToTab(AppTab.intentions);
        break;
      case VoiceCommandType.openHabitBuilder:
        _goToTab(AppTab.habitBuilder);
        break;
      case VoiceCommandType.openJournal:
        _goToTab(AppTab.reflection);
        break;
      case VoiceCommandType.openSettings:
        _pushScreen(const SettingsScreen());
        break;

      // ── Tool navigation (pushed routes) ─────────────────────────────────
      case VoiceCommandType.openNutritionCoach:
        _pushScreen(const NutritionCoachScreen());
        break;
      case VoiceCommandType.openMealPlanner:
        _pushScreen(const MealPlannerScreen());
        break;
      case VoiceCommandType.openCalorieBudget:
        _pushScreen(const CalorieBudgetScreen());
        break;
      case VoiceCommandType.openHydration:
        _pushScreen(const HydrationCoachScreen());
        break;
      case VoiceCommandType.openSleepCoach:
        _pushScreen(const SleepCoachEntry());
        break;
      case VoiceCommandType.openMeditation:
        _pushScreen(const MeditationHomeScreen());
        break;
      case VoiceCommandType.openPeriodTracker:
        _pushScreen(const PeriodTrackerScreen());
        break;
      case VoiceCommandType.openWeightTracker:
        _pushScreen(const WeightTrackerScreen());
        break;
      case VoiceCommandType.openMindfulTravel:
        _pushScreen(const TravelScreen());
        break;
      case VoiceCommandType.openChallenges:
        // Challenges live inside the Habit Builder tab.
        _goToTab(AppTab.habitBuilder);
        break;

      // ── Quick actions ───────────────────────────────────────────────────
      case VoiceCommandType.logWater:
        final amount = command.params['amountMl'];
        _logWaterByVoice(amount is int ? amount : (amount is num ? amount.round() : null));
        break;
      case VoiceCommandType.startBreathing:
        _pushScreen(const BreathingScreen());
        break;
      case VoiceCommandType.startMeditation:
        _pushScreen(const GuidedMeditationScreen());
        break;

      default:
        break;
    }
  }

  /// Switches the bottom-nav tab via [AppNavigationService], then closes the
  /// voice sheet so the target tab is visible.
  void _goToTab(AppTab tab) {
    // Request the tab switch first, then close the sheet so the tab shows.
    context.read<AppNavigationService>().goToTab(tab);
    _closeSheet();
  }

  /// Closes the voice sheet, then pushes a full-screen route on the app's
  /// root navigator.
  ///
  /// Order matters: we must pop the sheet BEFORE pushing, otherwise a later
  /// sheet-dismiss would pop the freshly-pushed tool screen instead (the bug
  /// where the tool opened then instantly disappeared).
  void _pushScreen(Widget screen) {
    // Capture the root navigator before we pop (context stays valid).
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    _closeSheet();
    // Push on the next frame so the sheet pop has fully settled.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      rootNavigator.push(MaterialPageRoute(builder: (_) => screen));
    });
  }

  /// Immediately closes the voice assistant bottom sheet if it's still open.
  void _closeSheet() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) navigator.pop();
  }

  /// Logs water via the Hydration tool. Uses the spoken [amountMl] when given,
  /// otherwise defaults to one glass (250 ml). The spoken confirmation is
  /// handled by VoiceCommandService, so this only speaks on failure.
  Future<void> _logWaterByVoice(int? amountMl) async {
    final ml = (amountMl != null && amountMl > 0) ? amountMl : 250;
    try {
      final hydration = context.read<HydrationState>();
      await hydration.logWater(ml, source: 'voice');
    } catch (e) {
      _voiceService.speak(
          "Sorry, I couldn't log your water right now. Please try again.");
    }
  }

  /// Creates a wellness intention from a voice command (title is the only
  /// required field). Respects the free-tier 3-intention limit.
  ///
  /// Premium users get an AI-shortened title AND an AI-generated task plan.
  /// Free users keep the simple behavior (raw title, generic/fallback steps).
  Future<void> _createIntentionByVoice(String rawTitle) async {
    final appState = context.read<AppState>();

    // Free-tier limit: 3 active intentions (matches the add-intention screen).
    if (!appState.isPro && appState.dreams.length >= 3) {
      _voiceService.speak(
          "You've reached the free limit of 3 intentions. Upgrade to Premium "
          "in Settings to add more.");
      return;
    }

    try {
      if (appState.isPro) {
        final ai = AIService();
        // 1. Short, tidy AI title (fall back to the raw spoken title).
        final aiTitle = await ai.generateIntentionTitle(rawTitle);
        final title = (aiTitle != null && aiTitle.trim().isNotEmpty)
            ? aiTitle.trim()
            : rawTitle;
        // 2. AI-generated daily task plan.
        final steps = await ai.generateDreamTasks(dream: title, days: 7);
        await appState.addDream(
          title,
          deadline: DateTime.now().add(const Duration(days: 7)),
          initialSteps: steps,
        );
        _voiceService.speak("Done! I've created your intention: $title.");
      } else {
        // Free tier — current behavior (raw title, no AI plan).
        await appState.addDream(rawTitle);
      }
    } catch (e) {
      _voiceService.speak(
          "Sorry, I couldn't add that intention. Please try again.");
    }
  }

  /// Premium: update today's energy/recovery from a voice command and
  /// regenerate the plan. Free users get a spoken upsell.
  Future<void> _adjustCheckInAndRegenerate({
    int? energyScore,
    RecoveryStatus? recoveryStatus,
    AvailableTimeRange? availableTime,
  }) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    final appState = context.read<AppState>();
    if (!appState.isPro) {
      _voiceService.speak(
          'Adjusting your check-in to regenerate today\'s plan is '
          'a Premium feature. You can upgrade to Premium in Settings.');
      return;
    }

    final checkInState = context.read<CheckInState>();
    final planState = context.read<WellnessPlanState>();
    final preferredMethods = context.read<AppState>().preferredMethods;

    final updated = await checkInState.updateEnergyAndRecovery(
      energyScore: energyScore,
      recoveryStatus: recoveryStatus,
      availableTime: availableTime,
    );
    await planState.regeneratePlan(userId, updated,
        preferredMethods: preferredMethods);
  }

  void _refreshPlan() {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    // Regenerating today's plan is a Premium feature.
    final appState = context.read<AppState>();
    if (!appState.isPro) {
      _voiceService.speak(
          'Regenerating your plan is a Premium feature. You can upgrade to '
          'Premium in Settings.');
      return;
    }

    final checkInState = context.read<CheckInState>();
    final planState = context.read<WellnessPlanState>();
    final preferredMethods = appState.preferredMethods;

    final checkIn = checkInState.todaysCheckIn;
    if (checkIn != null) {
      planState.regeneratePlan(userId, checkIn,
          preferredMethods: preferredMethods);
    } else {
      // Use a default check-in for regeneration
      final defaultCheckIn = CheckIn(
        id: 'voice_${const Uuid().v4()}',
        date: DateTime.now(),
        energyScore: 3,
        availableTime: AvailableTimeRange.range20_40,
      );
      planState.regeneratePlan(userId, defaultCheckIn,
          preferredMethods: preferredMethods);
    }
  }

  void _submitVoiceCheckIn() {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    final checkInState = context.read<CheckInState>();
    final planState = context.read<WellnessPlanState>();

    final energy = _voiceService.pendingEnergy;
    final moodStr = _voiceService.pendingMood;
    final recoveryStr = _voiceService.pendingRecovery;
    final timeStr = _voiceService.pendingTime;

    // Convert strings to enums
    MoodState? mood;
    if (moodStr != null) {
      mood = MoodState.values.firstWhere(
        (e) => e.name == moodStr,
        orElse: () => MoodState.calm,
      );
    }

    RecoveryStatus? recovery;
    if (recoveryStr != null) {
      recovery = RecoveryStatus.values.firstWhere(
        (e) => e.name == recoveryStr,
        orElse: () => RecoveryStatus.wellRested,
      );
    }

    AvailableTimeRange? time;
    if (timeStr != null) {
      time = AvailableTimeRange.values.firstWhere(
        (e) => e.name == timeStr,
        orElse: () => AvailableTimeRange.range20_40,
      );
    }

    final skipped = <String>[];
    if (energy == null) skipped.add('energyScore');
    if (mood == null) skipped.add('moodState');
    if (recovery == null) skipped.add('recoveryStatus');
    if (time == null) skipped.add('availableTime');

    final checkIn = CheckIn(
      id: const Uuid().v4(),
      date: DateTime.now(),
      energyScore: energy,
      moodState: mood,
      recoveryStatus: recovery,
      availableTime: time,
      skippedFields: skipped,
    );

    // Capture personalization inputs synchronously (BuildContext must not be
    // used inside the async .then callback).
    final appState = context.read<AppState>();
    final preferredMethods = appState.preferredMethods;
    final cycleContext = appState.cyclePhaseContext;
    final travelContext = appState.travelContext;
    final premiumToolkitContext = ToolkitContextBuilder.build(context);

    // Submit and generate plan
    checkInState.submitCheckIn(checkIn).then((_) {
      planState.generatePlan(userId, checkIn,
          intentions: appState.intentions,
          cycleContext: cycleContext,
          travelContext: travelContext,
          preferredMethods: preferredMethods,
          premiumToolkitContext: premiumToolkitContext);
    });

    _voiceService.resetCheckInFlow();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1A27) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Drag handle
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Title bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Icon(
                  Icons.mic_rounded,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Wellness Assistant',
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                if (_voiceService.isInCheckInFlow)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Check-in',
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Conversation messages
          Expanded(
            child: _voiceService.messages.isEmpty
                ? _buildEmptyState(theme)
                : _buildMessageList(theme, isDark),
          ),

          // Live transcription
          if (_voiceService.currentWords.isNotEmpty &&
              _voiceService.state == VoiceAssistantState.listening)
            _buildTranscriptionBar(theme),

          // Debug-only text input (no microphone needed — for Simulator
          // testing of the parse → Gemini reply → response pipeline).
          if (kDebugMode) _buildDebugInput(theme, isDark),

          // Orb + controls
          _buildOrbSection(theme, isDark),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.spatial_audio_off_rounded,
              size: 48,
              color: theme.colorScheme.primary.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'Tap the orb to speak',
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try: "Switch to dark mode"\n"Start my check-in"\n"How am I doing?"',
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                fontSize: 14,
                color: theme.colorScheme.onSurface.withOpacity(0.4),
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageList(ThemeData theme, bool isDark) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: _voiceService.messages.length,
      itemBuilder: (context, index) {
        final message = _voiceService.messages[index];
        return _buildMessageBubble(message, theme, isDark);
      },
    );
  }

  Widget _buildMessageBubble(VoiceMessage message, ThemeData theme, bool isDark) {
    final isUser = message.isUser;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isUser
              ? theme.colorScheme.primary.withOpacity(0.12)
              : isDark
                  ? Colors.white.withOpacity(0.06)
                  : Colors.grey.shade100,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: isUser ? const Radius.circular(18) : const Radius.circular(4),
            bottomRight: isUser ? const Radius.circular(4) : const Radius.circular(18),
          ),
        ),
        child: Text(
          message.text,
          style: GoogleFonts.dmSans(
            fontSize: 15,
            color: theme.colorScheme.onSurface,
            height: 1.4,
          ),
        ),
      ),
    );
  }

  Widget _buildTranscriptionBar(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: theme.colorScheme.primary.withOpacity(0.05),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: Colors.redAccent,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.redAccent.withOpacity(0.4),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _voiceService.currentWords,
              style: GoogleFonts.dmSans(
                fontSize: 14,
                fontStyle: FontStyle.italic,
                color: theme.colorScheme.onSurface.withOpacity(0.7),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// Debug-only typed-input row for testing without a microphone.
  Widget _buildDebugInput(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: (isDark ? Colors.amber : Colors.orange).withOpacity(0.08),
      child: Row(
        children: [
          Icon(Icons.bug_report_rounded,
              size: 18, color: theme.colorScheme.onSurface.withOpacity(0.4)),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _debugInputController,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _submitDebugText(),
              style: GoogleFonts.dmSans(
                fontSize: 14,
                color: theme.colorScheme.onSurface,
              ),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Debug: type a phrase to test…',
                hintStyle: GoogleFonts.dmSans(
                  fontSize: 13,
                  color: theme.colorScheme.onSurface.withOpacity(0.4),
                ),
                border: InputBorder.none,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.send_rounded,
                size: 20, color: theme.colorScheme.primary),
            onPressed: _submitDebugText,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _buildOrbSection(ThemeData theme, bool isDark) {
    final isListening = _voiceService.state == VoiceAssistantState.listening;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        children: [
          // State label
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              _stateLabel,
              key: ValueKey(_stateLabel),
              style: GoogleFonts.dmSans(
                fontSize: 13,
                color: theme.colorScheme.onSurface.withOpacity(0.5),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Orb
          GestureDetector(
            onTap: _onOrbTap,
            onLongPress: _onOrbLongPress,
            child: VoiceOrb(
              state: _voiceService.state,
              soundLevel: _voiceService.soundLevel,
              size: 130,
              primaryColor: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 12),

          // Action hint
          Text(
            isListening ? 'Tap to stop' : 'Tap to speak',
            style: GoogleFonts.dmSans(
              fontSize: 12,
              color: theme.colorScheme.onSurface.withOpacity(0.4),
            ),
          ),
        ],
      ),
    );
  }

  String get _stateLabel {
    switch (_voiceService.state) {
      case VoiceAssistantState.idle:
        return 'Ready';
      case VoiceAssistantState.listening:
        return 'Listening...';
      case VoiceAssistantState.processing:
        return 'Thinking...';
      case VoiceAssistantState.speaking:
        return 'Speaking...';
    }
  }

  void _onOrbTap() {
    switch (_voiceService.state) {
      case VoiceAssistantState.idle:
        _voiceService.startListening();
        break;
      case VoiceAssistantState.listening:
        _voiceService.stopListening();
        break;
      case VoiceAssistantState.speaking:
        // Could interrupt TTS here
        break;
      case VoiceAssistantState.processing:
        break;
    }
  }

  void _onOrbLongPress() {
    // Long press starts check-in flow
    if (!_voiceService.isInCheckInFlow) {
      _voiceService.startCheckInFlow();
    }
  }
}
