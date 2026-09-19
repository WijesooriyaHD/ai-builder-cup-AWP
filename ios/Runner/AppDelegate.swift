import Flutter
import UIKit
import AVFoundation
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

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
