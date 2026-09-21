import 'dart:async';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart';

import '../config/feature_flags.dart';
import 'ai_models.dart';

/// Lifecycle of a real-time Gemini Live conversation.
enum LiveConversationState {
  /// Not connected; idle.
  idle,

  /// Establishing the Live WebSocket session.
  connecting,

  /// Session open — streaming mic audio up and playing model audio down.
  active,

  /// Tearing the session down.
  closing,

  /// A recoverable error occurred (see [LiveConversationService.lastError]).
  error,
}

/// Who spoke a given line of the conversation transcript.
enum LiveSpeaker { user, model }

/// A single committed turn in the conversation transcript.
class LiveTranscriptTurn {
  const LiveTranscriptTurn(this.role, this.text);
  final LiveSpeaker role;
  final String text;
}

/// Abstraction over microphone capture + PCM playback so the Live session logic
/// is testable and doesn't hard-depend on a specific audio plugin yet.
///
/// A concrete implementation (e.g. using `record` for capture at 16 kHz mono
/// PCM16 and `just_audio`/a raw player for 24 kHz PCM playback) is added when
/// the feature graduates from spike to build. Keeping this interface lets the
/// service compile and be unit-tested before that dependency lands.
abstract class LiveAudioIO {
  /// Requests mic permission. Returns true if granted.
  Future<bool> requestPermission();

  /// Starts capturing microphone audio and returns a stream of PCM16 chunks
  /// (16 kHz, mono) suitable for [InlineDataPart] with mime type 'audio/pcm'.
  Stream<Uint8List> startCapture();

  /// Stops microphone capture.
  Future<void> stopCapture();

  /// Pauses microphone capture (hardware mic off) without ending the stream —
  /// used for true half-duplex so the model's speaker output cannot be
  /// captured and echoed back while it's talking.
  Future<void> pauseCapture();

  /// Resumes microphone capture after [pauseCapture].
  Future<void> resumeCapture();

  /// Plays a chunk of PCM16 audio (24 kHz, mono) returned by the model.
  Future<void> playChunk(Uint8List pcm);

  /// Plays a short, soft "thinking" cue (a gentle tone) through the same
  /// playback engine while the model prepares its reply. No-op if unsupported.
  Future<void> playThinkingCue();

  /// Stops any in-progress playback (used for barge-in).
  Future<void> stopPlayback();

  /// Estimated time until all audio fed so far has finished playing.
  ///
  /// Because playback lags receive (chunks are buffered inside the player),
  /// this lets the service know the model is still audibly speaking even when
  /// no *new* chunk has arrived recently — so it doesn't re-open the mic or end
  /// the turn mid-sentence on a long reply. Returns [Duration.zero] when
  /// nothing is buffered/playing.
  Duration get playbackRemaining => Duration.zero;

  /// Releases audio resources.
  Future<void> dispose();
}

/// Executes a tool/function the model asked for during a live conversation and
/// returns the result payload to send back to the model.
///
/// [name] is the declared function name (e.g. 'create_habit') and [args] are
/// the model-supplied arguments. Return a JSON-serializable map describing the
/// outcome (e.g. {'status': 'ok', 'message': 'Created "Swimming"'}). The owner
/// (UI layer) provides this so the service stays free of app-state deps.
typedef LiveToolHandler = Future<Map<String, Object?>> Function(
    String name, Map<String, Object?> args);

/// Premium, real-time "Conversation Mode" backed by the Gemini Live API
/// (Firebase AI Logic).
///
/// - Gated by [FeatureFlags.liveConversationMode] AND Premium status, so it can
///   never run in production until explicitly enabled.
/// - Wires the real `liveGenerativeModel` → `connect()` → `receive()` flow,
///   delegating mic/playback to an injected [LiveAudioIO] and tool EXECUTION to
///   an injected [LiveToolHandler].
/// - Intentionally separate from `VoiceCommandService` so the shipping
///   command-and-control assistant is never destabilized by this experiment.
///
/// IMPORTANT backend note: `liveGenerativeModel` is only supported on the
/// **Agent Platform (Vertex)** backend (it throws on the Developer API
/// backend), so this uses `FirebaseAI.agentPlatform()` (location `global`)
/// with App Check — matching how [AIService] is wired. (Newer SDK/docs move
/// Live to the Developer API backend; revisit on upgrade.)
class LiveConversationService extends ChangeNotifier {
  LiveConversationService({
    LiveAudioIO? audioIO,
    FirebaseAI? ai,
  })  : _audioIO = audioIO,
        _ai = ai;

  /// Live-capable model id, sourced from the central [kGeminiLiveModel] config
  /// (default `gemini-live-2.5-flash-native-audio` — the current Stable
  /// Live/BidiGenerateContent model on the Agent Platform / Vertex endpoint).
  /// NOTE: per the Firebase AI Logic docs, the Agent Platform does NOT support
  /// any Gemini Live 3.x models, so the Live path stays on the 2.5 line even
  /// though standard generation is on 3.5. Kept overridable because Live model
  /// ids are retired/renamed periodically — do not hardcode long-term.
  ///
  /// Overridable at build time for debugging which model the Live/BidiGenerate
  /// endpoint accepts (a wrong/retired model closes the WebSocket with code
  /// 1008 — policy violation), e.g.:
  ///   flutter run --dart-define=LIVE_MODEL_ID=gemini-live-2.5-flash-preview
  ///
  /// Served via firebase_ai 4.0.0 + FirebaseAI.agentPlatform() (location
  /// `global`, where the Live/BidiGenerateContent models are served — fixing
  /// the 1008 "model not found" error seen with vertexAI() + us-central1).
  static const String _defaultModelId = kGeminiLiveModel;

  final LiveAudioIO? _audioIO;
  final FirebaseAI? _ai;

  /// Optional handler invoked when the model requests a tool/function call.
  /// Set by the owner before [start]. If null, tool calls are acknowledged
  /// with an error result so the model can recover gracefully.
  LiveToolHandler? onToolCall;

  /// The tool/function declarations exposed to the model. Set by the owner
  /// before [start] to match [onToolCall].
  List<Tool> tools = const [];

  /// Fired when the USER'S transcribed speech indicates they want to end the
  /// conversation ("bye", "let's end", "I'm done", etc.). The Live model is
  /// unreliable at calling the end_conversation tool for spoken goodbyes, so we
  /// detect the intent app-side from the input transcription and let the owner
  /// (ConversationModeSheet) tear the session down. Fires at most once.
  VoidCallback? onUserEndIntent;
  bool _endIntentFired = false;
  // Armed when the user says goodbye; the actual end is deferred until the
  // pal finishes its goodbye reply (next turnComplete).
  bool _endPending = false;

  LiveConversationState _state = LiveConversationState.idle;
  LiveConversationState get state => _state;

  // Half-duplex echo control: while the model is speaking we pause the mic (so
  // the loudspeaker output isn't re-captured and echoed back), resuming on the
  // model's turnComplete. Two separate audio engines (record + flutter_pcm_sound)
  // mean iOS hardware AEC can't cancel the echo, so we gate instead.
  bool _modelSpeaking = false;
  // Ensures the soft "thinking" cue plays at most once per user turn.
  bool _thinkingCuePlayed = false;
  // Timestamp of the model's most recent audio, used to add a short tail before
  // the mic resumes so the speaker's trailing audio doesn't leak in.
  DateTime _lastModelAudioAt = DateTime.fromMillisecondsSinceEpoch(0);

  // Watchdog: if the mic stays gated (paused) for longer than this with no new
  // model audio arriving, we assume a missed/dropped turnComplete and force the
  // mic back open so the conversation can't silently deadlock ("stops
  // responding"). This is the safety net behind the turnComplete resume.
  static const Duration _micGateMaxHold = Duration(seconds: 4);
  Timer? _micWatchdog;

  // Stall detection: while the model is mid-turn (speaking) but no audio has
  // arrived for [_stallThreshold] with playback already drained, the session
  // is likely stuck on the network (slow/stalled socket, weak connection). We
  // surface this to the UI as "reconnecting" instead of hanging silently. The
  // flag clears the instant new audio arrives, a turn completes, or the turn
  // is torn down. Kept shorter than [_micGateMaxHold] so the user sees the hint
  // slightly before the watchdog force-resumes the mic.
  static const Duration _stallThreshold = Duration(seconds: 2);
  bool _stalled = false;

  /// Whether the live conversation appears stalled on the network: the pal was
  /// mid-reply but no audio has arrived for a couple of seconds. The UI can use
  /// this to show a subtle "Reconnecting…" / "Check your connection" hint.
  /// Only meaningful while [state] is [LiveConversationState.active].
  bool get isStalled => _stalled && _state == LiveConversationState.active;

  void _setStalled(bool value) {
    if (_stalled == value) return;
    _stalled = value;
    if (kDebugMode) {
      debugPrint('LiveConversationService: stalled=$value');
    }
    notifyListeners();
  }

  String _lastTranscript = '';

  /// The latest transcription of the model's spoken reply (from the server's
  /// output audio transcription). Useful for showing live captions in the UI.
  String get lastTranscript => _lastTranscript;

  /// The model's CURRENT spoken reply as live captions: the in-progress model
  /// turn while it's speaking, otherwise the most recently completed model
  /// reply. Empty until the pal has said something. Updates as the reply
  /// streams so the UI can show it like movie subtitles.
  String get currentReply {
    // While the pal is mid-reply, the running buffer has the freshest text.
    if (_modelTurnBuf.isNotEmpty) return _modelTurnBuf.toString().trim();
    // Otherwise show the last committed model turn (keeps it on screen).
    for (var i = _transcript.length - 1; i >= 0; i--) {
      if (_transcript[i].role == LiveSpeaker.model &&
          _transcript[i].text.trim().isNotEmpty) {
        return _transcript[i].text.trim();
      }
    }
    return '';
  }

  /// One line of the conversation transcript.
  final List<LiveTranscriptTurn> _transcript = [];

  /// The full, ordered two-sided conversation transcript (user + assistant),
  /// accumulated across the whole session. Empty until the first speech is
  /// transcribed. Used to save the conversation as a Reflection afterwards.
  List<LiveTranscriptTurn> get transcript =>
      List.unmodifiable(_transcript);

  /// Whether there is any real conversation content worth offering to save.
  bool get hasTranscript =>
      _transcript.any((t) => t.text.trim().isNotEmpty);

  /// The transcript rendered as plain text with role labels, e.g.
  /// "You: ...\nPal: ...". Suitable for summarization or storage.
  String get transcriptText => _transcript
      .where((t) => t.text.trim().isNotEmpty)
      .map((t) => '${t.role == LiveSpeaker.user ? 'You' : 'Pal'}: ${t.text}')
      .join('\n');

  // Transcription arrives incrementally per turn. We buffer the in-progress
  // text for each side and commit it as a turn when that side stops (the other
  // side starts, or the turn completes), so the saved transcript reads as clean
  // alternating turns rather than fragmented partials.
  final StringBuffer _userTurnBuf = StringBuffer();
  final StringBuffer _modelTurnBuf = StringBuffer();

  /// Appends transcription text for [speaker], buffering partials and merging
  /// them into a single turn until the speaker changes.
  void _appendTranscript(LiveSpeaker speaker, String text) {
    final t = text.trim();
    if (t.isEmpty) return;
    if (speaker == LiveSpeaker.user) {
      // ECHO GUARD: mic-vs-speaker isolation can never be perfect (two separate
      // audio engines), so the mic sometimes catches the pal's own voice and
      // the server transcribes it as USER input. Rather than rely only on the
      // mic gate, we reject "user" text that is really an echo of what the pal
      // just said — a content-level check on the actual transcription output.
      if (_looksLikeModelEcho(t)) {
        if (kDebugMode) {
          debugPrint('LiveConversationService: dropped echoed user text: "$t"');
        }
        return;
      }
      // Committing a new user turn flushes any pending model turn first.
      _flushModelTurn();
      _userTurnBuf.write(_userTurnBuf.isEmpty ? t : ' $t');
      // Check the current buffer AND this fresh fragment for an end phrase.
      // (The buffer can be flushed when the model starts speaking, so also
      // matching the raw fragment makes "bye" detection reliable.)
      _maybeDetectEndIntent('${_userTurnBuf.toString()} $t');
    } else {
      _flushUserTurn();
      _modelTurnBuf.write(_modelTurnBuf.isEmpty ? t : ' $t');
      _lastTranscript = t;
      // Remember what the pal recently said so the echo guard above can
      // recognise it if the mic loops it back as "user" input.
      _rememberModelSpeech(t);
    }
    notifyListeners();
  }

  // Rolling record of the pal's recent spoken words (lowercased) + when, used
  // to detect when a "user" transcription is actually an echo of the pal.
  final List<({String text, DateTime at})> _recentModelSpeech = [];

  void _rememberModelSpeech(String text) {
    _recentModelSpeech.add((text: text.toLowerCase(), at: DateTime.now()));
    // Keep only the last few seconds' worth so old replies don't false-match.
    final cutoff = DateTime.now().subtract(const Duration(seconds: 6));
    _recentModelSpeech.removeWhere((e) => e.at.isBefore(cutoff));
    if (_recentModelSpeech.length > 12) {
      _recentModelSpeech.removeRange(0, _recentModelSpeech.length - 12);
    }
  }

  /// Whether a supposed "user" utterance is really the pal's own voice looped
  /// back through the mic. Two independent signals, either is enough:
  ///  1. Timing: it arrived while the model was speaking or within a short
  ///     window of the pal's last audio — a genuine barge-in would come via the
  ///     server `interrupted` path, not as clean input mid-playback.
  ///  2. Content: the words overlap what the pal recently said.
  bool _looksLikeModelEcho(String userText) {
    final sinceModelAudio =
        DateTime.now().difference(_lastModelAudioAt).inMilliseconds;
    final playing = (_audioIO?.playbackRemaining ?? Duration.zero) >
        const Duration(milliseconds: 50);

    // STRONGEST SIGNAL — the pal currently has the floor. The mic is gated
    // while the model is speaking / its audio is still playing, so a "user"
    // transcription arriving now is the speaker leaking into the mic, not real
    // user speech (a genuine barge-in comes via the server `interrupted`
    // path, not as clean input transcription). Drop it regardless of content.
    if (_modelSpeaking || playing) return true;

    // Otherwise only scrutinise text that arrived shortly AFTER the pal's audio
    // (the tail window); anything later is clearly the user's own turn.
    if (sinceModelAudio >= 1500) return false;

    final u = userText.toLowerCase();
    for (final spoken in _recentModelSpeech) {
      final m = spoken.text;
      if (m.isEmpty) continue;
      // Echo if the user text is contained in the pal's words (or vice versa),
      // or they share a meaningful word overlap.
      if (m.contains(u) || u.contains(m) || _wordOverlap(u, m) >= 0.34) {
        return true;
      }
    }
    return false;
  }

  /// Fraction of [a]'s words that also appear in [b] (0..1). Simple bag-of-words
  /// overlap — enough to catch echoed fragments without heavy NLP.
  double _wordOverlap(String a, String b) {
    final aw = a.split(RegExp(r'\s+')).where((w) => w.length > 2).toList();
    if (aw.isEmpty) return 0;
    final bw = b.split(RegExp(r'\s+')).toSet();
    final hits = aw.where(bw.contains).length;
    return hits / aw.length;
  }

  void _flushUserTurn() {
    if (_userTurnBuf.isEmpty) return;
    _transcript.add(
        LiveTranscriptTurn(LiveSpeaker.user, _userTurnBuf.toString().trim()));
    _userTurnBuf.clear();
  }

  void _flushModelTurn() {
    if (_modelTurnBuf.isEmpty) return;
    _transcript.add(
        LiveTranscriptTurn(LiveSpeaker.model, _modelTurnBuf.toString().trim()));
    _modelTurnBuf.clear();
  }

  /// Commits any pending buffered turns (called at turn/session boundaries).
  void _flushTranscriptBuffers() {
    _flushUserTurn();
    _flushModelTurn();
  }

  /// End-of-conversation phrases we watch for in the user's transcribed speech.
  static final RegExp _endIntentPattern = RegExp(
    r"\b("
    r"good\s?bye|bye bye|bye|see you|see ya|"
    r"(let'?s|let us|we can|i want to|i'?d like to|can we|please)\s+"
    r"(end|stop|finish|wrap up|wrap this up|close|be done)|"
    r"end (the|this) (conversation|chat|call|discussion|session)|"
    r"stop (the|this) (conversation|chat|call|discussion|session)|"
    r"(i'?m|i am|we'?re|we are) (done|finished)|"
    r"that'?s (all|it|enough)|"
    r"talk (to you )?later|gotta go|got to go|hang up|"
    r"thanks?,? (that'?s all|bye|goodbye)"
    r")\b",
    caseSensitive: false,
  );

  /// If [utterance] looks like the user asking to end, ARM the pending-end
  /// flag (once). We don't end immediately — we let the pal speak its goodbye
  /// reply and end after that turn completes (see [_onServerResponse]). This is
  /// the reliable path — the Live model often just speaks a goodbye instead of
  /// calling the end_conversation tool.
  void _maybeDetectEndIntent(String utterance) {
    if (_endIntentFired || _endPending) return;
    if (onUserEndIntent == null) return;
    if (_endIntentPattern.hasMatch(utterance.toLowerCase())) {
      _endPending = true;
      if (kDebugMode) {
        debugPrint('LiveConversationService: end intent detected in '
            '"$utterance" — ending after the pal\'s goodbye.');
      }
      // Fallback: if the pal never produces a goodbye turn at all, end anyway
      // after a wait. This DEFERS to the drain loop if the pal is actually
      // mid sign-off, so a long goodbye is never truncated.
      _endFallbackTimer?.cancel();
      _endFallbackTimer =
          Timer(const Duration(seconds: 6), _onEndFallbackTimeout);
    }
  }

  Timer? _endFallbackTimer;

  // True once the pal's goodbye turn has been reported complete by the server.
  // After this, NO more audio chunks will arrive for that turn, so the only
  // thing left to wait for is the on-device player to drain.
  bool _endTurnCompleteSeen = false;
  // Guards against spawning multiple concurrent drain-poll loops (turnComplete
  // can fire more than once if the pal produces a follow-up turn).
  bool _endWaitActive = false;

  /// Waits for the pal's sign-off to finish actually coming out of the speaker
  /// before ending, so the user always hears the whole thing.
  ///
  /// This is PROGRESS-driven, not deadline-driven — that distinction matters:
  ///  - A short "Take care!" ends almost immediately (as soon as the few
  ///    hundred ms of buffered audio drains).
  ///  - A long multi-sentence sign-off plays to completion however long it
  ///    takes; there is no fixed ceiling that could truncate it.
  ///  - A genuinely broken/stalled pipeline still ends promptly, because we
  ///    bail when no PROGRESS has been made (no new audio arriving AND the
  ///    playback buffer not shrinking) — not when some arbitrary timer expires.
  void _scheduleEndAfterGoodbye() {
    if (_endWaitActive) return; // already polling
    _endWaitActive = true;

    // Player is considered drained below this (avoids chasing the last few ms).
    const drainThreshold = Duration(milliseconds: 120);
    // Small settle after drain so the final syllable isn't clipped by the
    // abrupt stopPlayback() inside stop().
    const tailSettle = Duration(milliseconds: 200);
    // If the turn is NOT yet complete we also want a brief network-quiet gap,
    // so we don't end between two chunks of an in-progress sentence.
    const quietGap = Duration(milliseconds: 700);
    // Bail only when nothing is progressing: no new audio AND the buffer isn't
    // draining. This is the real "something is wrong" signal.
    const noProgressTimeout = Duration(seconds: 3);
    // Absolute backstop purely to prevent a leaked poll loop. Deliberately
    // generous so it can never truncate a legitimately long sign-off.
    const absoluteCeiling = Duration(minutes: 2);

    final startedAt = DateTime.now();
    var lastProgressAt = DateTime.now();
    var lastRemainingMs = (_audioIO?.playbackRemaining ?? Duration.zero)
        .inMilliseconds;
    var lastAudioAt = _lastModelAudioAt;

    void finishAfterSettle() {
      Future.delayed(tailSettle, () {
        if (!_endPending || _endIntentFired) return;
        _endWaitActive = false;
        _fireEndIfPending();
      });
    }

    void check() {
      if (!_endPending || _endIntentFired) {
        _endWaitActive = false;
        return;
      }

      final now = DateTime.now();
      final remaining = _audioIO?.playbackRemaining ?? Duration.zero;
      final remainingMs = remaining.inMilliseconds;

      // --- Progress accounting -------------------------------------------
      // Progress = new audio arrived from the network, OR the player drained
      // some of its buffer. Either means the pipeline is alive and the user is
      // still hearing (or about to hear) the pal.
      final newAudioArrived = _lastModelAudioAt.isAfter(lastAudioAt);
      final bufferDrained = remainingMs < lastRemainingMs - 20;
      if (newAudioArrived || bufferDrained) {
        lastProgressAt = now;
        lastAudioAt = _lastModelAudioAt;
      }
      lastRemainingMs = remainingMs;

      // --- Normal completion ---------------------------------------------
      final playbackDrained = remainingMs <= drainThreshold.inMilliseconds;
      // Once the server says the turn is complete, no more chunks are coming,
      // so draining the player is sufficient → fast exit for short goodbyes.
      // If the turn ISN'T complete yet, also require a short network-quiet gap
      // so we don't cut in between chunks of an in-flight sentence.
      final networkSettled = _endTurnCompleteSeen ||
          now.difference(_lastModelAudioAt) >= quietGap;

      if (playbackDrained && networkSettled) {
        if (kDebugMode) {
          debugPrint('LiveConversationService: goodbye drained after '
              '${now.difference(startedAt).inMilliseconds}ms '
              '(turnComplete=$_endTurnCompleteSeen) — ending.');
        }
        finishAfterSettle();
        return;
      }

      // --- Stall / safety bail -------------------------------------------
      final sinceProgress = now.difference(lastProgressAt);
      if (sinceProgress >= noProgressTimeout) {
        if (kDebugMode) {
          debugPrint('LiveConversationService: goodbye wait saw no progress '
              'for ${sinceProgress.inMilliseconds}ms '
              '(remaining=${remainingMs}ms) — ending anyway.');
        }
        finishAfterSettle();
        return;
      }
      if (now.difference(startedAt) >= absoluteCeiling) {
        if (kDebugMode) {
          debugPrint('LiveConversationService: goodbye wait hit absolute '
              'ceiling — ending.');
        }
        _endWaitActive = false;
        _fireEndIfPending();
        return;
      }

      // Poll at 100ms so a short sign-off ends snappily.
      Future.delayed(const Duration(milliseconds: 100), check);
    }

    // Give playback a beat to actually start before the first sample, so we
    // don't mistake "hasn't started yet" for "already drained".
    Future.delayed(const Duration(milliseconds: 250), check);
  }

  /// Public entry point for external end triggers (e.g. the model calls the
  /// `end_conversation` tool). Arms the same defer-then-drain path used by the
  /// spoken-goodbye detector so the pal's final phrase is never clipped.
  /// Safe to call multiple times — only the first arms the end.
  void deferEnd() {
    if (_endIntentFired || _endPending) return;
    if (onUserEndIntent == null) return;
    _endPending = true;
    if (kDebugMode) {
      debugPrint('LiveConversationService: deferEnd() — ending after the '
          "pal's goodbye finishes playing.");
    }
    // Fallback: end anyway if we somehow never see a turnComplete AND no
    // playback comes through. Defers to the drain loop if the pal IS speaking.
    _endFallbackTimer?.cancel();
    _endFallbackTimer =
        Timer(const Duration(seconds: 6), _onEndFallbackTimeout);
    // Start the drain wait right away. It tolerates the pal still streaming
    // (it requires a network-quiet gap until turnComplete arrives), so this is
    // safe whether or not the pal is mid-sentence.
    _scheduleEndAfterGoodbye();
  }

  /// Fallback path for when the pal never produces a goodbye turn at all (no
  /// turnComplete, no audio). Critically, this DEFERS to an in-flight drain
  /// wait: if [_scheduleEndAfterGoodbye] is actively polling, the pal is mid
  /// sign-off and we must NOT cut it off — the drain loop owns the ending.
  void _onEndFallbackTimeout() {
    if (!_endPending || _endIntentFired) return;
    if (_endWaitActive) {
      if (kDebugMode) {
        debugPrint('LiveConversationService: end fallback fired but the drain '
            'wait is active (pal still speaking) — deferring to it.');
      }
      return;
    }
    if (kDebugMode) {
      debugPrint('LiveConversationService: end fallback fired with no goodbye '
          'turn — ending.');
    }
    _fireEndIfPending();
  }

  /// Fires the end callback (once) after the pal has finished its goodbye.
  void _fireEndIfPending() {
    if (!_endPending || _endIntentFired) return;
    _endIntentFired = true;
    _endPending = false;
    _endWaitActive = false;
    _endFallbackTimer?.cancel();
    _endFallbackTimer = null;
    onUserEndIntent?.call();
  }

  String? _lastError;
  String? get lastError => _lastError;

  /// Whether the feature is even available to attempt (flag on).
  static bool get isAvailable => FeatureFlags.liveConversationMode;

  LiveSession? _session;

  /// Starts a real-time conversation session.
  ///
  /// [isPremium] must be true — the caller (UI) is responsible for showing the
  /// upsell to Free users instead of calling this. [systemInstruction] seeds
  /// the assistant persona; [modelId] overrides the default Live model.
  Future<void> start({
    required bool isPremium,
    String? systemInstruction,
    String? modelId,
  }) async {
    if (!isAvailable) {
      _fail('Conversation Mode is not enabled in this build.');
      return;
    }
    if (!isPremium) {
      // Defensive: the UI should gate this, but never start for a Free user.
      _fail('Conversation Mode is a Premium feature.');
      return;
    }
    if (_state == LiveConversationState.connecting ||
        _state == LiveConversationState.active) {
      return; // Already running.
    }
    final audio = _audioIO;
    if (audio == null) {
      _fail('Audio pipeline is not wired up yet.');
      return;
    }

    _setState(LiveConversationState.connecting);
    _lastError = null;
    _stalled = false;
    _modelSpeaking = false;
    _lastModelAudioAt = DateTime.fromMillisecondsSinceEpoch(0);
    _lastTranscript = '';
    _transcript.clear();
    _userTurnBuf.clear();
    _modelTurnBuf.clear();
    _endIntentFired = false;
    _endPending = false;
    _endTurnCompleteSeen = false;
    _endWaitActive = false;
    _thinkingCuePlayed = false;
    _recentModelSpeech.clear();

    try {
      final granted = await audio.requestPermission();
      if (!granted) {
        _fail('Microphone permission is needed for Conversation Mode.');
        return;
      }

      // firebase_ai 4.0.0: use agentPlatform() instead of the deprecated
      // vertexAI(). agentPlatform() defaults to location='global', which is
      // where the Live/BidiGenerateContent models (e.g. gemini-live-2.5-flash)
      // are served. The old vertexAI() + us-central1 combination caused a 1008
      // "Publisher model was not found" close on every Live connect().
      final ai = _ai ??
          FirebaseAI.agentPlatform();
      // Resolve the model id: explicit override, else the default constant.
      final resolvedModel = modelId ?? _defaultModelId;
      final liveModel = ai.liveGenerativeModel(
        model: resolvedModel,
        liveGenerationConfig: LiveGenerationConfig(
          responseModalities: [ResponseModalities.audio],
          // Ask the server for text transcriptions of BOTH sides of the
          // conversation: the model's spoken reply (output) and the user's
          // speech (input). We stitch these into a running two-sided transcript
          // (see _appendTranscript) so the whole conversation can be saved as a
          // Reflection afterwards, and surfaced live as captions.
          inputAudioTranscription: AudioTranscriptionConfig(),
          outputAudioTranscription: AudioTranscriptionConfig(),
          // Keep spoken replies concise by capping output, and make turn-taking
          // snappy + interruptible: detect speech eagerly, respond soon after a
          // short silence, and let the user barge in to cut off the reply.
          maxOutputTokens: 512,
          temperature: 0.8,
          realtimeInputConfig: RealtimeInputConfig(
            automaticActivityDetection: ActivityDetectionConfig(
              startSensitivity: Sensitivity.high,
              endSensitivity: Sensitivity.high,
              silenceDurationMS: 500,
            ),
            activityHandling: ActivityHandling.interrupt,
          ),
        ),
        tools: tools.isEmpty ? null : tools,
        systemInstruction:
            systemInstruction != null ? Content.system(systemInstruction) : null,
      );

      _session = await liveModel.connect();
      _setState(LiveConversationState.active);
      _startMicWatchdog();

      // Stream mic audio up as realtime PCM chunks. The Live API expects raw
      // 16-bit LE PCM at 16 kHz, tagged 'audio/pcm;rate=16000'. firebase_ai
      // 4.0.0 deprecates sendMediaStream() in favour of sendAudioRealtime(),
      // which emits the current `realtime_input.audio` shape the model's
      // voice-activity-detection expects — using the old media_chunks path can
      // leave the model waiting silently (stuck on "Listening").
      final micStream = audio.startCapture();
      unawaited(_pumpMic(micStream));

      // Continuously receive turns. receive() ends its stream when a turn
      // completes, so we re-subscribe for the next turn until the session is
      // closed — that's what makes it a back-and-forth conversation.
      unawaited(_receiveLoop());
    } catch (e) {
      _fail('Could not start Conversation Mode: $e');
    }
  }

  /// Pumps captured mic PCM chunks to the model as realtime audio input.
  Future<void> _pumpMic(Stream<Uint8List> micStream) async {
    final session = _session;
    if (session == null) return;
    try {
      await for (final data in micStream) {
        if (_state != LiveConversationState.active || _session == null) break;
        // Half-duplex gate: don't forward mic audio while the model is speaking
        // OR while its audio is still playing out of the speaker, so the
        // loudspeaker output isn't captured and transcribed back as the user
        // (the "pal hears himself" echo). `_modelSpeaking` is cleared on the
        // server's turnComplete; the extra guards below cover the gap where
        // turnComplete arrives but buffered audio is still playing.
        //
        // 1. `_modelSpeaking` — model has the floor.
        // 2. `playbackRemaining` — audio is still audibly playing (the accurate
        //    signal; playback lags receive, so a fixed time tail isn't enough).
        // 3. a short fixed tail after the last received chunk as a final safety
        //    net for the moment right after playback drains.
        final remaining = _audioIO?.playbackRemaining ?? Duration.zero;
        final sinceAudio =
            DateTime.now().difference(_lastModelAudioAt).inMilliseconds;
        if (_modelSpeaking ||
            remaining > const Duration(milliseconds: 200) ||
            sinceAudio < 800) {
          continue;
        }
        await session
            .sendAudioRealtime(InlineDataPart('audio/pcm;rate=16000', data));
      }
    } catch (e) {
      if (kDebugMode) debugPrint('LiveConversationService: mic pump error: $e');
    }
  }

  Timer? _resumeTimer;

  /// Reopens the mic a short tail after the model finishes speaking. Rearms
  /// itself if the model produced more audio during the tail, so a late chunk
  /// can never leave the mic permanently gated.
  void _scheduleMicResume() {
    _resumeTimer?.cancel();
    _resumeTimer = Timer(const Duration(milliseconds: 500), () {
      if (_state != LiveConversationState.active) return;
      if (_modelSpeaking) {
        // A late chunk re-armed speaking; try again shortly instead of bailing.
        _scheduleMicResume();
        return;
      }
      // The transcript's turnComplete arrives before the audio finishes
      // playing (playback lags receive). If audio is still buffered/playing,
      // wait for it to drain before re-opening the mic — otherwise the mic
      // captures the speaker's own tail and can cut off the reply via a VAD
      // interrupt.
      final remaining = _audioIO?.playbackRemaining ?? Duration.zero;
      if (remaining > const Duration(milliseconds: 250)) {
        _scheduleMicResume();
        return;
      }
      // Playback has drained. Wait a short settle before re-opening the
      // hardware mic so the speaker's acoustic tail + iOS render buffer fully
      // clear — otherwise the mic can catch the last of the pal's own voice and
      // it gets transcribed back as the user ("pal hears himself").
      Timer(const Duration(milliseconds: 350), () {
        if (_state != LiveConversationState.active) return;
        if (_modelSpeaking ||
            (_audioIO?.playbackRemaining ?? Duration.zero) >
                const Duration(milliseconds: 200)) {
          // A late chunk started more audio during the settle — reschedule.
          _scheduleMicResume();
          return;
        }
        unawaited(_audioIO?.resumeCapture() ?? Future.value());
      });
    });
  }

  /// Periodically checks that the mic isn't stuck gated. If the model is
  /// "speaking" but no audio has arrived for [_micGateMaxHold], we treat the
  /// turn as finished (a dropped/late turnComplete) and force the mic open so
  /// the conversation recovers instead of hanging.
  void _startMicWatchdog() {
    _micWatchdog?.cancel();
    _micWatchdog = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_state != LiveConversationState.active) {
        _setStalled(false);
        return;
      }
      if (!_modelSpeaking) {
        _setStalled(false);
        return;
      }
      // Don't fire while audio is still audibly playing: on a long reply the
      // model can pause >_micGateMaxHold between received chunks while earlier
      // audio is still buffered in the player. Re-opening the mic then would
      // capture the speaker's own output and trip a VAD `interrupted`, which
      // releases playback mid-sentence. Only treat the turn as stalled once the
      // buffered audio has drained too.
      final remaining = _audioIO?.playbackRemaining ?? Duration.zero;
      if (remaining > const Duration(milliseconds: 250)) {
        // Still audibly playing buffered audio — not stalled.
        _setStalled(false);
        return;
      }
      final sinceAudio = DateTime.now().difference(_lastModelAudioAt);
      // The pal was replying but the audio stream has gone quiet with nothing
      // left to play — surface a network hint before the hard mic recovery.
      _setStalled(sinceAudio >= _stallThreshold);
      if (sinceAudio >= _micGateMaxHold) {
        if (kDebugMode) {
          debugPrint('LiveConversationService: mic watchdog fired after '
              '${sinceAudio.inMilliseconds}ms (playback drained) — '
              'force-resuming mic.');
        }
        _modelSpeaking = false;
        unawaited(_audioIO?.resumeCapture() ?? Future.value());
      }
    });
  }

  void _stopMicWatchdog() {
    _micWatchdog?.cancel();
    _micWatchdog = null;
    _resumeTimer?.cancel();
    _resumeTimer = null;
    _setStalled(false);
  }

  /// Drives the receive stream turn-by-turn until the session ends.
  Future<void> _receiveLoop() async {
    final session = _session;
    if (session == null) return;
    try {
      // receive() is a long-lived stream for the whole session in firebase_ai
      // 4.0.0 (it does NOT end per turn), so turn boundaries must be detected
      // from the `turnComplete` message field, handled in _onServerResponse.
      await for (final response in session.receive()) {
        if (_state != LiveConversationState.active || _session == null) break;
        await _onServerResponse(response);
      }
    } catch (e) {
      // The error (incl. any WebSocket closeReason) is surfaced to the UI.
      if (kDebugMode) {
        debugPrint('LiveConversationService: receive error: $e');
      }
      if (_state == LiveConversationState.active) {
        _fail('Live session error: $e');
      }
    }
  }

  /// Handles a response from the model: plays streamed audio, honors barge-in
  /// interruptions, and dispatches tool calls to [onToolCall].
  Future<void> _onServerResponse(LiveServerResponse response) async {
    final audio = _audioIO;
    if (audio == null) return;
    // Any message from the server means the socket is alive again — clear any
    // "reconnecting" hint we were showing.
    _setStalled(false);
    final message = response.message;
    try {
      if (message is LiveServerContent) {
        // Model asked to interrupt (user barged in) — stop current playback.
        if (message.interrupted == true) {
          _modelSpeaking = false;
          await audio.stopPlayback();
          unawaited(audio.resumeCapture());
          return;
        }
        // Turn finished: re-open the mic so the user can speak again. This is
        // the signal that keeps the back-and-forth going (receive() itself does
        // not end per turn). Without handling this the mic stays gated after the
        // first reply and the model appears to "stop replying".
        if (message.turnComplete == true) {
          _modelSpeaking = false;
          _lastModelAudioAt = DateTime.now();
          // Resume the mic after a short tail so the speaker's trailing audio
          // finishes playing before the mic re-opens (prevents a final echo).
          // Self-rearming: if a late audio chunk flips _modelSpeaking back on
          // during the tail, we reschedule instead of silently giving up — the
          // old code cancelled the resume in that case and the mic could stay
          // gated forever (a cause of the "stops responding" stall).
          _scheduleMicResume();
        }
        // Capture both sides' transcription into the running transcript.
        final inT = message.inputTranscription?.text;
        if (inT != null && inT.trim().isNotEmpty) {
          _appendTranscript(LiveSpeaker.user, inT);
          // The user just said something and the pal hasn't started replying
          // yet — play a soft "thinking" cue once so the pause feels alive.
          if (!_modelSpeaking && !_thinkingCuePlayed) {
            _thinkingCuePlayed = true;
            unawaited(audio.playThinkingCue());
          }
        }
        final outT = message.outputTranscription?.text;
        if (outT != null && outT.trim().isNotEmpty) {
          _appendTranscript(LiveSpeaker.model, outT);
        }
        // On turn boundary, commit any buffered partials as clean turns.
        if (message.turnComplete == true) {
          _flushTranscriptBuffers();
          // If the user asked to end, the pal has finished GENERATING its
          // goodbye — but the audio may still be buffered on-device and playing
          // out of the speaker. Mark the turn complete (which lets the drain
          // wait skip its network-quiet gap and exit as soon as the player
          // empties → short sign-offs end fast) and make sure the wait is
          // running.
          if (_endPending) {
            _endTurnCompleteSeen = true;
            _scheduleEndAfterGoodbye();
          }
        }
        // As soon as the model produces ANY turn content it has taken the floor:
        // pause the mic so its loudspeaker output can't be captured and echoed
        // back. The gate stays closed until turnComplete.
        final hasModelContent =
            (message.modelTurn?.parts.isNotEmpty ?? false) ||
                (outT != null && outT.trim().isNotEmpty);
        if (hasModelContent && !_modelSpeaking) {
          _modelSpeaking = true;
          _thinkingCuePlayed = false; // reset for the next user turn
          _lastModelAudioAt = DateTime.now();
          unawaited(audio.pauseCapture());
        } else if (hasModelContent) {
          _lastModelAudioAt = DateTime.now();
        }
        final parts = message.modelTurn?.parts;
        if (parts != null) {
          for (final part in parts) {
            if (part is InlineDataPart &&
                part.mimeType.startsWith('audio/pcm')) {
              _modelSpeaking = true;
              _lastModelAudioAt = DateTime.now();
              await audio.playChunk(part.bytes);
            }
          }
        }
      } else if (message is LiveServerToolCall) {
        await _handleToolCalls(message.functionCalls);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('LiveConversationService: message error: $e');
    }
  }

  /// Executes each requested function via [onToolCall] and sends the results
  /// back to the model so it can continue speaking with the outcome.
  Future<void> _handleToolCalls(List<FunctionCall>? calls) async {
    final session = _session;
    if (calls == null || calls.isEmpty || session == null) return;

    for (final call in calls) {
      Map<String, Object?> result;
      try {
        result = onToolCall != null
            ? await onToolCall!(call.name, call.args)
            : {
                'status': 'error',
                'message': 'This action is not available right now.',
              };
      } catch (e) {
        result = {'status': 'error', 'message': 'Could not complete: $e'};
      }
      try {
        // Send the function result back into the session as a tool response.
        await session.send(input: Content.functionResponse(call.name, result));
      } catch (e) {
        if (kDebugMode) {
          debugPrint('LiveConversationService: tool response send failed: $e');
        }
      }
    }
  }

  /// Interrupts the model's current speech so the user can talk over it
  /// (barge-in) by flushing local playback.
  ///
  /// NOTE: As of the current Firebase AI Logic Live API (Preview), SDK-driven
  /// interruption handling and VAD configuration are listed as "coming soon".
  /// Until then, callers can invoke this manually (e.g. on a push-to-talk tap);
  /// the model may still also emit an `interrupted` server signal which we
  /// honor in [_onServerResponse].
  Future<void> interrupt() async {
    // User is taking over: stop playback and re-open the mic immediately.
    _modelSpeaking = false;
    _lastModelAudioAt = DateTime.fromMillisecondsSinceEpoch(0);
    await _audioIO?.stopPlayback();
    await _audioIO?.resumeCapture();
  }

  /// Ends the conversation and releases the session + audio resources.
  Future<void> stop() async {
    if (_state == LiveConversationState.idle) return;
    // Setting closing first makes the receive loop exit cleanly.
    _setState(LiveConversationState.closing);
    _stopMicWatchdog();
    _endFallbackTimer?.cancel();
    _endFallbackTimer = null;
    _flushTranscriptBuffers();
    try {
      await _audioIO?.stopCapture();
      await _audioIO?.stopPlayback();
      await _session?.close();
    } catch (e) {
      if (kDebugMode) debugPrint('LiveConversationService: stop error: $e');
    } finally {
      _session = null;
      _setState(LiveConversationState.idle);
    }
  }

  void _fail(String message) {
    _stopMicWatchdog();
    _lastError = message;
    _setState(LiveConversationState.error);
  }

  void _setState(LiveConversationState next) {
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _stopMicWatchdog();
    _session?.close();
    _audioIO?.dispose();
    super.dispose();
  }
}
