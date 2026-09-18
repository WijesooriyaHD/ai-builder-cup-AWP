/// Central place for experimental / rollout feature flags.
///
/// Keep flags here so risky, in-progress features can ship dark (compiled but
/// disabled) and be flipped on without hunting through the codebase.
class FeatureFlags {
  const FeatureFlags._();

  /// Premium real-time "Conversation Mode" powered by the Gemini Live API.
  ///
  /// OFF by default. This backs a Preview capability of Firebase AI Logic
  /// (no SLA, may change with breaking updates), so it must stay behind this
  /// flag until the audio pipeline and Live integration are fully validated.
  ///
  /// Can be overridden at build time:
  ///   flutter run --dart-define=LIVE_CONVERSATION=true
  static const bool liveConversationMode =
      bool.fromEnvironment('LIVE_CONVERSATION', defaultValue: false);
}
