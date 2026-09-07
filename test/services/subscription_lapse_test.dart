import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tests for the subscription lapse banner logic (Req 13.8).
///
/// These tests validate the SharedPreferences-based persistence of the
/// lapse banner shown flag. The full lapse detection logic lives in AppState
/// and depends on RevenueCat callbacks, so here we test the storage layer
/// behavior that supports it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const lapseBannerShownKey = 'lapse_banner_shown';

  group('Subscription Lapse Banner Persistence (Req 13.8)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('lapse banner shown flag is false by default', () async {
      final prefs = await SharedPreferences.getInstance();
      final shown = prefs.getBool(lapseBannerShownKey) ?? false;
      expect(shown, isFalse);
    });

    test('setting lapse banner shown flag to true persists', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(lapseBannerShownKey, true);

      final result = prefs.getBool(lapseBannerShownKey);
      expect(result, isTrue);
    });

    test('banner should only show once: after setting, remains true', () async {
      final prefs = await SharedPreferences.getInstance();

      // Simulate first dismissal
      await prefs.setBool(lapseBannerShownKey, true);

      // On subsequent app opens, the flag remains true → banner won't show
      final shouldShow = !(prefs.getBool(lapseBannerShownKey) ?? false);
      expect(shouldShow, isFalse);
    });

    test('removing the flag allows the banner to show again (re-subscribe cycle)', () async {
      final prefs = await SharedPreferences.getInstance();

      // User dismissed the banner previously
      await prefs.setBool(lapseBannerShownKey, true);
      expect(prefs.getBool(lapseBannerShownKey), isTrue);

      // User re-subscribes and then lapses again — reset the flag
      await prefs.remove(lapseBannerShownKey);

      final shouldShow = !(prefs.getBool(lapseBannerShownKey) ?? false);
      expect(shouldShow, isTrue);
    });
  });
}
