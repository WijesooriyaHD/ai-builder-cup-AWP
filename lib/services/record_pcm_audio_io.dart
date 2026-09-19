import 'dart:typed_data';

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
  static const MethodChannel _audioChannel = MethodChannel('bloom/audio');
  bool _playbackReady = false;

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
      }
    } catch (e) {
      debugPrint('RecordPcmAudioIO: playChunk failed: $e');
    }
  }

  @override
  Future<void> stopPlayback() async {
    // Release the engine (used for barge-in / turn end).
    try {
      if (_playbackReady) {
        await pcm.FlutterPcmSound.release();
        _playbackReady = false;
        _playbackStarted = false;
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
