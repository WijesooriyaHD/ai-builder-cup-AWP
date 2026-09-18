import Flutter
import UIKit
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
