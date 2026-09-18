import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';
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
      ),
    );
    yield* stream;
  }

  @override
  Future<void> stopCapture() async {
    try {
      await _recorder.stop();
    } catch (e) {
      debugPrint('RecordPcmAudioIO: stopCapture failed: $e');
    }
  }

  Future<void> _ensurePlaybackReady() async {
    if (_playbackReady) return;
    await FlutterPcmSound.setup(
      sampleRate: _outputSampleRate,
      channelCount: 1,
    );
    _playbackReady = true;
  }

  @override
  Future<void> playChunk(Uint8List pcm) async {
    if (pcm.isEmpty) return;
    try {
      await _ensurePlaybackReady();
      // The model returns raw little-endian PCM16 bytes; wrap them directly as
      // an int16 sample buffer for the player (no per-sample re-encoding).
      final samples = pcm.buffer.asByteData(pcm.offsetInBytes, pcm.lengthInBytes);
      await FlutterPcmSound.feed(PcmArrayInt16(bytes: samples));
    } catch (e) {
      debugPrint('RecordPcmAudioIO: playChunk failed: $e');
    }
  }

  @override
  Future<void> stopPlayback() async {
    // flutter_pcm_sound drains its queued frames; releasing + re-setup on next
    // chunk is the simplest way to flush for barge-in. Guarded so a failure
    // never crashes the session.
    try {
      if (_playbackReady) {
        await FlutterPcmSound.release();
        _playbackReady = false;
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
      if (_playbackReady) await FlutterPcmSound.release();
    } catch (_) {}
    _playbackReady = false;
  }
}
