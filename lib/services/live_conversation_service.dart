import 'dart:async';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart';

import '../config/feature_flags.dart';

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

  /// Stops any in-progress playback (used for barge-in).
  Future<void> stopPlayback();

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
/// IMPORTANT backend note: in the installed `firebase_ai` (2.3.0),
/// `liveGenerativeModel` is only supported on the **Vertex AI** backend (it
/// throws on the Developer API backend), so this uses `FirebaseAI.vertexAI()`
/// with App Check — matching how [AIService] is wired. (Newer SDK/docs move
/// Live to the Developer API backend; revisit on upgrade.)
class LiveConversationService extends ChangeNotifier {
  LiveConversationService({
    LiveAudioIO? audioIO,
    FirebaseAI? ai,
  })  : _audioIO = audioIO,
        _ai = ai;

  /// Live-capable model id. Kept overridable because these preview models are
  /// retired/renamed frequently — do not hardcode long-term.
  ///
  /// Overridable at build time for debugging which model the Live/BidiGenerate
  /// endpoint accepts (a wrong/retired model closes the WebSocket with code
  /// 1008 — policy violation):
  ///   flutter run --dart-define=LIVE_MODEL_ID=gemini-live-2.5-flash-preview
  ///
  /// Default: `gemini-live-2.5-flash` — the Live/BidiGenerateContent model
  /// available on the `global` Vertex AI endpoint for this project. Confirmed
  /// working with firebase_ai 4.0.0 + FirebaseAI.agentPlatform() which
  /// defaults to `global` (fixing the 1008 "model not found" error that
  /// occurred with the old vertexAI() + us-central1 combination).
  static const String _defaultModelId = String.fromEnvironment(
    'LIVE_MODEL_ID',
    defaultValue: 'gemini-live-2.5-flash',
  );

  final LiveAudioIO? _audioIO;
  final FirebaseAI? _ai;

  /// Optional handler invoked when the model requests a tool/function call.
  /// Set by the owner before [start]. If null, tool calls are acknowledged
  /// with an error result so the model can recover gracefully.
  LiveToolHandler? onToolCall;

  /// The tool/function declarations exposed to the model. Set by the owner
  /// before [start] to match [onToolCall].
  List<Tool> tools = const [];

  LiveConversationState _state = LiveConversationState.idle;
  LiveConversationState get state => _state;

  // Half-duplex echo control: while the model is speaking we pause the mic (so
  // the loudspeaker output isn't re-captured and echoed back), resuming on the
  // model's turnComplete. Two separate audio engines (record + flutter_pcm_sound)
  // mean iOS hardware AEC can't cancel the echo, so we gate instead.
  bool _modelSpeaking = false;
  // Timestamp of the model's most recent audio, used to add a short tail before
  // the mic resumes so the speaker's trailing audio doesn't leak in.
  DateTime _lastModelAudioAt = DateTime.fromMillisecondsSinceEpoch(0);

  String _lastTranscript = '';

  /// The latest transcription of the model's spoken reply (from the server's
  /// output audio transcription). Useful for showing live captions in the UI.
  String get lastTranscript => _lastTranscript;

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
    _modelSpeaking = false;
    _lastModelAudioAt = DateTime.fromMillisecondsSinceEpoch(0);
    _lastTranscript = '';

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
          // Ask the server for a text transcription of the model's spoken
          // reply. Exposed via `lastTranscript` so the UI can show captions of
          // what the model said.
          outputAudioTranscription: AudioTranscriptionConfig(),
        ),
        tools: tools.isEmpty ? null : tools,
        systemInstruction:
            systemInstruction != null ? Content.system(systemInstruction) : null,
      );

      _session = await liveModel.connect();
      _setState(LiveConversationState.active);

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
        // (plus a short tail after its last audio chunk) so the loudspeaker
        // output isn't captured and echoed back. `_modelSpeaking` is cleared on
        // the server's turnComplete signal (see _onServerResponse), which is
        // what keeps the conversation flowing turn-to-turn.
        final sinceAudio =
            DateTime.now().difference(_lastModelAudioAt).inMilliseconds;
        if (_modelSpeaking || sinceAudio < 600) {
          continue;
        }
        await session
            .sendAudioRealtime(InlineDataPart('audio/pcm;rate=16000', data));
      }
    } catch (e) {
      if (kDebugMode) debugPrint('LiveConversationService: mic pump error: $e');
    }
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
          final resumeAudio = audio;
          Future.delayed(const Duration(milliseconds: 500), () {
            if (_state == LiveConversationState.active && !_modelSpeaking) {
              unawaited(resumeAudio.resumeCapture());
            }
          });
        }
        // Capture the model's output transcription for optional UI captions.
        final outT = message.outputTranscription?.text;
        if (outT != null && outT.trim().isNotEmpty) {
          _lastTranscript = outT.trim();
          notifyListeners();
        }
        // As soon as the model produces ANY turn content it has taken the floor:
        // pause the mic so its loudspeaker output can't be captured and echoed
        // back. The gate stays closed until turnComplete.
        final hasModelContent =
            (message.modelTurn?.parts.isNotEmpty ?? false) ||
                (outT != null && outT.trim().isNotEmpty);
        if (hasModelContent && !_modelSpeaking) {
          _modelSpeaking = true;
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
    _lastError = message;
    _setState(LiveConversationState.error);
  }

  void _setState(LiveConversationState next) {
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _session?.close();
    _audioIO?.dispose();
    super.dispose();
  }
}
