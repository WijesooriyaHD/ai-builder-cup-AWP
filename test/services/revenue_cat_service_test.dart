import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aiwellnesspal/services/revenue_cat_service.dart';

/// Tests for the RevenueCat fallback, upsell throttle, and lapse detection
/// features added in task 16.3.
///
/// Note: We cannot test full RevenueCat SDK calls in unit tests (they require
/// platform channels), so we test the SharedPreferences-based helpers directly.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RevenueCat Fallback (Req 13.6)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('getCachedProStatus returns false when no cached value exists', () async {
      // Access the private method indirectly via hasProAccess behavior:
      // Since RevenueCat is not initialized, hasProAccess will throw and fall
      // back to cached status. With no cached value, it should return false.
      final service = RevenueCatService();
      // Not initializing RC — calling hasProAccess will fail and fall back
      final result = await service.hasProAccess();
      expect(result, isFalse);
    });

    test('cached pro status is returned on error when previously set to true', () async {
      // Pre-set the cached value to true
      SharedPreferences.setMockInitialValues({'rc_cached_is_pro': true});

      final service = RevenueCatService();
      // Not initializing RC — calling hasProAccess will fail and use cached value
      final result = await service.hasProAccess();
      expect(result, isTrue);
    });

    test('cached pro status is returned on error when previously set to false', () async {
      SharedPreferences.setMockInitialValues({'rc_cached_is_pro': false});

      final service = RevenueCatService();
      final result = await service.hasProAccess();
      expect(result, isFalse);
    });
  });

  group('48-Hour Upsell Throttle (Req 13.5)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('canShowProactiveUpsell returns true when no previous upsell recorded', () async {
      final service = RevenueCatService();
      final result = await service.canShowProactiveUpsell();
      expect(result, isTrue);
    });

    test('canShowProactiveUpsell returns false within 48 hours of last shown', () async {
      final recentTimestamp = DateTime.now()
          .subtract(const Duration(hours: 24))
          .millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues({
        'upsell_last_shown_at': recentTimestamp,
      });

      final service = RevenueCatService();
      final result = await service.canShowProactiveUpsell();
      expect(result, isFalse);
    });

    test('canShowProactiveUpsell returns true after 48 hours have elapsed', () async {
      final oldTimestamp = DateTime.now()
          .subtract(const Duration(hours: 49))
          .millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues({
        'upsell_last_shown_at': oldTimestamp,
      });

      final service = RevenueCatService();
      final result = await service.canShowProactiveUpsell();
      expect(result, isTrue);
    });

    test('canShowProactiveUpsell returns false at exactly 47 hours', () async {
      final almostTimestamp = DateTime.now()
          .subtract(const Duration(hours: 47))
          .millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues({
        'upsell_last_shown_at': almostTimestamp,
      });

      final service = RevenueCatService();
      final result = await service.canShowProactiveUpsell();
      expect(result, isFalse);
    });

    test('recordUpsellShown writes timestamp to SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});

      final service = RevenueCatService();
      await service.recordUpsellShown();

      final prefs = await SharedPreferences.getInstance();
      final storedMs = prefs.getInt('upsell_last_shown_at');
      expect(storedMs, isNotNull);

      // Should be within the last second
      final storedTime = DateTime.fromMillisecondsSinceEpoch(storedMs!);
      final diff = DateTime.now().difference(storedTime);
      expect(diff.inSeconds, lessThan(2));
    });

    test('after recordUpsellShown, canShowProactiveUpsell returns false', () async {
      SharedPreferences.setMockInitialValues({});

      final service = RevenueCatService();
      await service.recordUpsellShown();

      final result = await service.canShowProactiveUpsell();
      expect(result, isFalse);
    });
  });
}
