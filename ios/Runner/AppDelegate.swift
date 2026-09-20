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
    // Fixed Firebase App Check DEBUG token.
    //
    // The Firebase App Check debug provider reads this token from the
    // `FIRAAppCheckDebugToken` environment variable at startup. Setting it here
    // (BEFORE GeneratedPluginRegistrant.register triggers FirebaseApp.configure)
    // pins a known, stable token instead of a randomly generated one. This lets
    // us register a single token in the Firebase console and reuse it on the
    // physical device (which cannot use App Attest on a free/personal Apple
    // team) as well as after reinstalls.
    //
    // This only has an effect when the app runs the App Check DEBUG provider
    // (debug builds, or release builds launched with
    // --dart-define=APPCHECK_DEBUG=true). Production App Attest builds ignore it.
    // Register this exact value under Firebase console → App Check → Apps →
    // iOS app → Manage debug tokens.
    setenv("FIRAAppCheckDebugToken", "5002195D-47B7-4B69-A59F-9A4C0A94575B", 1)

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
