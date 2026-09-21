import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'live_conversation_service.dart';

/// [LiveAudioIO] backed by the native iOS [LiveAudioEngine] (AVAudioEngine with
/// Voice-Processing I/O), giving hardware acoustic echo cancellation.
///
/// Unlike [RecordPcmAudioIO] (two separate engines: `record` + `flutter_pcm_
/// sound`), this uses ONE native engine for both mic capture and pal playback,
/// so the system AEC has the playback as its reference signal and cancels the
/// pal's voice out of the mic BEFORE it's upstreamed. That eliminates the
/// "pal hears himself" echo — the model's audio never reaches the mic channel,
/// so it can't be transcribed as user speech.
///
/// Bridges to native via:
///   - MethodChannel  `aiwellnesspal/live_audio`       (control + playback)
///   - EventChannel   `aiwellnesspal/live_audio/mic`    (mic PCM16 upstream)
class NativeAecAudioIO implements LiveAudioIO {
  static const MethodChannel _method =
      MethodChannel('aiwellnesspal/live_audio');
  static const EventChannel _micEvents =
      EventChannel('aiwellnesspal/live_audio/mic');

  StreamController<Uint8List>? _micController;
  StreamSubscription<dynamic>? _micSub;

  // Local mirror of native playback-remaining so the sync getter (which the
  // service polls) stays cheap; refreshed opportunistically on playback ops.
  int _playbackRemainingMs = 0;
  DateTime _remainingSampledAt = DateTime.fromMillisecondsSinceEpoch(0);

  // Full-duplex is safe only when native Voice-Processing I/O has successfully
  // enabled AEC on BOTH sides. Start pessimistically; otherwise a failed iOS
  // audio-session reconfiguration lets speaker audio reach the mic and the
  // server falsely interrupts the pal mid-sentence.
  bool _hasVerifiedAec = false;
  DateTime _aecSampledAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  Future<bool> requestPermission() async {
    try {
      final granted = await _method.invokeMethod<bool>('requestPermission');
      return granted ?? false;
    } catch (e) {
      debugPrint('NativeAecAudioIO: requestPermission failed: $e');
      return false;
    }
  }

  @override
  Stream<Uint8List> startCapture() {
    // Surface the mic event stream FIRST, then start the native engine. The
    // engine emits 16 kHz mono PCM16 chunks (echo-cancelled).
    //
    // Order matters: the native side drops tap buffers while its event sink is
    // unregistered, so subscribing before `start` guarantees the very first
    // audio (the user's opening words) isn't thrown away.
    _micController?.close();
    final controller = StreamController<Uint8List>();
    _micController = controller;

    var eventsSeen = 0;
    _micSub?.cancel();
    _micSub = _micEvents.receiveBroadcastStream().listen(
      (data) {
        if (data is Uint8List) {
          eventsSeen++;
          if (eventsSeen == 1) {
            debugPrint('NativeAecAudioIO: FIRST mic chunk received from native '
                '(${data.length} bytes) — capture is live.');
          }
          controller.add(data);
        }
      },
      onError: (e) => debugPrint('NativeAecAudioIO: mic stream error: $e'),
    );

    // Kick off native start and log the returned native audio diagnostics
    // (NSLog does not reach `flutter run`, so this is how we see them).
    _method.invokeMethod<dynamic>('start').then((diag) {
      _updateAecStatus(diag);
      debugPrint('NativeAecAudioIO: native start OK — $diag');
      // Re-check shortly after: if something else grabs the audio session
      // (e.g. audio_service finishing its init and forcing .playback), the
      // category/converter state here will show it.
      Future.delayed(const Duration(seconds: 2), _refreshAecStatus);
    }).catchError((e) {
      _hasVerifiedAec = false;
      debugPrint('NativeAecAudioIO: native start FAILED: $e');
      return null;
    });

    return controller.stream;
  }

  @override
  Future<void> stopCapture() async {
    _hasVerifiedAec = false;
    await _invoke('stop');
    await _micSub?.cancel();
    _micSub = null;
    await _micController?.close();
    _micController = null;
  }

  @override
  Future<void> pauseCapture() => _invoke('pauseMic');

  @override
  Future<void> resumeCapture() => _invoke('resumeMic');

  @override
  Future<void> playChunk(Uint8List pcm) async {
    if (pcm.isEmpty) return;
    try {
      await _method.invokeMethod<void>('playChunk', pcm);
    } catch (e) {
      debugPrint('NativeAecAudioIO: playChunk failed: $e');
    }
  }

  /// Full duplex (and therefore barge-in) is enabled only after native iOS
  /// diagnostics confirm both Voice-Processing I/O directions are active.
  @override
  bool get hasHardwareAec => _hasVerifiedAec;

  void _updateAecStatus(dynamic diagnostics) {
    final map = diagnostics is Map ? diagnostics : null;
    final enabled = map?['aecInput'] == true && map?['aecOutput'] == true;
    if (_hasVerifiedAec != enabled) {
      _hasVerifiedAec = enabled;
      debugPrint('NativeAecAudioIO: verified hardware AEC=$enabled');
    }
  }

  void _refreshAecStatus() {
    if (DateTime.now().difference(_aecSampledAt) <
        const Duration(seconds: 2)) {
      return;
    }
    _aecSampledAt = DateTime.now();
    _method.invokeMethod<dynamic>('diagnostics').then((diagnostics) {
      _updateAecStatus(diagnostics);
      debugPrint('NativeAecAudioIO: native audio state — $diagnostics');
    }).catchError((_) {
      _hasVerifiedAec = false;
    });
  }

  @override
  Future<void> playThinkingCue() async {
    // The native engine plays the pal's real audio; a synthetic cue isn't
    // essential and would need its own tone generator native-side. Kept as a
    // no-op so the pipeline stays simple and echo-free. (The service treats
    // this as best-effort/optional.)
  }

  @override
  Future<void> stopPlayback() async {
    await _invoke('stopPlayback');
    _playbackRemainingMs = 0;
    _remainingSampledAt = DateTime.now();
  }

  @override
  Duration get playbackRemaining {
    // Decay the last sampled value by elapsed time so the getter stays fresh
    // between the periodic async refreshes below.
    final elapsed = DateTime.now().difference(_remainingSampledAt).inMilliseconds;
    final remaining = _playbackRemainingMs - elapsed;
    // Opportunistically refresh native state (async, non-blocking).
    _refreshPlaybackRemaining();
    _refreshAecStatus();
    return remaining > 0 ? Duration(milliseconds: remaining) : Duration.zero;
  }

  void _refreshPlaybackRemaining() {
    // Throttle native round-trips to ~every 100ms.
    if (DateTime.now().difference(_remainingSampledAt).inMilliseconds < 100) {
      return;
    }
    _remainingSampledAt = DateTime.now();
    _method.invokeMethod<int>('playbackRemainingMs').then((ms) {
      if (ms != null) {
        _playbackRemainingMs = ms;
        _remainingSampledAt = DateTime.now();
      }
    }).catchError((_) {});
  }

  @override
  Future<void> dispose() async {
    await _micSub?.cancel();
    _micSub = null;
    await _micController?.close();
    _micController = null;
    await _invoke('stop');
  }

  Future<void> _invoke(String method) async {
    try {
      await _method.invokeMethod<void>(method);
    } catch (e) {
      debugPrint('NativeAecAudioIO: $method failed: $e');
    }
  }
}
