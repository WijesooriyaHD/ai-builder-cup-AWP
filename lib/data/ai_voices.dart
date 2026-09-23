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
    id: 'nova',
    name: 'Nova',
    description: 'Bright and upbeat',
    ttsVoiceName: 'Karen',
    locale: 'en-AU',
    pitch: 1.12,
    rate: 0.5,
    icon: Icons.wb_sunny_rounded,
    isPremium: false,
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
    isPremium: false,
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
];

/// Returns the voice option for [id], or the default when not found.
AiVoiceOption aiVoiceById(String? id) {
  return kAiVoices.firstWhere(
    (v) => v.id == id,
    orElse: () => kAiVoices.first,
  );
}

/// A selectable voice for the real-time Live chat pal.
///
/// These are SERVER-side prebuilt voices from the Gemini Live API, not device
/// TTS voices — so unlike [AiVoiceOption] there is no locale/pitch/rate to set
/// and no local preview: the voice is chosen when the session is created and
/// rendered by the model. [id] must be the exact prebuilt voice name the API
/// expects (it is sent as `speech_config.voice_config.prebuilt_voice_config
/// .voice_name`).
class LivePalVoiceOption {
  /// The exact Gemini prebuilt voice name. Also the value persisted in settings.
  final String id;

  /// User-facing display name.
  final String name;

  /// Short descriptor shown under the name.
  final String description;

  /// Icon shown in the selector.
  final IconData icon;

  /// Whether this voice requires a Pro subscription.
  final bool isPremium;

  const LivePalVoiceOption({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    this.isPremium = false,
  });
}

/// The catalog of selectable Live chat pal voices.
///
/// All are free for now. Because the voice is fixed when the Live session is
/// created, changing it takes effect on the NEXT conversation.
const List<LivePalVoiceOption> kLivePalVoices = [
  LivePalVoiceOption(    
    id: 'Sadaltager',
    name: 'Daniel',
    description: 'Good if you want a coach / expert feel',
    icon: Icons.emoji_events_rounded,
    isPremium: false,
  ),
  LivePalVoiceOption(    
    id: 'Achird',
    name: 'Michael',
    description: 'Friendly, natural and approachable',
    icon: Icons.emoji_events_rounded,
    isPremium: false,
  ),
  LivePalVoiceOption(    
    id: 'Charon',
    name: 'James',
    description: 'Good for guided wellness sessions',
    icon: Icons.emoji_events_rounded,
    isPremium: false,
  ),
  LivePalVoiceOption(    
    id: 'Umbriel',
    name: 'Alex',
    description: 'Relaxed and easy-going',
    icon: Icons.emoji_events_rounded,
    isPremium: false,
  ),
  LivePalVoiceOption(
    id: 'Puck',
    name: 'Ethan',
    description: 'Energetic motivator voice',
    icon: Icons.record_voice_over_rounded,
    isPremium: false,
  ),
  LivePalVoiceOption(
    id: 'Aoede',
    name: 'Aoede',
    description: 'Calm, warm, conversational',
    icon: Icons.spa_rounded,
    isPremium: false,
  ),
  LivePalVoiceOption(
    id: 'Achernar',
    name: 'Grace',
    description: 'Soft and gentle',
    icon: Icons.nightlight_round,
    isPremium: false,
  ),
  LivePalVoiceOption(
    id: 'Callirrhoe',
    name: 'Sophia',
    description: 'Relaxed and natural',
    icon: Icons.water_drop_rounded,
    isPremium: false,
  ),
  LivePalVoiceOption(
    id: 'Leda',
    name: 'Maya',
    description: 'Energetic and uplifting',
    icon: Icons.bolt_rounded,
    isPremium: false,
  ),

];

/// The default Live pal voice id.
const String kDefaultLivePalVoice = 'Sadaltager';

/// Returns the Live voice option for [id], or the default when not found.
LivePalVoiceOption livePalVoiceById(String? id) {
  return kLivePalVoices.firstWhere(
    (v) => v.id == id,
    orElse: () => kLivePalVoices.first,
  );
}
