import 'package:flutter/material.dart';

/// A selectable text-to-speech voice for the AI assistant.
class AiVoiceOption {
  /// Stable identifier persisted in settings.
  final String id;

  /// User-facing display name.
  final String name;

  /// Short descriptor shown under the name.
  final String description;

  /// The platform TTS voice name (iOS/Android voice name). May be null for the
  /// default system voice, in which case only language/pitch/rate are applied.
  final String? ttsVoiceName;

  /// BCP-47 locale for the voice.
  final String locale;

  /// Speech pitch (1.0 = normal).
  final double pitch;

  /// Speech rate (matches flutter_tts scale; ~0.48 is the app default).
  final double rate;

  /// Icon shown in the selector.
  final IconData icon;

  /// Whether this voice requires a Pro subscription.
  final bool isPremium;

  const AiVoiceOption({
    required this.id,
    required this.name,
    required this.description,
    this.ttsVoiceName,
    this.locale = 'en-US',
    this.pitch = 1.0,
    this.rate = 0.48,
    required this.icon,
    this.isPremium = false,
  });
}

/// The catalog of selectable AI voices.
///
/// The first option ("default") is free; the rest are Pro-only. `ttsVoiceName`
/// values correspond to common Apple system voices; if a voice isn't available
/// on the device, flutter_tts falls back to the system default for the locale,
/// while pitch/rate still apply so each option still sounds distinct.
const List<AiVoiceOption> kAiVoices = [
  AiVoiceOption(
    id: 'default',
    name: 'Default',
    description: 'The standard pal voice',
    ttsVoiceName: null,
    pitch: 1.0,
    rate: 0.48,
    icon: Icons.record_voice_over_rounded,
    isPremium: false,
  ),
  AiVoiceOption(
    id: 'aria',
    name: 'Aria',
    description: 'Warm and calming',
    ttsVoiceName: 'Samantha',
    locale: 'en-US',
    pitch: 1.05,
    rate: 0.46,
    icon: Icons.spa_rounded,
    isPremium: true,
  ),
  AiVoiceOption(
    id: 'nova',
    name: 'Nova',
    description: 'Bright and upbeat',
    ttsVoiceName: 'Karen',
    locale: 'en-AU',
    pitch: 1.12,
    rate: 0.5,
    icon: Icons.wb_sunny_rounded,
    isPremium: true,
  ),
  AiVoiceOption(
    id: 'atlas',
    name: 'Atlas',
    description: 'Deep and grounded',
    ttsVoiceName: 'Daniel',
    locale: 'en-GB',
    pitch: 0.9,
    rate: 0.46,
    icon: Icons.terrain_rounded,
    isPremium: true,
  ),
  AiVoiceOption(
    id: 'sage',
    name: 'Sage',
    description: 'Gentle and soothing',
    ttsVoiceName: 'Moira',
    locale: 'en-IE',
    pitch: 1.0,
    rate: 0.44,
    icon: Icons.self_improvement_rounded,
    isPremium: true,
  ),
];

/// Returns the voice option for [id], or the default when not found.
AiVoiceOption aiVoiceById(String? id) {
  return kAiVoices.firstWhere(
    (v) => v.id == id,
    orElse: () => kAiVoices.first,
  );
}
