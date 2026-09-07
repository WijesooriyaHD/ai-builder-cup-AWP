/// Represents the type of voice command recognized from user speech.
enum VoiceCommandType {
  // Settings commands
  setThemeDark,
  setThemeLight,
  setAccentColor,
  increaseTextSize,
  decreaseTextSize,
  resetTextSize,
  toggleWinterMode,

  // Check-in commands
  setEnergyScore,
  setMood,
  setRecoveryStatus,
  setAvailableTime,
  submitCheckIn,

  // Wellness intention commands
  logIntention,

  // Navigation commands (tabs)
  openSettings,
  openCheckIn,
  openJournal,
  openHome,
  openIntentions,
  openHabitBuilder,
  refreshPlan,

  // Tool navigation commands (Life Toolkit + features)
  openNutritionCoach,
  openMealPlanner,
  openCalorieBudget,
  openHydration,
  openSleepCoach,
  openMeditation,
  openPeriodTracker,
  openWeightTracker,
  openMindfulTravel,
  openChallenges,

  // Quick actions
  logWater,
  startBreathing,
  startMeditation,

  // Conversational
  greeting,
  howAmI,
  help,

  // Unknown
  unknown,
}

/// A parsed voice command with its type and extracted parameters.
class VoiceCommand {
  final VoiceCommandType type;
  final Map<String, dynamic> params;
  final String rawText;
  final double confidence;

  const VoiceCommand({
    required this.type,
    this.params = const {},
    required this.rawText,
    this.confidence = 1.0,
  });

  @override
  String toString() => 'VoiceCommand($type, params: $params, raw: "$rawText")';
}

/// Represents a message in the voice assistant conversation.
class VoiceMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  VoiceMessage({
    required this.text,
    required this.isUser,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  VoiceMessage.user(String text)
      : this(text: text, isUser: true);

  VoiceMessage.assistant(String text)
      : this(text: text, isUser: false);
}
