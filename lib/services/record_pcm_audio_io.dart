import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart' as pcm;
import 'package:record/record.dart';

import 'live_conversation_service.dart';

/// Concrete [LiveAudioIO] for the Gemini Live pipeline.
///
/// - Capture: `record` streams mono 16-bit PCM at 16 kHz (the Live API's
///   required input format), delivered as `Uint8List` chunks.
/// - Playback: `flutter_pcm_sound` plays the model's mono 16-bit PCM at 24 kHz
///   (the Live API's output format) in real time.
///
/// Sample rates are fixed to match the Live API spec exactly:
/// input 16 kHz LE PCM16, output 24 kHz LE PCM16.
class RecordPcmAudioIO implements LiveAudioIO {
  static const int _inputSampleRate = 16000; // Live API input requirement
  static const int _outputSampleRate = 24000; // Live API output format

  final AudioRecorder _recorder = AudioRecorder();
  static const MethodChannel _audioChannel =
      MethodChannel('aiwellnesspal/audio');
  bool _playbackReady = false;

  // Playback-progress tracking so the service can tell when audio is still
  // audibly playing even if no new chunk has arrived recently (playback lags
  // receive). We accumulate the total audio *duration* fed to the player and
  // mark when playback started; `playbackRemaining` = fed - elapsed.
  Duration _fedAudio = Duration.zero;
  DateTime? _playbackStartedAt;

  @override
  Future<bool> requestPermission() async {
    try {
      return await _recorder.hasPermission();
    } catch (e) {
      debugPrint('RecordPcmAudioIO: permission check failed: $e');
      return false;
    }
  }

  @override
  Stream<Uint8List> startCapture() async* {
    // 16 kHz mono PCM16, matching the Live API input spec.
    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _inputSampleRate,
        numChannels: 1,
        // Light front-end cleanup helps recognition without altering the format.
        echoCancel: true,
        noiseSuppress: true,
        // Route the shared play-and-record session to the loudspeaker so the
        // model's playback is audible while the mic captures. NOTE: no
        // `mixWithOthers` — it disables iOS voice-processing/AEC and causes the
        // speaker output to echo back through the mic. `echoCancel` +
        // `.voiceChat` mode (set natively in routeToSpeaker) handle the echo.
        iosConfig: IosRecordConfig(
          categoryOptions: [
            IosAudioCategoryOption.defaultToSpeaker,
            IosAudioCategoryOption.allowBluetooth,
            IosAudioCategoryOption.allowBluetoothA2DP,
          ],
        ),
      ),
    );
    // Assert the .voiceChat (AEC-enabled) speaker session as soon as capture
    // begins, so the hardware echo canceller is active from the first sample
    // and the mic doesn't feed the speaker's output back to the model.
    await _routeToSpeaker();
    yield* stream;
  }

  @override
  Future<void> pauseCapture() async {
    try {
      if (await _recorder.isRecording()) {
        await _recorder.pause();
      }
    } catch (e) {
      debugPrint('RecordPcmAudioIO: pauseCapture failed: $e');
    }
  }

  @override
  Future<void> resumeCapture() async {
    try {
      if (await _recorder.isPaused()) {
        await _recorder.resume();
      }
    } catch (e) {
      debugPrint('RecordPcmAudioIO: resumeCapture failed: $e');
    }
  }

  @override
  Future<void> stopCapture() async {
    try {
      await _recorder.stop();
    } catch (e) {
      debugPrint('RecordPcmAudioIO: stopCapture failed: $e');
    }
  }

  bool _playbackStarted = false;

  Future<void> _ensurePlaybackReady() async {
    if (_playbackReady) return;
    await pcm.FlutterPcmSound.setup(
      sampleRate: _outputSampleRate,
      channelCount: 1,
      // Conversation Mode captures mic (via `record`) AND plays the model's
      // audio at the same time. `playAndRecord` lets capture and playback
      // coexist so the model's voice is audible while the mic is live.
      iosAudioCategory: pcm.IosAudioCategory.playAndRecord,
    );
    // Single feed path: we push each chunk directly in playChunk. We register
    // a NO-OP feed callback only so start() is permitted (the plugin requires a
    // callback to be set). We must NOT also drain from the callback — feeding
    // from both the callback and playChunk double-feeds the same audio, which
    // sounds like the model's voice echoing/overlapping itself.
    await pcm.FlutterPcmSound.setFeedThreshold(0);
    pcm.FlutterPcmSound.setFeedCallback((_) {});
    // flutter_pcm_sound activates playAndRecord WITHOUT defaultToSpeaker, which
    // routes output to the quiet earpiece. Re-assert speaker routing natively.
    await _routeToSpeaker();
    _playbackReady = true;
  }

  Future<void> _routeToSpeaker() async {
    try {
      await _audioChannel.invokeMethod<bool>('routeToSpeaker');
    } catch (e) {
      debugPrint('RecordPcmAudioIO: routeToSpeaker failed: $e');
    }
  }

  @override
  Future<void> playChunk(Uint8List bytes) async {
    if (bytes.isEmpty) return;
    try {
      await _ensurePlaybackReady();
      // Feed this chunk exactly once (single feed path — no callback drain, no
      // buffer accumulation — to avoid double-playing the same audio).
      final samples =
          bytes.buffer.asByteData(bytes.offsetInBytes, bytes.lengthInBytes);
      await pcm.FlutterPcmSound.feed(pcm.PcmArrayInt16(bytes: samples));
      if (!_playbackStarted) {
        pcm.FlutterPcmSound.start();
        _playbackStarted = true;
        _playbackStartedAt = DateTime.now();
        _fedAudio = Duration.zero;
      }
      // Track how much audio time we've fed so `playbackRemaining` can report
      // whether the player is still speaking. 24 kHz mono PCM16 → 2 bytes/
      // sample, so seconds = bytes / (sampleRate * 2).
      final micros =
          (bytes.lengthInBytes / (_outputSampleRate * 2) * 1e6).round();
      _fedAudio += Duration(microseconds: micros);
    } catch (e) {
      debugPrint('RecordPcmAudioIO: playChunk failed: $e');
    }
  }

  @override
  Duration get playbackRemaining {
    final startedAt = _playbackStartedAt;
    if (!_playbackStarted || startedAt == null) return Duration.zero;
    final elapsed = DateTime.now().difference(startedAt);
    final remaining = _fedAudio - elapsed;
    return remaining > Duration.zero ? remaining : Duration.zero;
  }

  bool _cuePlaying = false;

  @override
  Future<void> playThinkingCue() async {
    if (_cuePlaying) return;
    _cuePlaying = true;
    try {
      await _ensurePlaybackReady();
      // Feed a short, soft two-note "thinking" blip through the same engine
      // that plays the model's voice — so it shares the audio session and
      // speaker routing (no separate player, no session conflict).
      await pcm.FlutterPcmSound.feed(pcm.PcmArrayInt16(bytes: _thinkingTone()));
      if (!_playbackStarted) {
        pcm.FlutterPcmSound.start();
        _playbackStarted = true;
      }
    } catch (e) {
      debugPrint('RecordPcmAudioIO: playThinkingCue failed: $e');
    } finally {
      _cuePlaying = false;
    }
  }

  /// Builds a gentle, low-volume two-note tone (~360ms) at 24 kHz mono PCM16,
  /// with short fades so it sounds soft rather than a harsh beep.
  ByteData _thinkingTone() {
    const sr = _outputSampleRate; // 24000
    const noteMs = 170;
    const gapMs = 20;
    const amp = 0.16; // low volume
    final samplesPerNote = (sr * noteMs / 1000).round();
    final gapSamples = (sr * gapMs / 1000).round();
    final total = samplesPerNote * 2 + gapSamples;
    final data = ByteData(total * 2);
    var i = 0;

    void writeNote(double freq) {
      for (var n = 0; n < samplesPerNote; n++) {
        // Fade in/out over ~12ms to avoid clicks.
        final fadeLen = (sr * 12 / 1000).round();
        var env = 1.0;
        if (n < fadeLen) env = n / fadeLen;
        if (n > samplesPerNote - fadeLen) {
          env = (samplesPerNote - n) / fadeLen;
        }
        final v = amp * env * math.sin(2 * math.pi * freq * n / sr);
        data.setInt16(i * 2, (v * 32767).round(), Endian.little);
        i++;
      }
    }

    writeNote(523.25); // C5
    for (var g = 0; g < gapSamples; g++) {
      data.setInt16(i * 2, 0, Endian.little);
      i++;
    }
    writeNote(659.25); // E5 — gentle rising two-note cue
    return data;
  }

  @override
  Future<void> stopPlayback() async {
    // Release the engine (used for barge-in / turn end).
    try {
      if (_playbackReady) {
        await pcm.FlutterPcmSound.release();
        _playbackReady = false;
        _playbackStarted = false;
        _playbackStartedAt = null;
        _fedAudio = Duration.zero;
      }
    } catch (e) {
      debugPrint('RecordPcmAudioIO: stopPlayback failed: $e');
    }
  }

  @override
  Future<void> dispose() async {
    try {
      await _recorder.dispose();
    } catch (_) {}
    try {
      if (_playbackReady) await pcm.FlutterPcmSound.release();
    } catch (_) {}
    _playbackReady = false;
    _playbackStarted = false;
  }
}
