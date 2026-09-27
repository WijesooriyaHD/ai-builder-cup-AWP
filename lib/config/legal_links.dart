import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Public legal and support pages, hosted on GitHub Pages
/// (github.com/viraj-dhanushka/AIWellnessPal).
///
/// App Store Review requires the Privacy Policy to be reachable inside the app
/// (Guideline 5.1.1(i)) and the Terms of Use / EULA to be linked for
/// auto-renewing subscriptions (Guideline 3.1.2). Keep these in sync with the
/// URLs entered in App Store Connect and the RevenueCat paywall.
class LegalLinks {
  LegalLinks._();

  static const String privacyPolicy =
      'https://viraj-dhanushka.github.io/AIWellnessPal/privacy.html';
  static const String termsOfUse =
      'https://viraj-dhanushka.github.io/AIWellnessPal/terms.html';
  static const String support =
      'https://viraj-dhanushka.github.io/AIWellnessPal/';

  /// Opens [url] in an in-app browser. Returns false if it could not open.
  static Future<bool> open(String url) async {
    try {
      return await launchUrl(Uri.parse(url), mode: LaunchMode.inAppBrowserView);
    } catch (e) {
      debugPrint('❌ LegalLinks: could not open $url: $e');
      return false;
    }
  }
}
