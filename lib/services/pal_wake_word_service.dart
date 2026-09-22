import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'pal_feedback_sounds.dart';

/// A lightweight, foreground-only wake-word listener that opens the Live pal
/// when the user says "Hey Pal" or "Pal".
///
/// Design notes:
///  - iOS does not allow arbitrary third-party apps to run a wake-word
///    listener while backgrounded, so this service is deliberately foreground
///    only. Callers coordinate app-lifecycle start/stop.
///  - It uses its own `SpeechToText` instance so it never fights the
///    tap-to-speak `VoiceCommandService` recognizer or the Live audio pipeline
///    for mic ownership. Callers MUST stop it before either of those engages
///    the microphone, and restart it after they release.
///  - On-device `speech_to_text` sessions have a ~1 minute ceiling, so the
///    listener auto-restarts a fresh session every time one ends without a
///    match. That keeps it running indefinitely without leaking sessions.
class PalWakeWordService extends ChangeNotifier {
  PalWakeWordService();

  /// Regex matching the wake phrases. Word boundaries around "pal" so words
  /// like "palm", "palace" or "pale" do NOT trigger. Prefixes like "hey",
  /// "ok", or "hi" are accepted variants.
  static final RegExp _wakePattern = RegExp(
    r'\b(?:hey\s+pal|ok(?:ay)?\s+pal|hi\s+pal|pal)\b',
    caseSensitive: false,
  );

  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _initializing = false;
  bool _initialized = false;
  bool _running = false;
  bool _restartScheduled = false;
  Timer? _restartTimer;
  // Health-check tick verifying the recognizer is still listening. iOS SFSpeech
  // sessions occasionally drop without a status callback, and a missed callback
  // meant the wake service was silently dead — that was the "had to say Hey Pal
  // 2-3 times" symptom. The watchdog recovers it within a second.
  Timer? _healthTimer;
  VoidCallback? _onWake;
  DateTime _lastWakeAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// True while the recognizer is actively listening for the wake phrase.
  bool get isListening => _running;

  /// Fires the given [onWake] callback once when a wake phrase is heard. The
  /// service pauses itself immediately after firing so the caller can hand the
  /// microphone to the Live pipeline without contention.
  Future<void> start({required VoidCallback onWake}) async {
    _onWake = onWake;
    if (_running) return;
    if (!await _ensureInitialized()) return;

    _running = true;
    notifyListeners();
    await _beginSession();
    _startHealthWatchdog();
  }

  /// Immediately stops the recognizer and cancels any pending restart. Safe to
  /// call repeatedly.
  Future<void> stop() async {
    _restartTimer?.cancel();
    _restartTimer = null;
    _restartScheduled = false;
    _healthTimer?.cancel();
    _healthTimer = null;
    if (!_running) return;
    _running = false;
    try {
      await _speech.stop();
    } catch (e) {
      debugPrint('PalWakeWordService: stop() failed: $e');
    }
    notifyListeners();
  }

  void _startHealthWatchdog() {
    _healthTimer?.cancel();
    _healthTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_running) return;
      // If the recognizer went idle without a status callback and no restart
      // is queued, kick off a fresh session so the wake window never sits idle.
      if (!_speech.isListening && !_restartScheduled) {
        _scheduleRestart();
      }
    });
  }

  Future<bool> _ensureInitialized() async {
    if (_initialized) return true;
    if (_initializing) return false;
    _initializing = true;
    try {
      _initialized = await _speech.initialize(
        onStatus: _onStatus,
        onError: (error) {
          if (kDebugMode) {
            debugPrint('PalWakeWordService: STT error — $error');
          }
          _scheduleRestart();
        },
        debugLogging: false,
      );
    } catch (e) {
      debugPrint('PalWakeWordService: initialize failed: $e');
      _initialized = false;
    } finally {
      _initializing = false;
    }
    return _initialized;
  }

  void _onStatus(String status) {
    if (!_running) return;
    // Auto-restart when the session naturally ends (iOS caps a single session
    // at ~1 minute). No wake phrase matched, so open a fresh window.
    if (status == 'notListening' || status == 'done') {
      _scheduleRestart();
    }
  }

  Future<void> _beginSession() async {
    if (!_running || !_initialized) return;
    try {
      await _speech.listen(
        onResult: _onResult,
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.dictation,
          partialResults: true,
          cancelOnError: false,
          listenFor: const Duration(seconds: 55),
          // Keep the session alive through natural silences. If pauseFor is
          // shorter than listenFor, iOS ends the session on the first quiet
          // stretch — that's the "wake word had to be said twice" bug.
          pauseFor: const Duration(seconds: 55),
        ),
      );
    } catch (e) {
      debugPrint('PalWakeWordService: listen() failed: $e');
      _scheduleRestart();
    }
  }

  void _scheduleRestart() {
    if (!_running || _restartScheduled) return;
    _restartScheduled = true;
    _restartTimer?.cancel();
    // Restart as fast as consecutive status callbacks allow — 50ms both keeps
    // the mic effectively continuous and still collapses status bursts.
    _restartTimer = Timer(const Duration(milliseconds: 50), () async {
      _restartScheduled = false;
      if (!_running) return;
      await _beginSession();
    });
  }

  void _onResult(SpeechRecognitionResult result) {
    if (!_running) return;
    final text = result.recognizedWords.trim();
    if (text.isEmpty) return;
    if (!_wakePattern.hasMatch(text)) return;

    // Debounce so a lingering partial ("hey pal, hey pal") only fires once.
    final now = DateTime.now();
    if (now.difference(_lastWakeAt) < const Duration(seconds: 3)) return;
    _lastWakeAt = now;

    if (kDebugMode) {
      debugPrint('PalWakeWordService: wake phrase detected in "$text"');
    }

    // Pause self before invoking the callback — the caller will start the Live
    // pipeline which needs exclusive mic access.
    final callback = _onWake;
    unawaited(stop());
    // Immediate feedback while the sheet is spinning up so the user knows the
    // phrase was heard, even during the handoff latency.
    unawaited(PalFeedbackSounds.wakeAcknowledged());
    callback?.call();
  }

  @override
  void dispose() {
    _restartTimer?.cancel();
    _restartTimer = null;
    _healthTimer?.cancel();
    _healthTimer = null;
    _speech.cancel();
    super.dispose();
  }
}
