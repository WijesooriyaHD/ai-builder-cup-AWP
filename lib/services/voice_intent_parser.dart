import '../models/voice_command.dart';
import '../models/wellness_enums.dart';

/// Parses natural language text into structured [VoiceCommand] objects.
///
/// Uses keyword matching and pattern recognition to identify user intent
/// without requiring a Cloud Function call. Handles settings commands,
/// check-in data extraction, navigation, and conversational phrases.
class VoiceIntentParser {
  /// Parses recognized speech text into a [VoiceCommand].
  VoiceCommand parse(String text) {
    final normalized = text.toLowerCase().trim();

    // Try each category in priority order
    return _tryThemeCommand(normalized, text) ??
        _tryQuickActionCommand(normalized, text) ??
        _tryToolNavigationCommand(normalized, text) ??
        _tryEnergyCommand(normalized, text) ??
        _tryMoodCommand(normalized, text) ??
        _tryRecoveryCommand(normalized, text) ??
        _tryTimeCommand(normalized, text) ??
        _tryTextSizeCommand(normalized, text) ??
        _tryWinterModeCommand(normalized, text) ??
        _tryNavigationCommand(normalized, text) ??
        _tryCheckInSubmit(normalized, text) ??
        _tryRefreshPlan(normalized, text) ??
        _tryLogIntention(normalized, text) ??
        _tryConversational(normalized, text) ??
        VoiceCommand(type: VoiceCommandType.unknown, rawText: text);
  }

  // ---------------------------------------------------------------------------
  // Quick actions (do something, not just navigate)
  // ---------------------------------------------------------------------------

  VoiceCommand? _tryQuickActionCommand(String normalized, String raw) {
    // Log water — "log water", "I drank water", "add a glass of water",
    // "log 100 milliliters", "add 500 ml", "log two glasses".
    final mentionsWater = _matchesAny(normalized, [
      'log water',
      'log a glass',
      'add water',
      'add a glass',
      'drank water',
      'drink water',
      'had some water',
      'track water',
      'log my water',
      'record water',
      // amount-led phrasings
      'milliliter',
      'millilitre',
    ]);
    // Also treat "log 250 ml" / "add 500ml" as water even without the word
    // "water", as long as a water action verb + ml unit is present.
    final mlUnit = RegExp(r'\b(\d+)\s*(ml|milliliters?|millilitres?)\b')
        .firstMatch(normalized);
    final waterVerb = _matchesAny(normalized, ['log', 'add', 'drank', 'drink', 'record', 'track']);

    if (mentionsWater || (mlUnit != null && waterVerb)) {
      final amount = _extractWaterMl(normalized);
      return VoiceCommand(
        type: VoiceCommandType.logWater,
        params: amount != null ? {'amountMl': amount} : const {},
        rawText: raw,
      );
    }

    // Start a breathing exercise.
    if (_matchesAny(normalized, [
      'start breathing',
      'breathing exercise',
      'do breathing',
      'breathe',
      'box breathing',
      'breathing session',
    ])) {
      return VoiceCommand(type: VoiceCommandType.startBreathing, rawText: raw);
    }

    // Start a meditation session.
    if (_matchesAny(normalized, [
      'start meditation',
      'start a meditation',
      'meditate',
      'begin meditation',
      'let\'s meditate',
      'guided meditation',
      'meditation session',
    ])) {
      return VoiceCommand(type: VoiceCommandType.startMeditation, rawText: raw);
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // Tool + tab navigation
  // ---------------------------------------------------------------------------

  VoiceCommand? _tryToolNavigationCommand(String normalized, String raw) {
    // Tabs.
    if (_matchesAny(normalized, [
      'open intentions',
      'my intentions',
      'wellness intentions',
      'go to intentions',
      'show intentions',
    ])) {
      return VoiceCommand(type: VoiceCommandType.openIntentions, rawText: raw);
    }
    if (_matchesAny(normalized, [
      'habit builder',
      'my habits',
      'open habits',
      'go to habits',
      'show habits',
      'habit tracker',
    ])) {
      return VoiceCommand(type: VoiceCommandType.openHabitBuilder, rawText: raw);
    }
    if (_matchesAny(normalized, [
      'challenges',
      'open challenge',
      'wellness challenge',
      'show challenges',
      'join a challenge',
    ])) {
      return VoiceCommand(type: VoiceCommandType.openChallenges, rawText: raw);
    }

    // Wellness tools.
    if (_matchesAny(normalized, [
      'nutrition coach',
      'open nutrition',
      'food log',
      'log food',
      'log a meal',
      'food logging',
      'scan food',
    ])) {
      return VoiceCommand(type: VoiceCommandType.openNutritionCoach, rawText: raw);
    }
    if (_matchesAny(normalized, [
      'meal planner',
      'meal plan',
      'plan my meals',
      'plan meals',
      'open meal',
    ])) {
      return VoiceCommand(type: VoiceCommandType.openMealPlanner, rawText: raw);
    }
    if (_matchesAny(normalized, [
      'calorie budget',
      'calories',
      'calorie tracker',
      'my calories',
      'open calorie',
    ])) {
      return VoiceCommand(type: VoiceCommandType.openCalorieBudget, rawText: raw);
    }
    if (_matchesAny(normalized, [
      'hydration coach',
      'open hydration',
      'water tracker',
      'hydration',
      'track my water',
    ])) {
      return VoiceCommand(type: VoiceCommandType.openHydration, rawText: raw);
    }
    if (_matchesAny(normalized, [
      'sleep coach',
      'open sleep',
      'my sleep',
      'sleep tracker',
      'how did i sleep',
    ])) {
      return VoiceCommand(type: VoiceCommandType.openSleepCoach, rawText: raw);
    }
    if (_matchesAny(normalized, [
      'meditation pal',
      'open meditation',
      'mindfulness',
      'meditation tool',
    ])) {
      return VoiceCommand(type: VoiceCommandType.openMeditation, rawText: raw);
    }
    if (_matchesAny(normalized, [
      'period tracker',
      'open period',
      'my cycle',
      'menstrual',
      'track my period',
    ])) {
      return VoiceCommand(type: VoiceCommandType.openPeriodTracker, rawText: raw);
    }
    if (_matchesAny(normalized, [
      'weight tracker',
      'body weight',
      'log my weight',
      'track my weight',
      'open weight',
    ])) {
      return VoiceCommand(type: VoiceCommandType.openWeightTracker, rawText: raw);
    }
    if (_matchesAny(normalized, [
      'mindful travel',
      'travel',
      'my trips',
      'open travel',
      'log a trip',
    ])) {
      return VoiceCommand(type: VoiceCommandType.openMindfulTravel, rawText: raw);
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // Wellness intention logging
  // ---------------------------------------------------------------------------

  /// Recognizes "add/create/set an intention (to <goal>)" and extracts the
  /// goal title when present. Title is the only required field.
  VoiceCommand? _tryLogIntention(String normalized, String raw) {
    // Lead-in phrases that signal intent to create a wellness intention/goal.
    final leadIns = <String>[
      'add an intention',
      'add intention',
      'log an intention',
      'log intention',
      'create an intention',
      'create intention',
      'set an intention',
      'set intention',
      'new intention',
      'add a wellness intention',
      'add a goal',
      'set a goal',
      'new goal',
    ];
    final matched = leadIns.firstWhere(
      (p) => normalized.contains(p),
      orElse: () => '',
    );
    if (matched.isEmpty) return null;

    // Extract whatever follows the lead-in (and an optional "to"/"for") from
    // the ORIGINAL text to preserve casing.
    String title = '';
    final lowerRaw = raw.toLowerCase();
    final idx = lowerRaw.indexOf(matched);
    if (idx != -1) {
      var rest = raw.substring(idx + matched.length).trim();
      rest = rest.replaceFirst(
          RegExp(r'^(to|for|about|called|named)\s+', caseSensitive: false), '');
      title = rest.trim();
      if (title.length > 60) title = title.substring(0, 60).trim();
    }

    return VoiceCommand(
      type: VoiceCommandType.logIntention,
      params: title.isNotEmpty ? {'title': title} : const {},
      rawText: raw,
    );
  }

  // ---------------------------------------------------------------------------
  // Theme commands
  // ---------------------------------------------------------------------------

  VoiceCommand? _tryThemeCommand(String normalized, String raw) {
    // Dark mode
    if (_matchesAny(normalized, [
      'dark mode',
      'dark theme',
      'switch to dark',
      'enable dark',
      'turn on dark',
      'go dark',
      'night mode',
    ])) {
      return VoiceCommand(type: VoiceCommandType.setThemeDark, rawText: raw);
    }

    // Light mode
    if (_matchesAny(normalized, [
      'light mode',
      'light theme',
      'switch to light',
      'enable light',
      'turn on light',
      'go light',
      'day mode',
    ])) {
      return VoiceCommand(type: VoiceCommandType.setThemeLight, rawText: raw);
    }

    // Accent color
    final colorMap = <String, int>{
      'coral': 0xFFFF7F50,
      'orange': 0xFFFF7F50,
      'turquoise': 0xFF4ECDC4,
      'teal': 0xFF4ECDC4,
      'yellow': 0xFFFFD93D,
      'purple': 0xFF9B59B6,
      'violet': 0xFF9B59B6,
      'pink': 0xFFE91E63,
      'blue': 0xFF2196F3,
      'green': 0xFF4CAF50,
      'red': 0xFFF44336,
    };

    for (final entry in colorMap.entries) {
      if (normalized.contains(entry.key) &&
          _matchesAny(normalized, [
            'change color to',
            'set color to',
            'accent color',
            'theme color',
            'make it ${entry.key}',
            'use ${entry.key}',
            '${entry.key} color',
            '${entry.key} theme',
          ])) {
        return VoiceCommand(
          type: VoiceCommandType.setAccentColor,
          params: {'color': entry.value, 'colorName': entry.key},
          rawText: raw,
        );
      }
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // Energy score
  // ---------------------------------------------------------------------------

  VoiceCommand? _tryEnergyCommand(String normalized, String raw) {
    // Direct numeric: "energy is 4", "my energy is 3", "set energy to 5"
    final numericPattern = RegExp(r'energy\s*(?:is|to|at|level)?\s*(\d)');
    final numMatch = numericPattern.firstMatch(normalized);
    if (numMatch != null) {
      final score = int.parse(numMatch.group(1)!);
      if (score >= 1 && score <= 5) {
        return VoiceCommand(
          type: VoiceCommandType.setEnergyScore,
          params: {'score': score},
          rawText: raw,
        );
      }
    }

    // Natural language energy descriptions
    final energyDescriptions = <List<String>, int>{
      ['completely drained', 'exhausted', 'no energy', 'dead tired', 'wiped out']: 1,
      ['low energy', 'pretty tired', 'not great', 'sluggish', 'barely awake']: 2,
      ['moderate', 'okay', 'so-so', 'decent', 'average', 'alright', 'not bad']: 3,
      ['good energy', 'feeling good', 'pretty good', 'energetic', 'well']: 4,
      ['fully energized', 'amazing', 'fantastic', 'great', 'on fire', 'excellent', 'best']: 5,
    };

    for (final entry in energyDescriptions.entries) {
      if (entry.key.any((phrase) => normalized.contains(phrase))) {
        // Only match if the context seems energy-related
        if (_matchesAny(normalized, [
          'energy',
          'feeling',
          'i feel',
          'i am',
          "i'm",
          'today',
          'my level',
        ])) {
          return VoiceCommand(
            type: VoiceCommandType.setEnergyScore,
            params: {'score': entry.value},
            rawText: raw,
          );
        }
      }
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // Mood
  // ---------------------------------------------------------------------------

  VoiceCommand? _tryMoodCommand(String normalized, String raw) {
    final moodMap = <List<String>, String>{
      ['calm', 'peaceful', 'relaxed', 'serene', 'tranquil', 'chill']: 'calm',
      ['anxious', 'worried', 'nervous', 'on edge', 'uneasy']: 'anxious',
      ['tired', 'sleepy', 'drowsy', 'fatigued', 'worn out']: 'tired',
      ['energized', 'pumped', 'hyper', 'wired', 'buzzing']: 'energized',
      ['stressed', 'overwhelmed', 'tense', 'pressured', 'burnt out']: 'stressed',
      ['content', 'happy', 'satisfied', 'good', 'cheerful', 'pleased']: 'content',
    };

    for (final entry in moodMap.entries) {
      if (entry.key.any((phrase) => normalized.contains(phrase))) {
        if (_matchesAny(normalized, [
          'mood',
          'feeling',
          'i feel',
          'i am',
          "i'm",
          'pretty',
          'quite',
          'very',
          'a bit',
          'kind of',
          'somewhat',
        ])) {
          return VoiceCommand(
            type: VoiceCommandType.setMood,
            params: {'mood': entry.value},
            rawText: raw,
          );
        }
      }
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // Recovery status
  // ---------------------------------------------------------------------------

  VoiceCommand? _tryRecoveryCommand(String normalized, String raw) {
    final recoveryMap = <List<String>, String>{
      ['well rested', 'well-rested', 'rested', 'fresh', 'recovered']: 'wellRested',
      ['sore', 'aching', 'muscles hurt', 'body hurts']: 'sore',
      ['fatigued', 'exhausted', 'drained', 'burned out']: 'fatigued',
      ['recovering', 'getting better', 'on the mend', 'healing']: 'recovering',
    };

    for (final entry in recoveryMap.entries) {
      if (entry.key.any((phrase) => normalized.contains(phrase))) {
        if (_matchesAny(normalized, [
          'recovery',
          'body',
          'physical',
          'rested',
          'sore',
          'muscle',
          'fatigue',
          'recover',
        ])) {
          return VoiceCommand(
            type: VoiceCommandType.setRecoveryStatus,
            params: {'status': entry.value},
            rawText: raw,
          );
        }
      }
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // Available time
  // ---------------------------------------------------------------------------

  VoiceCommand? _tryTimeCommand(String normalized, String raw) {
    if (_matchesAny(normalized, ['under 10', 'less than 10', '5 minute', 'few minutes', 'very little time'])) {
      return VoiceCommand(
        type: VoiceCommandType.setAvailableTime,
        params: {'time': AvailableTimeRange.under10.name},
        rawText: raw,
      );
    }
    if (_matchesAny(normalized, ['10 to 20', '10 minute', '15 minute', 'quarter hour', '10-20'])) {
      return VoiceCommand(
        type: VoiceCommandType.setAvailableTime,
        params: {'time': AvailableTimeRange.range10_20.name},
        rawText: raw,
      );
    }
    if (_matchesAny(normalized, ['20 to 40', '30 minute', '25 minute', 'half hour', '20-40'])) {
      return VoiceCommand(
        type: VoiceCommandType.setAvailableTime,
        params: {'time': AvailableTimeRange.range20_40.name},
        rawText: raw,
      );
    }
    if (_matchesAny(normalized, ['40 to 60', '45 minute', '50 minute', 'about an hour', '40-60'])) {
      return VoiceCommand(
        type: VoiceCommandType.setAvailableTime,
        params: {'time': AvailableTimeRange.range40_60.name},
        rawText: raw,
      );
    }
    if (_matchesAny(normalized, ['over 60', 'more than an hour', 'over an hour', 'plenty of time', 'lots of time'])) {
      return VoiceCommand(
        type: VoiceCommandType.setAvailableTime,
        params: {'time': AvailableTimeRange.over60.name},
        rawText: raw,
      );
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // Text size
  // ---------------------------------------------------------------------------

  VoiceCommand? _tryTextSizeCommand(String normalized, String raw) {
    if (_matchesAny(normalized, [
      'increase text',
      'bigger text',
      'larger text',
      'make text bigger',
      'increase font',
      'larger font',
    ])) {
      return VoiceCommand(type: VoiceCommandType.increaseTextSize, rawText: raw);
    }
    if (_matchesAny(normalized, [
      'decrease text',
      'smaller text',
      'make text smaller',
      'decrease font',
      'smaller font',
    ])) {
      return VoiceCommand(type: VoiceCommandType.decreaseTextSize, rawText: raw);
    }
    if (_matchesAny(normalized, [
      'reset text',
      'default text',
      'normal text',
      'reset font',
    ])) {
      return VoiceCommand(type: VoiceCommandType.resetTextSize, rawText: raw);
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Winter mode
  // ---------------------------------------------------------------------------

  VoiceCommand? _tryWinterModeCommand(String normalized, String raw) {
    if (_matchesAny(normalized, [
      'enable winter',
      'turn on winter',
      'snow mode',
      'winter mode on',
      'enable snow',
    ])) {
      return VoiceCommand(
        type: VoiceCommandType.toggleWinterMode,
        params: {'enabled': true},
        rawText: raw,
      );
    }
    if (_matchesAny(normalized, [
      'disable winter',
      'turn off winter',
      'winter mode off',
      'no snow',
      'disable snow',
    ])) {
      return VoiceCommand(
        type: VoiceCommandType.toggleWinterMode,
        params: {'enabled': false},
        rawText: raw,
      );
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------------

  VoiceCommand? _tryNavigationCommand(String normalized, String raw) {
    if (_matchesAny(normalized, ['open settings', 'go to settings', 'show settings'])) {
      return VoiceCommand(type: VoiceCommandType.openSettings, rawText: raw);
    }
    if (_matchesAny(normalized, ['open check in', 'start check in', 'do check in', 'check in'])) {
      return VoiceCommand(type: VoiceCommandType.openCheckIn, rawText: raw);
    }
    if (_matchesAny(normalized, ['open journal', 'go to journal', 'show journal'])) {
      return VoiceCommand(type: VoiceCommandType.openJournal, rawText: raw);
    }
    if (_matchesAny(normalized, ['go home', 'go to home', 'open home'])) {
      return VoiceCommand(type: VoiceCommandType.openHome, rawText: raw);
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Check-in submit
  // ---------------------------------------------------------------------------

  VoiceCommand? _tryCheckInSubmit(String normalized, String raw) {
    if (_matchesAny(normalized, [
      'submit check in',
      'done with check in',
      'finish check in',
      "that's all",
      "that's it",
      'submit',
    ])) {
      return VoiceCommand(type: VoiceCommandType.submitCheckIn, rawText: raw);
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Refresh plan
  // ---------------------------------------------------------------------------

  VoiceCommand? _tryRefreshPlan(String normalized, String raw) {
    if (_matchesAny(normalized, [
      'refresh plan',
      'new plan',
      'regenerate plan',
      'different plan',
      'change plan',
      'get a new plan',
    ])) {
      return VoiceCommand(type: VoiceCommandType.refreshPlan, rawText: raw);
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Conversational
  // ---------------------------------------------------------------------------

  VoiceCommand? _tryConversational(String normalized, String raw) {
    if (_matchesAny(normalized, ['hello', 'hey', 'hi', 'good morning', 'good afternoon', 'good evening'])) {
      return VoiceCommand(type: VoiceCommandType.greeting, rawText: raw);
    }
    if (_matchesAny(normalized, ['how am i doing', 'my progress', 'my stats', 'how am i'])) {
      return VoiceCommand(type: VoiceCommandType.howAmI, rawText: raw);
    }
    if (_matchesAny(normalized, ['help', 'what can you do', 'what can i say', 'commands'])) {
      return VoiceCommand(type: VoiceCommandType.help, rawText: raw);
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  bool _matchesAny(String input, List<String> patterns) {
    return patterns.any((p) => input.contains(p));
  }

  /// Extracts a water amount in millilitres from spoken text.
  ///
  /// Handles explicit units ("100 ml", "500 milliliters"), litres
  /// ("1 litre", "1.5 liters" -> ml), and glass counts ("two glasses" ->
  /// 250 ml each). Returns null when no amount is stated (caller defaults).
  int? _extractWaterMl(String normalized) {
    // Explicit millilitres.
    final ml = RegExp(r'(\d+(?:\.\d+)?)\s*(?:ml|milliliters?|millilitres?)')
        .firstMatch(normalized);
    if (ml != null) {
      final v = double.tryParse(ml.group(1)!);
      if (v != null && v > 0) return v.round();
    }

    // Litres -> ml.
    final l = RegExp(r'(\d+(?:\.\d+)?)\s*(?:l\b|liters?|litres?)')
        .firstMatch(normalized);
    if (l != null) {
      final v = double.tryParse(l.group(1)!);
      if (v != null && v > 0) return (v * 1000).round();
    }

    // Glass counts (numeric or worded), 250 ml per glass.
    final glassNum = RegExp(r'(\d+)\s*glass').firstMatch(normalized);
    if (glassNum != null) {
      final n = int.tryParse(glassNum.group(1)!);
      if (n != null && n > 0) return n * 250;
    }
    const words = {
      'a': 1, 'one': 1, 'two': 2, 'three': 3, 'four': 4,
      'five': 5, 'six': 6, 'seven': 7, 'eight': 8,
    };
    for (final entry in words.entries) {
      if (RegExp('\\b${entry.key}\\s+glass').hasMatch(normalized)) {
        return entry.value * 250;
      }
    }

    return null;
  }
}
