import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
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
  /// mishears of "pal" (pals, pao, pow, paul…) still do — either on their own
  /// or preceded by a wake word. iOS dictation mis-hears "Hey Pal" in many
  /// ways ("hey pao", "hi pal", "a pal", "hey paul", "hey pow"…), so the
  /// leading-word set is generous and the standalone "pal/pals/paul" family is
  /// also accepted. Matching runs on a normalised (lowercased, punctuation-
  /// stripped, whitespace-collapsed) copy of the transcript — see [_normalize].
  ///
  /// After a real greeting ("hey", "hi", "ok"…) Android in particular spells
  /// "pal" many ways — "pall", "pail", "bail", "paul", "bal", "pool" — so any
  /// short p/b word ending in "l" is accepted there. Vowel "i" is left out so
  /// "hey Bill" / "hi Phil" don't trigger. "a"/"the" only pair with the narrow
  /// set, otherwise everyday phrases like "the pool" or "a ball" would fire.
  /// "paypal"/"heypal" are how the recognizer writes "hey pal" run together.
  static final RegExp _wakePattern = RegExp(
    r'\b(?:hey|hay|heya|hei|ok(?:ay)?|hi|hello|yo)\s+'
    r'(?:[pb](?:a|aa|ai|au|aw|e|ee|o|oo|ou|ow|u)ll?'
    r'|pals|palo|pao|pow|pah|paw|val|bao)\b'
    r'|\b(?:a|the)\s+(?:pal|pals|pao|paul)\b'
    r'|\b(?:pal|pals|pall|paul|powl|paypal|heypal|haypal)\b',
    caseSensitive: false,
  );

  /// Lowercases, strips punctuation, and collapses whitespace so the matcher
  /// sees clean tokens (STT partials often carry commas/odd spacing).
  static String _normalize(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r"[^a-z0-9\s]"), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

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
  // Last time the recognizer showed ANY sign of life (a result callback or a
  // fresh listen() beginning). Used to detect a session that reports
  // isListening==true but has silently wedged (iOS STT can get stuck holding
  // the mic without delivering results), so the watchdog can force-recycle it.
  DateTime _lastActivityAt = DateTime.fromMillisecondsSinceEpoch(0);
  // How long a "listening" session may go with no result activity before we
  // assume it wedged and force a fresh session. Must be comfortably LONGER than
  // a normal quiet stretch (the session is kept alive through silence), so a
  // simply-quiet room is never mistaken for a wedged session and needlessly
  // recycled (recycling introduces a warm-up gap where a "Hey Pal" is missed).
  static const Duration _stallTimeout = Duration(seconds: 30);

  // Android's SpeechRecognizer service needs a beat to free itself after a
  // session ends or errors. Re-calling listen() too soon gets error_busy, and
  // retrying every 120ms on that error loops forever. These track a backoff
  // that both the error handler and the watchdog respect.
  static bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;
  int _consecutiveErrors = 0;
  DateTime _retryNotBefore = DateTime.fromMillisecondsSinceEpoch(0);

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
    // Check often so a session that quietly ended is revived before the user
    // gets a chance to speak into a dead mic. 400ms keeps the listen loop
    // effectively continuous without busy-spinning.
    _healthTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      // Only act on a clean, running, non-teardown state; otherwise we could
      // race a listen() into a half-released audio unit (the crash path).
      if (!_running || _tearingDown || _starting) return;
      if (!_speech.isListening) {
        // Session ended → restart quickly.
        if (!_restartScheduled) _scheduleRestart();
        return;
      }
      // Session CLAIMS to be listening but has been silent too long → it has
      // likely wedged (holding the mic without delivering results, so no
      // "Hey Pal" is ever heard). Force a full recycle: cancel releases the
      // stuck audio unit, then a fresh listen() re-arms it.
      if (!_restartScheduled &&
          DateTime.now().difference(_lastActivityAt) > _stallTimeout) {
        if (kDebugMode) {
          debugPrint('PalWakeWordService: session stalled — recycling.');
        }
        _forceRecycle();
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
        onError: _onError,
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

  void _onError(SpeechRecognitionError error) {
    final msg = error.errorMsg;
    // A quiet room ends Android sessions with no_match / speech_timeout every
    // few seconds. That's normal: restart promptly, but not so fast that the
    // next listen() lands while the service is still releasing (error_busy).
    final benign = msg == 'error_no_match' || msg == 'error_speech_timeout';
    final Duration backoff;
    if (benign) {
      backoff = Duration(milliseconds: _isAndroid ? 400 : 120);
    } else {
      // Real errors (busy, client, network…): exponential backoff, 0.5s → 8s.
      _consecutiveErrors++;
      final ms = 500 * (1 << (_consecutiveErrors - 1).clamp(0, 4));
      backoff = Duration(milliseconds: ms);
    }
    _retryNotBefore = DateTime.now().add(backoff);
    if (kDebugMode &&
        (!benign &&
            (_consecutiveErrors <= 3 || _consecutiveErrors % 10 == 0))) {
      debugPrint('PalWakeWordService: STT error — $msg '
          '(#$_consecutiveErrors, retrying in ${backoff.inMilliseconds}ms)');
    }
    // A restart may already be queued by the status callback or watchdog with
    // the short delay; replace it so the backoff actually applies.
    if (_restartScheduled) {
      _restartTimer?.cancel();
      _restartScheduled = false;
    }
    _scheduleRestart();
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
    // A fresh session counts as activity so the stall watchdog gives it time.
    _lastActivityAt = DateTime.now();
    try {
      await _speech.listen(
        onResult: _onResult,
        listenOptions: stt.SpeechListenOptions(
          // dictation mode does NOT auto-stop on the first recognised phrase
          // (search/confirmation modes end the session as soon as they think
          // the user finished — which, for wake-spotting, means the recognizer
          // keeps ending and needing a warm-up restart, and any "Hey Pal"
          // spoken during that warm-up gap is missed). dictation keeps the
          // session open so the mic stays continuously hot.
          listenMode: stt.ListenMode.dictation,
          partialResults: true,
          cancelOnError: false,
          // Prefer on-device recognition when available: lower latency, no
          // network dependency, and it doesn't get throttled/ended by the
          // server the way cloud dictation can.
          // Not on Android: there it selects the on-device recognizer or
          // EXTRA_PREFER_OFFLINE, which errors on every session when the
          // phone lacks the offline language pack, so the wake word never
          // fires. Android's default recognizer is the reliable path.
          onDevice: defaultTargetPlatform != TargetPlatform.android,
          autoPunctuation: false,
          // Keep ONE session alive as long as iOS allows and DON'T end it on
          // silence: pauseFor == listenFor so a quiet room never ends the
          // session. Fewer restarts = far fewer dead windows where a spoken
          // "Hey Pal" would be missed. The health watchdog re-arms the next
          // session the instant this one ends.
          listenFor: const Duration(seconds: 60),
          pauseFor: const Duration(seconds: 60),
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
    // Restart the SAME recognizer's listen() quickly. This gap is between two
    // consecutive wake sessions on one recognizer (it reuses its own input
    // node), NOT the wake→Live handoff, so it can be short. A long gap here is
    // exactly what made users repeat "Hey Pal": a spoken phrase landing in the
    // dead window between sessions was never heard. Keep it minimal — except
    // that Android needs a little longer, and any error backoff wins.
    var delay = Duration(milliseconds: _isAndroid ? 300 : 120);
    final untilAllowed = _retryNotBefore.difference(DateTime.now());
    if (untilAllowed > delay) delay = untilAllowed;
    _restartTimer = Timer(delay, () async {
      _restartScheduled = false;
      if (!_running || _tearingDown) return;
      await _beginSession();
    });
  }

  /// Force-recycles a wedged session: fully releases the stuck audio unit with
  /// cancel() (NOT stop-the-feature), then re-arms listen() after a short beat.
  /// Guarded by [_restartScheduled] so only one recycle is in flight.
  Future<void> _forceRecycle() async {
    if (!_running || _tearingDown || _restartScheduled) return;
    _restartScheduled = true;
    try {
      await _speech.cancel();
    } catch (e) {
      debugPrint('PalWakeWordService: recycle cancel() failed: $e');
    }
    // Reset the activity clock so the fresh session isn't immediately judged
    // stalled again.
    _lastActivityAt = DateTime.now();
    _restartTimer?.cancel();
    _restartTimer = Timer(const Duration(milliseconds: 150), () async {
      _restartScheduled = false;
      if (!_running || _tearingDown) return;
      await _beginSession();
    });
  }

  void _onResult(SpeechRecognitionResult result) {
    if (!_running || _tearingDown || _wakeFired) return;
    // Any result (even a non-matching partial) proves the session is alive.
    _lastActivityAt = DateTime.now();
    _consecutiveErrors = 0;
    // Check every alternate transcript, not just the top guess: Android returns
    // up to 10, and "hey pal" is often the 2nd or 3rd when the 1st is "paypal"
    // or "hey bail".
    final top = _normalize(result.recognizedWords);
    final candidates = <String>[
      top,
      for (final alt in result.alternates) _normalize(alt.recognizedWords),
    ].where((t) => t.isNotEmpty);
    if (candidates.isEmpty) return;
    final text = candidates.firstWhere(_wakePattern.hasMatch, orElse: () => '');
    if (text.isEmpty) {
      // Debug builds only: shows what the recognizer actually heard, so a
      // missed "Hey Pal" can be traced to a mishearing the pattern lacks.
      if (kDebugMode) {
        final alts =
            candidates.where((t) => t != top).toSet().take(3).join('" / "');
        debugPrint('PalWakeWordService: heard "$top" (no wake match)'
            '${alts.isEmpty ? '' : ' — alternates: "$alts"'}');
      }
      return;
    }

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
