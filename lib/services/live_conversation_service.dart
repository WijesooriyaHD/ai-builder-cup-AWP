import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../config/feature_flags.dart';
import 'remote_config_service.dart';

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
  static const String _defaultModelId =
      'gemini-2.5-flash-native-audio-preview-12-2025';

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

    try {
      final granted = await audio.requestPermission();
      if (!granted) {
        _fail('Microphone permission is needed for Conversation Mode.');
        return;
      }

      // In firebase_ai 2.3.0 the Live model requires the Vertex AI backend.
      final ai = _ai ??
          FirebaseAI.vertexAI(
            appCheck: FirebaseAppCheck.instance,
            auth: FirebaseAuth.instance,
          );
      // Resolve the model id: explicit override > Remote Config > constant.
      final resolvedModel = modelId ??
          RemoteConfigService.instance.liveModelId(fallback: _defaultModelId);
      final liveModel = ai.liveGenerativeModel(
        model: resolvedModel,
        liveGenerationConfig: LiveGenerationConfig(
          responseModalities: [ResponseModalities.audio],
        ),
        tools: tools.isEmpty ? null : tools,
        systemInstruction:
            systemInstruction != null ? Content.system(systemInstruction) : null,
      );

      _session = await liveModel.connect();
      _setState(LiveConversationState.active);

      // Stream mic audio up as PCM inline-data parts. The Live API requires the
      // input sample rate in the MIME type (raw 16-bit PCM, 16 kHz, LE).
      final micStream = audio.startCapture();
      final mediaChunks = micStream
          .map((data) => InlineDataPart('audio/pcm;rate=16000', data));
      // Fire-and-forget; the session consumes the stream until closed.
      unawaited(_session!.sendMediaStream(mediaChunks));

      // Continuously receive turns. receive() ends its stream when a turn
      // completes, so we re-subscribe for the next turn until the session is
      // closed — that's what makes it a back-and-forth conversation.
      unawaited(_receiveLoop());
    } catch (e) {
      _fail('Could not start Conversation Mode: $e');
    }
  }

  /// Drives the receive stream turn-by-turn until the session ends.
  Future<void> _receiveLoop() async {
    final session = _session;
    if (session == null) return;
    try {
      while (_state == LiveConversationState.active && _session != null) {
        await for (final response in session.receive()) {
          await _onServerResponse(response);
        }
        // Turn complete — loop to receive the next one (unless we're closing).
      }
    } catch (e) {
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
          await audio.stopPlayback();
          return;
        }
        final parts = message.modelTurn?.parts;
        if (parts != null) {
          for (final part in parts) {
            if (part is InlineDataPart &&
                part.mimeType.startsWith('audio/pcm')) {
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
    await _audioIO?.stopPlayback();
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
