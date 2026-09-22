import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'pal_feedback_sounds.dart';

/// A lightweight, foreground-only wake-word listener that opens the Live pal
/// when the user says "Hey Pal" or "Pal".
///
/// Audio-ownership safety (this is critical):
///  - iOS gives ONE app audio-input node. The tap-to-speak `VoiceCommandService`
///    recognizer, this wake listener, and the native Live `LiveAudioEngine` all
///    want it. If two touch it at once, `speech_to_text`'s native
///    `AVAudioNode inputFormatForBus:` dereferences a torn-down audio unit and
///    the app SEGFAULTs (observed crash: `AVAudioIONodeImpl::AUI()`).
///  - Therefore this service must be the ONLY audio consumer while it runs, and
///    it must FULLY release the input node (via `cancel()`, not just `stop()`)
///    before anything else — especially the Live pipeline — claims the session.
///  - It is foreground only (iOS forbids background wake-word listening).
class PalWakeWordService extends ChangeNotifier {
  PalWakeWordService();

  /// Regex matching the wake phrases. Word boundaries around the "pal" family
  /// so words like "palm"/"palace"/"pale" do NOT trigger, but common STT
  /// mishears of "pal" (pals, pao, pow…) still do when preceded by a wake word.
  static final RegExp _wakePattern = RegExp(
    r'\b(?:hey|ok(?:ay)?|hi|hello|a)\s+(?:pal|pals|pao|pow|pah|paul|powl)\b'
    r'|\bpal\b|\bpals\b',
    caseSensitive: false,
  );

  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _initialized = false;
  bool _running = false;
  bool _starting = false;
  bool _tearingDown = false;
  bool _restartScheduled = false;
  Timer? _restartTimer;
  Timer? _healthTimer;
  VoidCallback? _onWake;
  bool _wakeFired = false;
  DateTime _lastWakeAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// True while the recognizer is actively listening for the wake phrase.
  bool get isListening => _running;

  /// Fires [onWake] once when a wake phrase is heard, then fully tears the
  /// recognizer down so the caller can safely claim the microphone.
  Future<void> start({required VoidCallback onWake}) async {
    _onWake = onWake;
    // Never begin a start while a teardown is in flight or one is already up.
    if (_running || _starting || _tearingDown) return;
    _starting = true;
    _wakeFired = false;
    try {
      if (!await _ensureInitialized()) return;
      if (_tearingDown) return; // a stop() raced in during init
      _running = true;
      notifyListeners();
      await _beginSession();
      _startHealthWatchdog();
    } catch (e) {
      debugPrint('PalWakeWordService: start() failed: $e');
      _running = false;
    } finally {
      _starting = false;
    }
  }

  /// Warms up the recognizer (init only, no listening) so the first real start
  /// is instant. Safe to call repeatedly; no-ops once initialized.
  Future<void> warmUp() async {
    if (_initialized || _tearingDown) return;
    await _ensureInitialized();
  }

  /// Fully stops and RELEASES the recognizer's audio unit. Uses `cancel()`
  /// rather than `stop()` so the native input node is torn down completely —
  /// leaving it half-open is what let a later `listen()` crash on a dangling
  /// audio unit. Safe to call repeatedly.
  Future<void> stop() async {
    _tearingDown = true;
    _restartTimer?.cancel();
    _restartTimer = null;
    _restartScheduled = false;
    _healthTimer?.cancel();
    _healthTimer = null;

    final wasRunning = _running;
    _running = false;
    try {
      // cancel() releases the recognizer AND its audio session/input node.
      await _speech.cancel();
    } catch (e) {
      debugPrint('PalWakeWordService: cancel() failed: $e');
    } finally {
      _tearingDown = false;
    }
    if (wasRunning) notifyListeners();
  }

  void _startHealthWatchdog() {
    _healthTimer?.cancel();
    _healthTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      // Only act on a clean, running, non-teardown state; otherwise we could
      // race a listen() into a half-released audio unit (the crash path).
      if (!_running || _tearingDown || _starting) return;
      if (!_speech.isListening && !_restartScheduled) {
        _scheduleRestart();
      }
    });
  }

  // Held so concurrent callers (warmUp + start) await the SAME initialize().
  Future<bool>? _initFuture;

  Future<bool> _ensureInitialized() {
    if (_initialized) return Future.value(true);
    return _initFuture ??= _doInitialize();
  }

  Future<bool> _doInitialize() async {
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
      if (!_initialized) _initFuture = null;
    }
    return _initialized;
  }

  void _onStatus(String status) {
    if (!_running || _tearingDown) return;
    if (status == 'notListening' || status == 'done') {
      _scheduleRestart();
    }
  }

  Future<void> _beginSession() async {
    // Hard gate: only ever call listen() when cleanly running.
    if (!_running || !_initialized || _tearingDown) return;
    if (_speech.isListening) return;
    try {
      await _speech.listen(
        onResult: _onResult,
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.dictation,
          partialResults: true,
          cancelOnError: false,
          listenFor: const Duration(seconds: 55),
          // pauseFor == listenFor so a natural silence doesn't end the session.
          pauseFor: const Duration(seconds: 55),
        ),
      );
    } catch (e) {
      debugPrint('PalWakeWordService: listen() failed: $e');
      _scheduleRestart();
    }
  }

  void _scheduleRestart() {
    if (!_running || _tearingDown || _restartScheduled) return;
    _restartScheduled = true;
    _restartTimer?.cancel();
    // A slightly longer gap than before: it gives iOS time to release the
    // previous session's audio unit before the next listen(), avoiding a
    // reclaim-during-teardown race.
    _restartTimer = Timer(const Duration(milliseconds: 300), () async {
      _restartScheduled = false;
      if (!_running || _tearingDown) return;
      await _beginSession();
    });
  }

  void _onResult(SpeechRecognitionResult result) {
    if (!_running || _tearingDown || _wakeFired) return;
    final text = result.recognizedWords.trim();
    if (text.isEmpty) return;
    if (!_wakePattern.hasMatch(text)) return;

    final now = DateTime.now();
    if (now.difference(_lastWakeAt) < const Duration(milliseconds: 1200)) {
      return;
    }
    _lastWakeAt = now;
    _wakeFired = true;

    if (kDebugMode) {
      debugPrint('PalWakeWordService: wake phrase detected in "$text"');
    }
    // Immediate confirmation, then fully release audio BEFORE handing off.
    unawaited(PalFeedbackSounds.wakeAcknowledged());
    _fireWakeAfterRelease();
  }

  /// Fully releases the recognizer, waits for iOS to drop the input node, then
  /// invokes the wake callback. The delay is what prevents the Live engine from
  /// claiming the audio session while the recognizer's audio unit is still
  /// being torn down (the segfault window).
  Future<void> _fireWakeAfterRelease() async {
    final callback = _onWake;
    await stop();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    callback?.call();
  }

  @override
  void dispose() {
    _tearingDown = true;
    _restartTimer?.cancel();
    _restartTimer = null;
    _healthTimer?.cancel();
    _healthTimer = null;
    _running = false;
    try {
      _speech.cancel();
    } catch (_) {}
    super.dispose();
  }
}
