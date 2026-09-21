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
    // Start the native engine, then surface the mic event stream. The engine
    // emits 16 kHz mono PCM16 chunks (echo-cancelled).
    _micController?.close();
    final controller = StreamController<Uint8List>();
    _micController = controller;

    // Kick off native start (fire-and-forget; errors surface via the stream).
    _method.invokeMethod<bool>('start').catchError((e) {
      debugPrint('NativeAecAudioIO: start failed: $e');
      return false;
    });

    _micSub?.cancel();
    _micSub = _micEvents.receiveBroadcastStream().listen(
      (data) {
        if (data is Uint8List) controller.add(data);
      },
      onError: (e) => debugPrint('NativeAecAudioIO: mic stream error: $e'),
    );

    return controller.stream;
  }

  @override
  Future<void> stopCapture() async {
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
    // Opportunistically refresh from native (async, non-blocking).
    _refreshPlaybackRemaining();
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
