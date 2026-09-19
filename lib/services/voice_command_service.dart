import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';

import '../data/ai_voices.dart';
import '../models/voice_command.dart';
import 'ai_service.dart';
import 'voice_intent_parser.dart';

/// The state of the voice assistant.
enum VoiceAssistantState {
  idle,
  listening,
  processing,
  speaking,
}

/// Service that manages speech recognition, intent parsing, and TTS responses.
///
/// Integrates `speech_to_text` for input, [VoiceIntentParser] for NLP,
/// and `flutter_tts` for spoken responses.
class VoiceCommandService extends ChangeNotifier {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final VoiceIntentParser _parser = VoiceIntentParser();
  final AIService _aiService = AIService();

  VoiceAssistantState _state = VoiceAssistantState.idle;
  bool _isInitialized = false;
  bool _speechAvailable = false;
  AiVoiceOption _voice = kAiVoices.first;

  /// Whether the current user has Premium. Kept in sync by the UI layer so the
  /// assistant can tailor upsell hints (only suggests Premium to free users).
  bool _isPremium = false;
  set isPremium(bool value) => _isPremium = value;
  double _soundLevel = 0.0;
  String _currentWords = '';
  final List<VoiceMessage> _messages = [];

  // Awaiting the intention title after the user asked to log one without a
  // goal (we prompt for the one required field, then create it).
  bool _awaitingIntentionTitle = false;

  // Short-term memory of the habit the user most recently created/referenced
  // by voice, so follow-ups like "change it to 7:30" resolve to the right
  // habit. Set by the UI layer after a successful voice habit creation.
  String? _lastHabitId;
  String? _lastHabitTitle;

  /// Remembers the habit the user just acted on by voice (used to resolve
  /// pronoun follow-ups like "change it to 7:30"). Pass nulls to clear.
  void rememberLastHabit(String? id, String? title) {
    _lastHabitId = id;
    _lastHabitTitle = title;
  }

  /// The id of the last habit referenced by voice, or null.
  String? get lastHabitId => _lastHabitId;

  // Guards against processing the same utterance twice. Both the recognizer's
  // finalResult callback and stopListening() can fire for one utterance; this
  // ensures we only handle (and speak) it once.
  bool _isHandlingInput = false;

  // Conversational check-in state
  bool _isInCheckInFlow = false;
  int? _pendingEnergy;
  String? _pendingMood;
  String? _pendingRecovery;
  String? _pendingTime;
  int _checkInStep = 0; // 0=energy, 1=mood, 2=recovery/time

  // ---------------------------------------------------------------------------
  // Getters
  // ---------------------------------------------------------------------------

  VoiceAssistantState get state => _state;
  bool get isListening => _state == VoiceAssistantState.listening;
  bool get isSpeaking => _state == VoiceAssistantState.speaking;
  double get soundLevel => _soundLevel;
  String get currentWords => _currentWords;
  List<VoiceMessage> get messages => List.unmodifiable(_messages);
  bool get isInCheckInFlow => _isInCheckInFlow;
  int? get pendingEnergy => _pendingEnergy;
  String? get pendingMood => _pendingMood;
  String? get pendingRecovery => _pendingRecovery;
  String? get pendingTime => _pendingTime;

  // ---------------------------------------------------------------------------
  // Initialization
  // ---------------------------------------------------------------------------

  /// Initializes speech recognition and TTS. Must be called before use.
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Initialize speech recognition (requests mic + speech permission on iOS).
      _speechAvailable = await _speech.initialize(
        onError: _onSpeechError,
        onStatus: _onSpeechStatus,
      );

      await _tts.setVolume(1.0);
      // Apply the currently selected voice (language/rate/pitch/voice name).
      await _applyVoiceToTts(_voice);

      _tts.setCompletionHandler(() {
        _state = VoiceAssistantState.idle;
        notifyListeners();
      });

      _isInitialized = true;
      debugPrint('VoiceCommandService: initialized (speech=$_speechAvailable)');
    } catch (e) {
      debugPrint('VoiceCommandService: initialization failed: $e');
    }
  }

  /// Selects the AI assistant voice by id (see [kAiVoices]) and applies it to
  /// the TTS engine. Safe to call before or after [initialize].
  Future<void> setVoice(String voiceId) async {
    final option = aiVoiceById(voiceId);
    if (option.id == _voice.id && _isInitialized) return;
    _voice = option;
    if (_isInitialized) {
      await _applyVoiceToTts(option);
    }
  }

  /// Applies a voice option's language, rate, pitch, and (optionally) the
  /// platform voice name to the TTS engine.
  Future<void> _applyVoiceToTts(AiVoiceOption option) async {
    try {
      await _tts.setLanguage(option.locale);
      await _tts.setSpeechRate(option.rate);
      await _tts.setPitch(option.pitch);
      if (option.ttsVoiceName != null) {
        // If the named voice isn't installed, this is a no-op and the engine
        // keeps the locale/rate/pitch, so each option still sounds distinct.
        await _tts.setVoice({
          'name': option.ttsVoiceName!,
          'locale': option.locale,
        });
      }
    } catch (e) {
      debugPrint('VoiceCommandService: failed to apply voice ${option.id}: $e');
    }
  }

  /// Speaks a short sample so the user can preview the selected voice.
  Future<void> previewVoice(String voiceId) async {
    await setVoice(voiceId);
    if (!_isInitialized) await initialize();
    await speak(
        "Hi, I'm your wellness assistant. This is how I'll sound.");
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Starts listening for voice input.
  Future<void> startListening() async {
    if (!_isInitialized) await initialize();
    if (!_speechAvailable) {
      _addAssistantMessage(
          "Voice input isn't available. Please enable microphone and speech "
          "recognition permission for AI Wellness Pal in Settings.");
      return;
    }

    _currentWords = '';
    _state = VoiceAssistantState.listening;
    notifyListeners();

    await _speech.listen(
      onResult: _onSpeechResult,
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 4),
      onSoundLevelChange: _onSoundLevelChange,
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        listenMode: stt.ListenMode.dictation,
      ),
    );
  }

  /// Stops listening and processes whatever was captured.
  Future<void> stopListening() async {
    _soundLevel = 0.0;
    await _speech.stop();

    if (_currentWords.isNotEmpty) {
      _state = VoiceAssistantState.processing;
      notifyListeners();
      await _processInput(_currentWords);
    } else {
      _state = VoiceAssistantState.idle;
      notifyListeners();
    }
  }

  /// Submits typed [text] through the same pipeline as spoken input.
  ///
  /// Useful for testing on the iOS Simulator (which has no microphone) and as
  /// a text-entry fallback. Runs intent parsing / conversational reply exactly
  /// as if the words had been spoken.
  Future<void> submitTextInput(String text) async {
    if (text.trim().isEmpty) return;
    _state = VoiceAssistantState.processing;
    notifyListeners();
    await _processInput(text.trim());
  }

  /// Cancels listening without processing.
  Future<void> cancelListening() async {
    _soundLevel = 0.0;
    _currentWords = '';
    await _speech.cancel();
    _state = VoiceAssistantState.idle;
    notifyListeners();
  }

  /// Fully releases the microphone and audio session so another feature
  /// (Conversation Mode / Gemini Live, which uses the `record` plugin) can take
  /// exclusive control of the mic. Without this, speech_to_text keeps the mic
  /// open and both capture the loudspeaker at once, causing heavy echo.
  Future<void> shutdownForHandoff() async {
    _soundLevel = 0.0;
    _currentWords = '';
    try {
      await _tts.stop();
    } catch (_) {}
    try {
      await _speech.cancel();
    } catch (_) {}
    try {
      // stop() releases the underlying recognizer/audio session on iOS.
      await _speech.stop();
    } catch (_) {}
    _state = VoiceAssistantState.idle;
    notifyListeners();
  }

  /// Speaks a response using TTS.
  Future<void> speak(String text) async {
    _state = VoiceAssistantState.speaking;
    notifyListeners();
    await _tts.speak(text);
  }

  /// Starts the conversational check-in flow.
  void startCheckInFlow() {
    _isInCheckInFlow = true;
    _checkInStep = 0;
    _pendingEnergy = null;
    _pendingMood = null;
    _pendingRecovery = null;
    _pendingTime = null;
    notifyListeners();

    final greeting = "Let's do your check-in. How's your energy today? "
        "You can say something like 'I feel pretty good' or give a number from 1 to 5.";
    _addAssistantMessage(greeting);
    speak(greeting);
  }

  /// Resets the check-in flow state.
  void resetCheckInFlow() {
    _isInCheckInFlow = false;
    _checkInStep = 0;
    _pendingEnergy = null;
    _pendingMood = null;
    _pendingRecovery = null;
    _pendingTime = null;
    notifyListeners();
  }

  /// Clears the conversation history.
  void clearMessages() {
    _messages.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _speech.cancel();
    _tts.stop();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Callbacks
  // ---------------------------------------------------------------------------

  void _onSpeechResult(SpeechRecognitionResult result) {
    _currentWords = result.recognizedWords;
    // A successful transcription clears the error streak.
    if (_currentWords.trim().isNotEmpty) _consecutiveErrors = 0;
    notifyListeners();

    // When the recognizer marks the result final, process it automatically.
    if (result.finalResult && _currentWords.trim().isNotEmpty) {
      _soundLevel = 0.0;
      _state = VoiceAssistantState.processing;
      notifyListeners();
      _processInput(_currentWords);
    }
  }

  void _onSoundLevelChange(double level) {
    // Normalize to 0.0–1.0 range (raw values are typically -2 to 10)
    _soundLevel = ((level + 2) / 12).clamp(0.0, 1.0);
    notifyListeners();
  }

  void _onSpeechError(dynamic error) {
    debugPrint('VoiceCommandService: speech error: $error');
    _soundLevel = 0.0;
    _state = VoiceAssistantState.idle;

    // Extract the platform error id when available (speech_to_text passes a
    // SpeechRecognitionError with an `errorMsg` field).
    String errorId = '';
    try {
      errorId = (error as dynamic).errorMsg as String? ?? '';
    } catch (_) {
      errorId = error.toString();
    }
    final lower = errorId.toLowerCase();

    // Benign "nothing heard" cases — don't nag the user. These fire when the
    // recognizer times out without capturing speech (common if the user
    // didn't speak, or on the iOS Simulator which lacks a real microphone).
    final isNoSpeech = lower.contains('no_match') ||
        lower.contains('no match') ||
        lower.contains('speech_timeout') ||
        lower.contains('error_speech_timeout');

    // If we already captured words this session, let the normal processing
    // path handle it — the error is just the session closing.
    if (_currentWords.trim().isNotEmpty || isNoSpeech) {
      notifyListeners();
      return;
    }

    // Genuine, repeated failure — surface one gentle, actionable message.
    _consecutiveErrors++;
    if (_consecutiveErrors >= 2) {
      _addAssistantMessage(
          "I'm having trouble hearing you. Make sure microphone and speech "
          "recognition are allowed for AI Wellness Pal in Settings, and try "
          "again. (Voice input doesn't work on the iOS Simulator — use a real "
          "device.)");
      _consecutiveErrors = 0;
    }
    notifyListeners();
  }

  /// Counts consecutive recognizer errors so we only warn after a real,
  /// repeated failure rather than on the first transient hiccup.
  int _consecutiveErrors = 0;

  void _onSpeechStatus(String status) {
    debugPrint('VoiceCommandService: speech status: $status');
    if (status == 'done' || status == 'notListening') {
      if (_state == VoiceAssistantState.listening && _currentWords.isEmpty) {
        _state = VoiceAssistantState.idle;
        notifyListeners();
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Processing
  // ---------------------------------------------------------------------------

  Future<void> _processInput(String text) async {
    if (text.trim().isEmpty) {
      _state = VoiceAssistantState.idle;
      notifyListeners();
      return;
    }

    // Guard: the recognizer's finalResult callback and stopListening() can
    // both fire for one utterance. Only handle (and speak) it once.
    if (_isHandlingInput) return;
    _isHandlingInput = true;

    // Clear the buffered words so a follow-up stopListening() call sees nothing
    // to process (belt-and-suspenders against duplicate handling).
    _currentWords = '';

    try {
      _addUserMessage(text);

      // If we asked the user for an intention title, treat this reply as it.
      if (_awaitingIntentionTitle) {
        _awaitingIntentionTitle = false;
        final title = _cleanIntentionTitle(text);
        if (title.isEmpty) {
          final msg = "No problem — let me know when you'd like to add one.";
          _addAssistantMessage(msg);
          await speak(msg);
          return;
        }
        final command = VoiceCommand(
          type: VoiceCommandType.logIntention,
          params: {'title': title},
          rawText: text,
        );
        await _handleCommand(command);
        return;
      }

      if (_isInCheckInFlow) {
        await _processCheckInInput(text);
      } else {
        final command = await _parseCommand(text);
        await _handleCommand(command);
      }
    } finally {
      _isHandlingInput = false;
    }
  }

  /// Cleans a spoken intention title (strips common lead-ins, trims, caps len).
  String _cleanIntentionTitle(String raw) {
    var t = raw.trim();
    // Strip common conversational lead-ins.
    final lead = RegExp(
      r'^(i want to|i want|i would like to|i\047d like to|add an intention to|'
      r'add intention to|log an intention to|create an intention to|'
      r'set an intention to|add a goal to|my intention is to|my intention is|'
      r'to)\s+',
      caseSensitive: false,
    );
    t = t.replaceFirst(lead, '').trim();
    if (t.isEmpty) return '';
    // Capitalize first letter for a tidy title.
    t = t[0].toUpperCase() + t.substring(1);
    return t.length > 60 ? t.substring(0, 60).trim() : t;
  }

  /// Parses free-form speech into a [VoiceCommand].
  ///
  /// Tries the local keyword-based [VoiceIntentParser] FIRST — it's instant,
  /// offline, and handles the common phrasings with zero latency. Only when it
  /// can't confidently match (returns `unknown`) do we fall back to the
  /// AI-backed parser (Gemini 2.5 Flash via [AIService]) for flexible
  /// natural-language understanding. If the AI is unavailable/errors/unsure,
  /// the original `unknown` command is used so the assistant still responds.
  Future<VoiceCommand> _parseCommand(String text) async {
    // 0. Context-aware fast path: when a habit is in context and the user says
    //    a short follow-up with a time ("change it to 7:30", "make it 7 pm",
    //    "set it to 8am"), resolve it deterministically to updateHabitReminder.
    //    This runs BEFORE the keyword parser (which would otherwise mis-match a
    //    time phrase) and doesn't depend on the AI.
    if (_lastHabitId != null) {
      final reminder = _tryParseReminderChange(text);
      if (reminder != null) {
        return VoiceCommand(
          type: VoiceCommandType.updateHabitReminder,
          params: reminder,
          rawText: text,
        );
      }
    }

    // 1. Fast local keyword matching (offline-safe, no latency).
    final localCommand = _parser.parse(text);
    if (localCommand.type != VoiceCommandType.unknown) {
      return localCommand;
    }

    // 2. Local parser was unsure — ask the AI for a flexible interpretation.
    //    Give it the recent conversation transcript + short-term context (the
    //    last habit) so pronoun follow-ups resolve to the right target.
    try {
      final aiCommand = await _aiService.parseVoiceCommand(
        text,
        // Exclude the current utterance (already appended to _messages).
        history: _recentHistory(dropLast: 1),
        recentContext: _lastHabitTitle != null
            ? 'The user just created/updated a habit named "$_lastHabitTitle". '
                'If they refer to "it" or "that habit" with only a new time, '
                'they mean this habit.'
            : null,
      );
      if (aiCommand != null) return aiCommand;
    } catch (e) {
      debugPrint('VoiceCommandService: AI parse failed: $e');
    }

    // 3. Neither matched — return the unknown command (handler shows help).
    return localCommand;
  }

  /// Attempts to read a reminder-time-change follow-up from [text] when a
  /// habit is already in context. Returns `{reminderHour, reminderMinute}` in
  /// 24-hour form, or null if the utterance isn't a time change.
  ///
  /// Recognizes forms like: "7:30", "7.30", "7 30", "7", with optional am/pm,
  /// optionally preceded by change/reschedule/reminder/set/make wording.
  /// A bare number without am/pm or a "change/set" verb is NOT treated as a
  /// time change (to avoid hijacking unrelated numbers).
  Map<String, dynamic>? _tryParseReminderChange(String text) {
    final n = text.toLowerCase().trim();

    // Match a clock time: hour[:.  ]minute? with optional am/pm.
    final m = RegExp(
      r'\b(\d{1,2})\s*(?::|\.|\s)?\s*(\d{2})?\s*(a\.?m\.?|p\.?m\.?)?\b',
    ).firstMatch(n);
    if (m == null) return null;

    var hour = int.tryParse(m.group(1) ?? '');
    if (hour == null || hour > 23) return null;
    final minute = int.tryParse(m.group(2) ?? '0') ?? 0;
    if (minute > 59) return null;

    final ampm = m.group(3)?.replaceAll('.', '');
    final hasAmPm = ampm != null && ampm.isNotEmpty;

    // Signals that this utterance is about changing the reminder/time.
    const changeWords = [
      'change', 'reschedule', 'move', 'make it', 'set it', 'set the',
      'reminder', 'remind', 'instead', 'update', 'switch it', 'at ',
    ];
    final hasChangeWord = changeWords.any(n.contains);

    // Require either an am/pm token or an explicit change/time word so we
    // don't treat random numbers as a reschedule.
    if (!hasAmPm && !hasChangeWord) return null;

    // Apply am/pm to get 24-hour.
    if (hasAmPm) {
      final isPm = ampm.startsWith('p');
      if (isPm && hour < 12) hour += 12;
      if (!isPm && hour == 12) hour = 0;
    }
    // If no am/pm and the hour is a small daytime-ish number that clearly reads
    // as evening in context is ambiguous; keep as-is (24h interpretation).

    return {'reminderHour': hour, 'reminderMinute': minute};
  }

  /// Handles a parsed command and generates a response.
  /// Returns the command for the UI layer to execute.
  Future<VoiceCommand> _handleCommand(VoiceCommand command) async {
    String response;

    switch (command.type) {
      case VoiceCommandType.setThemeDark:
        response = "Switching to dark mode.";
        break;
      case VoiceCommandType.setThemeLight:
        response = "Switching to light mode.";
        break;
      case VoiceCommandType.setAccentColor:
        final colorName = command.params['colorName'] ?? 'new';
        response = "Changed the accent color to $colorName.";
        break;
      case VoiceCommandType.increaseTextSize:
        response = "Making the text larger.";
        break;
      case VoiceCommandType.decreaseTextSize:
        response = "Making the text smaller.";
        break;
      case VoiceCommandType.resetTextSize:
        response = "Reset text size to default.";
        break;
      case VoiceCommandType.toggleWinterMode:
        final enabled = command.params['enabled'] == true;
        response = enabled ? "Winter mode activated. Enjoy the snow!" : "Winter mode turned off.";
        break;
      case VoiceCommandType.openSettings:
        response = "Opening settings.";
        break;
      case VoiceCommandType.openCheckIn:
        response = "Let me start your check-in.";
        _isInCheckInFlow = true;
        _checkInStep = 0;
        break;
      case VoiceCommandType.openJournal:
        response = "Opening your journal.";
        break;
      case VoiceCommandType.openHome:
        response = "Going to the home screen.";
        break;
      case VoiceCommandType.openIntentions:
        response = "Opening your wellness intentions.";
        break;
      case VoiceCommandType.openHabitBuilder:
        response = "Opening your habit builder.";
        break;
      case VoiceCommandType.createHabit:
        final habitTitle = command.params['title'] as String?;
        if (habitTitle != null && habitTitle.trim().isNotEmpty) {
          // We have the habit name — hand off to the UI to create it; the UI
          // speaks the final confirmation (with the habit + frequency).
          response = "Creating your habit: $habitTitle.";
          _lastCommand = command;
          _addAssistantMessage(response);
          await speak(response);
          notifyListeners();
          return command;
        } else {
          response = "Sure — what habit would you like to add?";
        }
        break;
      case VoiceCommandType.updateHabitReminder:
        // Change the reminder time of the habit currently in context.
        if (_lastHabitId != null) {
          // Hand off to the UI to reschedule; it speaks the final
          // confirmation (with the resolved time and permission state).
          response = "Updating the reminder for "
              "${_lastHabitTitle ?? 'your habit'}.";
          _lastCommand = command;
          _addAssistantMessage(response);
          await speak(response);
          notifyListeners();
          return command;
        } else {
          response =
              "I'm not sure which habit you mean. You can say something like "
              "\"remind me about swimming at 7:30 pm\".";
        }
        break;
      case VoiceCommandType.openChallenges:
        response = "Opening your wellness challenges.";
        break;
      case VoiceCommandType.openNutritionCoach:
        response = "Opening the Nutrition Coach.";
        break;
      case VoiceCommandType.openMealPlanner:
        response = "Opening the Meal Planner.";
        break;
      case VoiceCommandType.openCalorieBudget:
        response = "Opening your Calorie Budget.";
        break;
      case VoiceCommandType.openHydration:
        response = "Opening the Hydration Coach.";
        break;
      case VoiceCommandType.openSleepCoach:
        response = "Opening the Sleep Coach.";
        break;
      case VoiceCommandType.openMeditation:
        response = "Opening Meditation Pal.";
        break;
      case VoiceCommandType.openPeriodTracker:
        response = "Opening your Period Tracker.";
        break;
      case VoiceCommandType.openWeightTracker:
        response = "Opening your Body Weight tracker.";
        break;
      case VoiceCommandType.openMindfulTravel:
        response = "Opening Mindful Travel.";
        break;
      case VoiceCommandType.logWater:
        final ml = command.params['amountMl'];
        if (ml is num && ml > 0 && ml != 250) {
          response = "Logging ${ml.round()} millilitres of water for you.";
        } else {
          response = "Logging a glass of water for you.";
        }
        break;
      case VoiceCommandType.startBreathing:
        response = "Let's take a breath together. Starting a breathing exercise.";
        break;
      case VoiceCommandType.startMeditation:
        response = "Starting a meditation session for you.";
        break;
      case VoiceCommandType.refreshPlan:
        response = "Generating a new plan for you.";
        break;
      case VoiceCommandType.greeting:
        final hour = DateTime.now().hour;
        final timeGreeting = hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening';
        response = "$timeGreeting! I'm your wellness assistant. How can I help you today?";
        break;
      case VoiceCommandType.howAmI:
        response = "You're doing great by checking in with your wellness. Keep it up!";
        break;
      case VoiceCommandType.help:
        response = "I can help you with: changing themes, doing your daily check-in by voice, "
            "adjusting text size, refreshing your plan, and more. Just speak naturally!";
        if (!_isPremium) {
          response +=
              " With Premium, I can also regenerate your plan, adjust your "
              "energy and recovery by voice, and unlock more assistant voices. "
              "You can upgrade to Premium in Settings.";
        }
        break;
      case VoiceCommandType.setEnergyScore:
      case VoiceCommandType.setRecoveryStatus:
      case VoiceCommandType.setAvailableTime:
        if (_isInCheckInFlow) {
          // Inside the guided check-in, keep collecting info as before.
          response = "Got it. Starting your check-in with that information.";
        } else {
          // Standalone adjustment — the UI layer will (for Premium users)
          // update today's energy/recovery/time and regenerate the plan.
          // Surface it as the last command so the sheet can act on it.
          switch (command.type) {
            case VoiceCommandType.setEnergyScore:
              response = "Updating your energy and refreshing today's plan.";
              break;
            case VoiceCommandType.setRecoveryStatus:
              response = "Updating your recovery and refreshing today's plan.";
              break;
            default:
              response = "Updating your available time and refreshing today's plan.";
          }
          _lastCommand = command;
          _addAssistantMessage(response);
          await speak(response);
          notifyListeners();
          return command;
        }
        break;
      case VoiceCommandType.setMood:
        // If not in check-in flow, start it
        if (!_isInCheckInFlow) {
          _isInCheckInFlow = true;
          _checkInStep = 0;
        }
        response = "Got it. Starting your check-in with that information.";
        break;
      case VoiceCommandType.submitCheckIn:
        response = "Submitting your check-in now.";
        break;
      case VoiceCommandType.logIntention:
        final title = command.params['title'] as String?;
        if (title != null && title.trim().isNotEmpty) {
          // We have the one required field — hand off to the UI to create it.
          response = "Adding your wellness intention: $title.";
          _lastCommand = command;
          _addAssistantMessage(response);
          await speak(response);
          notifyListeners();
          return command;
        } else {
          // Ask only for the required field: the intention title.
          _awaitingIntentionTitle = true;
          response = "Sure — what's the wellness intention you'd like to add?";
        }
        break;
      case VoiceCommandType.unknown:
        // Not an app command — treat it as a free-form question and let
        // Gemini 2.5 Flash generate a conversational spoken answer. Fall back
        // to the help prompt only if the AI is unavailable.
        final aiReply = await _generateConversationalReply(command.rawText);
        if (aiReply != null) {
          response = aiReply;
        } else {
          response =
              "I didn't quite catch that. You can ask me to change themes, "
              "start a check-in, refresh your plan, or say 'help' for more options.";
          if (!_isPremium) {
            response +=
                " Tip: upgrade to Premium in Settings to unlock more — like "
                "regenerating your plan and adjusting your check-in by voice.";
          }
        }
        break;
    }

    _addAssistantMessage(response);
    await speak(response);
    _lastCommand = command;
    notifyListeners();
    return command;
  }

  /// Asks the AI for a conversational reply to a free-form question, giving it
  /// the recent transcript so the reply stays in context.
  /// Returns null if the AI is unavailable so the caller can use a fallback.
  Future<String?> _generateConversationalReply(String question) async {
    try {
      return await _aiService.generateVoiceReply(
        question,
        // Exclude the current utterance (already appended to _messages).
        history: _recentHistory(dropLast: 1),
      );
    } catch (e) {
      debugPrint('VoiceCommandService: conversational reply failed: $e');
      return null;
    }
  }

  VoiceCommand? _lastCommand;

  /// Returns the last processed command (for the UI to act on).
  VoiceCommand? get lastCommand => _lastCommand;

  /// Clears the last command after it's been handled by the UI.
  void clearLastCommand() {
    _lastCommand = null;
  }

  // ---------------------------------------------------------------------------
  // Conversational check-in
  // ---------------------------------------------------------------------------

  Future<void> _processCheckInInput(String text) async {
    final command = _parser.parse(text);
    String response;

    switch (_checkInStep) {
      case 0: // Expecting energy
        if (command.type == VoiceCommandType.setEnergyScore) {
          _pendingEnergy = command.params['score'] as int;
          response = "Got it, energy level ${_pendingEnergy}. "
              "How are you feeling emotionally? Calm, anxious, tired, energized, stressed, or content?";
          _checkInStep = 1;
        } else if (command.type == VoiceCommandType.submitCheckIn) {
          response = "Let me finish collecting your info first. How's your energy from 1 to 5?";
        } else {
          // Try to extract energy from natural speech
          final energy = _extractEnergyFromNatural(text);
          if (energy != null) {
            _pendingEnergy = energy;
            response = "I sense your energy is around $energy out of 5. "
                "Now, how's your mood? Calm, anxious, tired, energized, stressed, or content?";
            _checkInStep = 1;
          } else {
            response = "I couldn't determine your energy level. "
                "Could you rate it from 1 to 5, or describe how energetic you feel?";
          }
        }
        break;

      case 1: // Expecting mood
        if (command.type == VoiceCommandType.setMood) {
          _pendingMood = command.params['mood'] as String;
          response = "Feeling ${_pendingMood}. "
              "Last question — how's your body recovering? Well-rested, sore, fatigued, or recovering?";
          _checkInStep = 2;
        } else if (command.type == VoiceCommandType.submitCheckIn) {
          _checkInStep = 3;
          response = "Alright, wrapping up your check-in.";
          _lastCommand = VoiceCommand(
            type: VoiceCommandType.submitCheckIn,
            rawText: text,
          );
        } else {
          // Try mood extraction
          final mood = _extractMoodFromNatural(text);
          if (mood != null) {
            _pendingMood = mood;
            response = "Got it, you're feeling $mood. "
                "How's your body? Well-rested, sore, fatigued, or recovering?";
            _checkInStep = 2;
          } else {
            response = "I couldn't determine your mood. "
                "Try saying: calm, anxious, tired, energized, stressed, or content.";
          }
        }
        break;

      case 2: // Expecting recovery + time
        if (command.type == VoiceCommandType.setRecoveryStatus) {
          _pendingRecovery = command.params['status'] as String;
          response = "Got it. How much time do you have today? "
              "Under 10 minutes, 10 to 20, 20 to 40, 40 to 60, or over an hour?";
          _checkInStep = 3;
        } else if (command.type == VoiceCommandType.setAvailableTime) {
          _pendingTime = command.params['time'] as String;
          response = "Perfect. I have everything I need. Submitting your check-in now.";
          _checkInStep = 4;
          _lastCommand = VoiceCommand(
            type: VoiceCommandType.submitCheckIn,
            rawText: text,
          );
        } else if (command.type == VoiceCommandType.submitCheckIn) {
          _checkInStep = 4;
          response = "Alright, submitting your check-in.";
          _lastCommand = VoiceCommand(
            type: VoiceCommandType.submitCheckIn,
            rawText: text,
          );
        } else {
          final recovery = _extractRecoveryFromNatural(text);
          if (recovery != null) {
            _pendingRecovery = recovery;
            response = "Body status: $recovery. "
                "How much time do you have? Under 10 min, 10-20, 20-40, 40-60, or over an hour?";
            _checkInStep = 3;
          } else {
            response = "Couldn't catch that. Are you well-rested, sore, fatigued, or recovering?";
          }
        }
        break;

      case 3: // Expecting time
        if (command.type == VoiceCommandType.setAvailableTime) {
          _pendingTime = command.params['time'] as String;
          response = "Great! All set. Submitting your check-in.";
          _checkInStep = 4;
          _lastCommand = VoiceCommand(
            type: VoiceCommandType.submitCheckIn,
            rawText: text,
          );
        } else if (command.type == VoiceCommandType.submitCheckIn) {
          _checkInStep = 4;
          response = "Submitting your check-in now.";
          _lastCommand = VoiceCommand(
            type: VoiceCommandType.submitCheckIn,
            rawText: text,
          );
        } else {
          // Try time extraction
          final time = _extractTimeFromNatural(text);
          if (time != null) {
            _pendingTime = time;
            response = "Perfect! Submitting your check-in now.";
            _checkInStep = 4;
            _lastCommand = VoiceCommand(
              type: VoiceCommandType.submitCheckIn,
              rawText: text,
            );
          } else {
            response = "How much time do you have? "
                "Say under 10 minutes, 10 to 20, 20 to 40, 40 to 60, or over an hour.";
          }
        }
        break;

      default:
        response = "Check-in complete!";
        _isInCheckInFlow = false;
    }

    _addAssistantMessage(response);
    await speak(response);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Natural language extraction helpers
  // ---------------------------------------------------------------------------

  int? _extractEnergyFromNatural(String text) {
    final normalized = text.toLowerCase();
    if (normalized.contains('drain') || normalized.contains('exhaust') || normalized.contains('terrible')) return 1;
    if (normalized.contains('low') || normalized.contains('slug') || normalized.contains('bad')) return 2;
    if (normalized.contains('ok') || normalized.contains('decent') || normalized.contains('average')) return 3;
    if (normalized.contains('good') || normalized.contains('nice') || normalized.contains('well')) return 4;
    if (normalized.contains('great') || normalized.contains('amazing') || normalized.contains('fantastic')) return 5;
    return null;
  }

  String? _extractMoodFromNatural(String text) {
    final normalized = text.toLowerCase();
    if (normalized.contains('calm') || normalized.contains('peace') || normalized.contains('relax')) return 'calm';
    if (normalized.contains('anxi') || normalized.contains('worr') || normalized.contains('nerv')) return 'anxious';
    if (normalized.contains('tired') || normalized.contains('sleep') || normalized.contains('drowsy')) return 'tired';
    if (normalized.contains('energi') || normalized.contains('pump') || normalized.contains('hyper')) return 'energized';
    if (normalized.contains('stress') || normalized.contains('overwhelm') || normalized.contains('tense')) return 'stressed';
    if (normalized.contains('content') || normalized.contains('happy') || normalized.contains('good')) return 'content';
    return null;
  }

  String? _extractRecoveryFromNatural(String text) {
    final normalized = text.toLowerCase();
    if (normalized.contains('rest') || normalized.contains('fresh') || normalized.contains('recover')) return 'wellRested';
    if (normalized.contains('sore') || normalized.contains('ach') || normalized.contains('hurt')) return 'sore';
    if (normalized.contains('fatigu') || normalized.contains('drain') || normalized.contains('exhaust')) return 'fatigued';
    if (normalized.contains('recovering') || normalized.contains('mend') || normalized.contains('heal')) return 'recovering';
    return null;
  }

  String? _extractTimeFromNatural(String text) {
    final normalized = text.toLowerCase();
    if (normalized.contains('under 10') || normalized.contains('few min') || normalized.contains('5 min')) return 'under10';
    if (normalized.contains('10') && normalized.contains('20') || normalized.contains('15 min') || normalized.contains('quarter')) return 'range10_20';
    if (normalized.contains('20') && normalized.contains('40') || normalized.contains('30 min') || normalized.contains('half')) return 'range20_40';
    if (normalized.contains('40') && normalized.contains('60') || normalized.contains('45 min') || normalized.contains('hour')) return 'range40_60';
    if (normalized.contains('over') || normalized.contains('more than') || normalized.contains('plenty') || normalized.contains('lots')) return 'over60';
    return null;
  }

  // ---------------------------------------------------------------------------
  // Message helpers
  // ---------------------------------------------------------------------------

  /// Builds the recent conversation transcript for the AI, as an ordered list
  /// of {'role': 'user'|'assistant', 'text': ...} turns.
  ///
  /// Keeps only the last [maxTurns] messages so the context stays small/fast,
  /// and drops the final [dropLast] messages (used to exclude the current
  /// utterance, which is added to [_messages] before parsing).
  List<Map<String, String>> _recentHistory({
    int maxTurns = 8,
    int dropLast = 0,
  }) {
    final end = (_messages.length - dropLast).clamp(0, _messages.length);
    final start = (end - maxTurns).clamp(0, end);
    return _messages
        .sublist(start, end)
        .map((m) => {
              'role': m.isUser ? 'user' : 'assistant',
              'text': m.text,
            })
        .toList();
  }

  void _addUserMessage(String text) {
    _messages.add(VoiceMessage.user(text));
    notifyListeners();
  }

  void _addAssistantMessage(String text) {
    _messages.add(VoiceMessage.assistant(text));
    notifyListeners();
  }
}
