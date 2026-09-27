import Flutter
import UIKit
import AVFoundation
import WidgetKit
import home_widget

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Audio-routing channel for Conversation Mode (Gemini Live).
    //
    // flutter_pcm_sound sets the AVAudioSession to `playAndRecord` WITHOUT the
    // `defaultToSpeaker` option, so on iPhone the model's audio is routed to
    // the quiet earpiece (receiver) — it plays but is effectively inaudible.
    // Dart calls `routeToSpeaker` after starting playback to force the session
    // to play-and-record with speaker output + Bluetooth, so the reply is heard
    // on the loudspeaker while the mic keeps capturing.
    if let controller = window?.rootViewController as? FlutterViewController {
      let audioChannel = FlutterMethodChannel(
        name: "aiwellnesspal/audio", binaryMessenger: controller.binaryMessenger)
      audioChannel.setMethodCallHandler { call, result in
        if call.method == "routeToSpeaker" {
          let session = AVAudioSession.sharedInstance()
          do {
            // `.voiceChat` mode enables the system's hardware acoustic echo
            // cancellation (AEC), so the mic doesn't pick up the model's voice
            // from the loudspeaker and echo it back. Do NOT use `.mixWithOthers`
            // here — it disables the voice-processing I/O and re-introduces echo.
            try session.setCategory(
              .playAndRecord,
              mode: .voiceChat,
              options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
            try session.setActive(true)
            try session.overrideOutputAudioPort(.speaker)
            result(true)
          } catch {
            result(FlutterError(
              code: "audio_route_failed",
              message: error.localizedDescription, details: nil))
          }
        } else if call.method == "bestEnhancedVoice" {
          // Returns the BEST available English voice (by quality tier) so the
          // reader narration can use it when "Higher-quality voice" is on. We
          // query AVSpeechSynthesisVoice directly, where `.quality` (default /
          // enhanced / premium) and a stable `.identifier` are available. Dart
          // applies the returned identifier via setVoice.
          //
          // NOTE: we return the best voice EVEN IF it's only `default` quality,
          // along with a `quality` label, so the narration always switches to a
          // deliberately chosen voice and the UI can report exactly what the
          // device offers (enhanced voices are a separate, optional download in
          // Settings → Accessibility → Spoken Content → Voices).
          let prefLang = (call.arguments as? [String: Any])?["language"]
            as? String ?? "en"
          let voices = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.lowercased().hasPrefix(prefLang.lowercased())
          }
          func rank(_ q: AVSpeechSynthesisVoiceQuality) -> Int {
            if #available(iOS 16.0, *), q == .premium { return 3 }
            if q == .enhanced { return 2 }
            return 1 // default / compact
          }
          func qualityLabel(_ q: AVSpeechSynthesisVoiceQuality) -> String {
            if #available(iOS 16.0, *), q == .premium { return "premium" }
            if q == .enhanced { return "enhanced" }
            return "default"
          }
          // Best = highest quality; prefer en-US among equals.
          let best = voices.max { a, b in
            let ra = rank(a.quality), rb = rank(b.quality)
            if ra != rb { return ra < rb }
            let aUS = a.language.lowercased() == "en-us" ? 1 : 0
            let bUS = b.language.lowercased() == "en-us" ? 1 : 0
            return aUS < bUS
          }
          if let v = best {
            result([
              "identifier": v.identifier,
              "name": v.name,
              "locale": v.language,
              "quality": qualityLabel(v.quality),
            ])
          } else {
            result(nil)
          }
        } else if call.method == "listVoices" {
          // Diagnostic: the full installed English voice inventory with quality
          // tiers, so we can see whether an enhanced voice is actually present.
          let voices = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.lowercased().hasPrefix("en")
          }
          func qualityLabel(_ q: AVSpeechSynthesisVoiceQuality) -> String {
            if #available(iOS 16.0, *), q == .premium { return "premium" }
            if q == .enhanced { return "enhanced" }
            return "default"
          }
          result(voices.map {
            [
              "name": $0.name,
              "locale": $0.language,
              "quality": qualityLabel($0.quality),
              "identifier": $0.identifier,
            ]
          })
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }

    // Register the plugin registrant callback so the home_widget background
    // worker (used by the interactive AI Wellness widget toggle on iOS 17+)
    // can spin up a headless Flutter engine and run the Dart backgroundCallback.
    if #available(iOS 17.0, *) {
      HomeWidgetBackgroundWorker.setPluginRegistrantCallback { registry in
        GeneratedPluginRegistrant.register(with: registry)
      }
    }

    // Hydration widget sync channel. Dart calls "push" with
    // {consumed: Int, goal: Int, pct: Int} whenever water is logged so the
    // native HydrationSyncCache has the latest values. On background transition
    // the cache flushes directly to the app-group UserDefaults and WidgetKit
    // reloads — no async platform-channel round-trip needed at that point.
    if let controller = window?.rootViewController as? FlutterViewController {
      let hydrationChannel = FlutterMethodChannel(
        name: "aiwellnesspal/hydration_sync",
        binaryMessenger: controller.binaryMessenger)
      hydrationChannel.setMethodCallHandler { call, result in
        if call.method == "push",
           let args = call.arguments as? [String: Any]
        {
          let consumed = args["consumed"] as? Int ?? 0
          let goal     = args["goal"]     as? Int ?? 0
          let pct      = args["pct"]      as? Int ?? 0
          HydrationSyncCache.shared.update(consumedMl: consumed, goalMl: goal, pct: pct)
          result(nil)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }

      // Unified, echo-cancelled Live audio engine (AVAudioEngine +
      // Voice-Processing I/O). Registers the "aiwellnesspal/live_audio" method
      // channel + "aiwellnesspal/live_audio/mic" event channel used by the
      // NativeAecAudioIO Dart bridge for the Gemini Live "pal" conversation.
      LiveAudioEngine.shared.register(with: controller.binaryMessenger)
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// On background transition: write the latest hydration snapshot (cached by
  /// the HydrationSyncCache channel from Dart) into the widget app-group and
  /// tell WidgetKit to reload. This runs synchronously in native Swift before
  /// the process suspends — no dependency on the Dart async chain.
  override func applicationDidEnterBackground(_ application: UIApplication) {
    super.applicationDidEnterBackground(application)
    if #available(iOS 14.0, *) {
      HydrationSyncCache.shared.flushToAppGroup()
      WidgetCenter.shared.reloadTimelines(ofKind: "HydrationToolWidget")
      NSLog("[AppDelegate] Hydration widget reloaded on background transition")
    }
  }
}

// MARK: - HydrationSyncCache
//
// A lightweight in-process cache for the latest hydration values. Dart calls
// the "aiwellnesspal/hydration_sync" channel to push values any time water is
// logged; AppDelegate.applicationDidEnterBackground flushes them into the
// widget app-group and triggers a WidgetKit reload. This bypasses the
// home_widget plugin's async platform-channel path entirely, guaranteeing the
// app-group is up to date before the process suspends.
class HydrationSyncCache {
  static let shared = HydrationSyncCache()
  private let appGroup = "group.com.aiwellnesspal.app"
  private var consumedMl: Int = 0
  private var goalMl: Int = 0
  private var pct: Int = 0

  func update(consumedMl: Int, goalMl: Int, pct: Int) {
    self.consumedMl = consumedMl
    self.goalMl     = goalMl
    self.pct        = pct
    // Also write to the app group immediately so WidgetKit's next scheduled
    // reload picks up the value even if the app is still in the foreground.
    flushToAppGroup()
  }

  func flushToAppGroup() {
    guard let defaults = UserDefaults(suiteName: appGroup) else { return }
    defaults.set(consumedMl, forKey: "hydration_consumed_ml")
    defaults.set(goalMl,     forKey: "hydration_goal_ml")
    defaults.set(pct,        forKey: "hydration_pct")
    defaults.synchronize()   // force immediate write to disk
    NSLog("[HydrationSyncCache] flushed consumed=\(consumedMl) goal=\(goalMl) pct=\(pct)%%")
  }
}
