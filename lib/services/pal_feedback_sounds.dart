import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// Auditory + haptic cues for the Live pal, similar in spirit to the
/// "start listening" / "stop listening" pings in ChatGPT's voice mode.
///
/// On iOS the audible tones use the platform's built-in recording chirps
/// (`SystemSoundID` 1113/1114 — the same tones Voice Control uses). They are
/// deliberately routed through the native `LiveAudioEngine` method channel so
/// they play at proper volume through the loudspeaker even while the Live
/// pipeline holds a `.playAndRecord`/`.voiceChat` audio session, which mutes
/// the quieter `SystemSound.click`.
class PalFeedbackSounds {
  const PalFeedbackSounds._();

  static const MethodChannel _channel =
      MethodChannel('aiwellnesspal/live_audio');

  // iOS built-in SystemSoundIDs — these are shipped with the OS and audible at
  // ringer volume, independent of the current audio session category.
  static const int _beginRecording = 1113; // ascending chirp
  static const int _endRecording = 1114; // descending chirp
  static const int _tink = 1103; // short "tink" for lighter cues

  /// Cue that the Live pal is opening / actively listening for the user.
  static Future<void> conversationStart() async {
    unawaited(_playSystemSound(_beginRecording));
    unawaited(HapticFeedback.lightImpact());
  }

  /// Cue that the Live pal has ended a conversation.
  static Future<void> conversationEnd() async {
    unawaited(_playSystemSound(_endRecording));
    unawaited(HapticFeedback.selectionClick());
  }

  /// Cue that a wake phrase was recognised. Fires before the sheet opens so the
  /// user gets immediate confirmation even during the brief handoff to Live.
  static Future<void> wakeAcknowledged() async {
    unawaited(_playSystemSound(_tink));
    unawaited(HapticFeedback.mediumImpact());
  }

  /// Cue for the gentle idle check-in ("Are you still there?"). A very short
  /// tink is used so it never masks the pal's soft prompt that follows.
  static Future<void> idleCheckIn() async {
    unawaited(HapticFeedback.selectionClick());
    unawaited(_playSystemSound(_tink));
  }

  /// Cue that the Live session failed / errored out.
  static Future<void> error() async {
    unawaited(HapticFeedback.heavyImpact());
    unawaited(_playSystemSound(_endRecording));
  }

  static Future<void> _playSystemSound(int id) async {
    // The native channel exists only in the iOS Runner; other platforms
    // gracefully fall back to the haptic alone.
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod<void>('playSystemCue', {'id': id});
    } catch (_) {
      // Never fail a session because a cue could not play.
    }
  }
}
