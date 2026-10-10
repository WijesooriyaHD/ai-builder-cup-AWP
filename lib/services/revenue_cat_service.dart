import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Singleton service for managing RevenueCat subscriptions
class RevenueCatService {
  static final RevenueCatService _instance = RevenueCatService._internal();
  factory RevenueCatService() => _instance;
  RevenueCatService._internal();

  // Real RevenueCat *public SDK* keys are supplied at build time via
  // --dart-define so secrets don't live in source. Pass them like:
  //   flutter run --dart-define=REVENUECAT_IOS_KEY=appl_xxx \
  //               --dart-define=REVENUECAT_ANDROID_KEY=goog_xxx
  // The `test_` fallbacks only work in debug (RevenueCat preview mode) and
  // CANNOT fetch real store products or show a real paywall on a device.
  // iOS defaults to the production public key so a release build can't ship
  // with purchases disabled just because the dart-define was forgotten (that
  // is what got build 9 rejected under guideline 2.1(b)). Public SDK keys are
  // designed to ship inside the app binary.
  static const String _iosApiKey = String.fromEnvironment(
    'REVENUECAT_IOS_KEY',
    defaultValue: 'appl_GXZTvgobYoeGIhNiiQvwhwjBxVn',
  );
  static const String _androidApiKey = String.fromEnvironment(
    'REVENUECAT_ANDROID_KEY',
    defaultValue: 'test_XblNGHDinPqDqxmWppeJYlbJIwy',
  );
  static const String proEntitlementId = 'ai_wellness_pal_pro';

  /// TEST-ONLY override to unlock all Premium features WITHOUT a real purchase.
  ///
  /// Enable by building with: `--dart-define=FORCE_PRO=true`.
  /// When set, [hasProAccess] returns true and [getSubscriptionStatus] reports
  /// an active plan, so every Premium gate in the app is open. This exists so
  /// Premium features can be tested on a device without RevenueCat/store setup.
  ///
  /// SAFETY: it's off unless the flag is explicitly passed, and it is only
  /// honoured in debug builds — a release/profile build ignores the flag even
  /// if it's passed by mistake.
  static const bool _forcePro =
      kDebugMode && bool.fromEnvironment('FORCE_PRO', defaultValue: false);

  /// Whether the test-only force-Pro override is active.
  static bool get isForcedPro => _forcePro;

  /// SharedPreferences key for cached entitlement state (Req 13.6)
  static const String _cachedIsProKey = 'rc_cached_is_pro';

  /// SharedPreferences key for upsell throttle timestamp (Req 13.5)
  static const String _upsellLastShownKey = 'upsell_last_shown_at';

  bool _isInitialized = false;

  /// True only when [Purchases.configure] actually ran successfully.
  /// When false, every method that touches the native RevenueCat SDK must
  /// short-circuit to avoid a native crash (calling the SDK before configure
  /// throws an uncatchable NSException on iOS).
  bool _isConfigured = false;

  /// Whether [Purchases.configure] actually ran, i.e. whether this build can
  /// sell anything at all.
  ///
  /// Exposed so the UI can distinguish "the store is misconfigured" from
  /// "the purchase failed", which look identical to a user and cost us an App
  /// Store rejection (guideline 2.1(b)) when a release build shipped with the
  /// `test_` placeholder key and every purchase path fell through to a generic
  /// "Something went wrong".
  bool get isConfigured => _isConfigured;

  /// True when this build cannot sell anything because it was compiled without
  /// a real API key — i.e. someone built without
  /// `--dart-define=REVENUECAT_IOS_KEY=appl_…`.
  ///
  /// Always false in debug, where the `test_` key is the expected setup.
  bool get isMisconfiguredRelease =>
      !kDebugMode && !_isConfigured && _activeApiKey.startsWith('test_');

  /// The key this platform would use, for diagnostics.
  static String get _activeApiKey =>
      Platform.isIOS ? _iosApiKey : _androidApiKey;

  CustomerInfo? _cachedCustomerInfo;
  Function(CustomerInfo)? _updateListener;

  /// Initialize RevenueCat SDK
  ///
  /// On error, falls back to cached entitlement state from SharedPreferences.
  /// If no cache exists, defaults to free tier (Req 13.6).
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      String apiKey;
      if (Platform.isIOS) {
        apiKey = _iosApiKey;
      } else if (Platform.isAndroid) {
        apiKey = _androidApiKey;
      } else {
        throw UnsupportedError('Platform not supported for RevenueCat');
      }

      // Skip RevenueCat in release mode if still using test key.
      // Mark as initialized (so callers don't retry) but NOT configured, so
      // every SDK-touching method short-circuits and never calls native code.
      if (!kDebugMode && apiKey.startsWith('test_')) {
        debugPrint(
            '⚠️ RevenueCat: Skipping init — test_ API key in a release build. '
            'Purchases, restore and Premium are DISABLED. Build with '
            '--dart-define=REVENUECAT_IOS_KEY / REVENUECAT_ANDROID_KEY '
            'set to production (appl_/goog_) keys.');
        _isInitialized = true;
        _isConfigured = false;
        return;
      }

      await Purchases.configure(
        PurchasesConfiguration(apiKey)
          ..appUserID = null, // Let RevenueCat generate anonymous ID
      );
      _isConfigured = true;

      // Enable debug logs in debug mode
      if (kDebugMode) {
        await Purchases.setLogLevel(LogLevel.debug);
      }

      _isInitialized = true;
      debugPrint('✅ RevenueCat initialized successfully');

      // Add customer info update listener
      Purchases.addCustomerInfoUpdateListener((customerInfo) {
        debugPrint('🔄 RevenueCat: CustomerInfo updated');
        _cachedCustomerInfo = customerInfo;
        _updateListener?.call(customerInfo);
      });

      // Fetch initial customer info
      await refreshCustomerInfo();
    } catch (e) {
      debugPrint('❌ RevenueCat initialization failed: $e');
      // Fallback: do not rethrow — allow the app to continue with cached state
      debugPrint('ℹ️ RevenueCat: falling back to cached entitlement state');
    }
  }

  /// Get current customer info (cached or fresh)
  Future<CustomerInfo> getCustomerInfo({bool forceRefresh = false}) async {
    if (!_isInitialized) {
      throw StateError('RevenueCat not initialized. Call initialize() first.');
    }

    // Not configured (e.g. test key skipped in release): no customer info.
    if (!_isConfigured) {
      throw StateError('RevenueCat not configured (running without a valid API key).');
    }

    if (!forceRefresh && _cachedCustomerInfo != null) {
      return _cachedCustomerInfo!;
    }

    return await refreshCustomerInfo();
  }

  /// Refresh customer info from server.
  ///
  /// On error, falls back to cached customer info or reads from
  /// SharedPreferences (Req 13.6).
  Future<CustomerInfo> refreshCustomerInfo() async {
    if (!_isConfigured) {
      if (_cachedCustomerInfo != null) return _cachedCustomerInfo!;
      throw StateError('RevenueCat not configured.');
    }
    try {
      _cachedCustomerInfo = await Purchases.getCustomerInfo();
      return _cachedCustomerInfo!;
    } catch (e) {
      debugPrint('❌ Failed to get customer info: $e');
      // If we have in-memory cached info, return it
      if (_cachedCustomerInfo != null) {
        debugPrint('ℹ️ Returning in-memory cached customer info');
        return _cachedCustomerInfo!;
      }
      rethrow;
    }
  }

  /// Forces a server round-trip, bypassing the *native* SDK cache as well as
  /// the in-memory one.
  ///
  /// [refreshCustomerInfo] only re-reads through `Purchases.getCustomerInfo()`,
  /// which the native SDK may answer from its own short-lived cache. That's
  /// fine after a purchase (the SDK updates itself), but NOT after an
  /// entitlement changes out of band:
  ///  - a promotional entitlement granted from the RevenueCat dashboard,
  ///  - an Apple offer code redeemed in the App Store app or redemption sheet,
  ///  - a Google Play promo code redeemed in the Play Store.
  ///
  /// In those cases the user can sit on a stale "free" state until the cache
  /// expires. Call this instead so the new entitlement lands immediately.
  Future<CustomerInfo> hardRefreshCustomerInfo() async {
    if (!_isConfigured) return refreshCustomerInfo();
    try {
      await Purchases.invalidateCustomerInfoCache();
    } catch (e) {
      // Non-fatal: fall through to a normal refresh.
      debugPrint('⚠️ invalidateCustomerInfoCache failed: $e');
    }
    return refreshCustomerInfo();
  }

  /// Get active subscription status
  Future<SubscriptionStatus> getSubscriptionStatus() async {
    // TEST-ONLY: report an active plan when force-Pro is on.
    if (_forcePro) return SubscriptionStatus.other;
    try {
      final customerInfo = await getCustomerInfo();
      final hasAccess = customerInfo.entitlements.active.containsKey(proEntitlementId);
      
      if (!hasAccess) {
        return SubscriptionStatus.none;
      }

      final entitlement = customerInfo.entitlements.active[proEntitlementId]!;
      final productId = entitlement.productIdentifier;

      if (productId.contains('monthly')) {
        return SubscriptionStatus.monthly;
      } else if (productId.contains('yearly') || productId.contains('annual')) {
        return SubscriptionStatus.yearly;
      }

      return SubscriptionStatus.other;
    } catch (e) {
      debugPrint('❌ Failed to get subscription status: $e');
      return SubscriptionStatus.none;
    }
  }

  /// Check if user has active pro subscription.
  ///
  /// On error, falls back to cached entitlement state from SharedPreferences.
  /// If no cached state exists, defaults to free tier (Req 13.6).
  Future<bool> hasProAccess({bool forceRefresh = false}) async {
    // TEST-ONLY: unlock everything when built with --dart-define=FORCE_PRO=true.
    if (_forcePro) {
      debugPrint('🧪 FORCE_PRO is ON — granting Premium access (test build).');
      return true;
    }
    try {
      final customerInfo = await getCustomerInfo(forceRefresh: forceRefresh);

      // Verification: make sure the customer info we're reading belongs to the
      // CURRENT app user (the Firebase UID we logged in with), not a stale
      // anonymous session. Note: `originalAppUserId` is the FIRST id RevenueCat
      // ever created for this device (often an anonymous `$RCAnonymousID:...`)
      // and does NOT change after `Purchases.logIn(uid)`. Comparing against it
      // therefore fails for every logged-in user and must not be used here.
      final currentAppUserId = await Purchases.appUserID;
      final isAnonymous = currentAppUserId.startsWith(r'$RCAnonymousID:');

      // Strictly check the entitlement
      final proEntitlement = customerInfo.entitlements.all[proEntitlementId];
      final isProActive = proEntitlement?.isActive ?? false;

      debugPrint('🛡️ RevenueCat Strict Check:');
      debugPrint('   - Current App User: $currentAppUserId (anonymous: $isAnonymous)');
      debugPrint('   - Pro Entitlement Active: $isProActive');

      // Grant access when the entitlement is active. We do not require a match
      // against `originalAppUserId` because it never equals the logged-in UID.
      final result = isProActive;

      // Cache the result to SharedPreferences for fallback (Req 13.6)
      await _cacheProStatus(result);

      return result;
    } catch (e) {
      debugPrint('❌ Failed to check pro access: $e');
      // Fallback: read cached entitlement state (Req 13.6)
      return await _getCachedProStatus();
    }
  }

  /// Caches the current pro status to SharedPreferences for offline fallback.
  Future<void> _cacheProStatus(bool isPro) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_cachedIsProKey, isPro);
    } catch (e) {
      debugPrint('⚠️ Failed to cache pro status: $e');
    }
  }

  /// Reads the cached pro status from SharedPreferences.
  /// Returns false (free tier) if no cached value exists (Req 13.6).
  Future<bool> _getCachedProStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_cachedIsProKey) ?? false;
    } catch (e) {
      debugPrint('⚠️ Failed to read cached pro status: $e');
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // 48-Hour Upsell Throttle (Req 13.5)
  // ---------------------------------------------------------------------------

  /// Checks whether a proactive upsell prompt can be shown.
  ///
  /// Returns `true` if the prompt can be shown (more than 48 hours since the
  /// last proactive upsell, or no record exists). Returns `false` if within
  /// the 48-hour suppression window.
  ///
  /// This does NOT apply to paywalls triggered by the user tapping a locked
  /// feature — those should bypass this check entirely.
  Future<bool> canShowProactiveUpsell() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastShownMs = prefs.getInt(_upsellLastShownKey);

      if (lastShownMs == null) return true;

      final lastShown = DateTime.fromMillisecondsSinceEpoch(lastShownMs);
      final elapsed = DateTime.now().difference(lastShown);
      return elapsed.inHours >= 48;
    } catch (e) {
      debugPrint('⚠️ Error checking upsell throttle: $e');
      return true; // Default to allowing on error
    }
  }

  /// Records that a proactive upsell prompt was shown right now.
  ///
  /// Writes the current timestamp to SharedPreferences and to the user's
  /// Firestore document (`upsell_last_shown_at`) for cross-device consistency.
  Future<void> recordUpsellShown({String? userId}) async {
    try {
      final now = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_upsellLastShownKey, now.millisecondsSinceEpoch);

      // Also persist to Firestore for cross-device throttling
      if (userId != null && userId.isNotEmpty) {
        try {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .update({'upsell_last_shown_at': Timestamp.fromDate(now)});
        } catch (e) {
          debugPrint('⚠️ Failed to write upsell timestamp to Firestore: $e');
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error recording upsell shown: $e');
    }
  }

  /// Syncs the upsell throttle timestamp from Firestore to local storage.
  /// Called during cloud sync to ensure cross-device consistency.
  Future<void> syncUpsellThrottleFromFirestore(String userId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();

      if (doc.exists) {
        final data = doc.data();
        final timestamp = data?['upsell_last_shown_at'] as Timestamp?;
        if (timestamp != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt(
              _upsellLastShownKey, timestamp.toDate().millisecondsSinceEpoch);
        }
      }
    } catch (e) {
      debugPrint('⚠️ Failed to sync upsell throttle from Firestore: $e');
    }
  }

  /// Restore purchases
  Future<CustomerInfo> restorePurchases() async {
    if (!_isConfigured) {
      throw StateError('RevenueCat not configured — cannot restore purchases.');
    }
    try {
      final customerInfo = await Purchases.restorePurchases();
      _cachedCustomerInfo = customerInfo;
      debugPrint('✅ Purchases restored successfully');
      return customerInfo;
    } catch (e) {
      debugPrint('❌ Failed to restore purchases: $e');
      rethrow;
    }
  }

  /// Get available offerings
  Future<Offerings?> getOfferings() async {
    if (!_isConfigured) return null;
    try {
      return await Purchases.getOfferings();
    } catch (e) {
      debugPrint('❌ Failed to get offerings: $e');
      return null;
    }
  }

  /// Presents the RevenueCat-hosted paywall for the current (default) offering.
  ///
  /// This is the single, guarded entry point every "Upgrade" action should use
  /// so behavior stays consistent and a misconfiguration degrades gracefully
  /// instead of crashing on a real device:
  /// - If the SDK isn't configured (e.g. a `test_` key skipped in release),
  ///   returns null instead of touching native code (which would crash).
  /// - If there's no current offering with packages (products/paywall not set
  ///   up), returns null so the caller can show a friendly message rather than
  ///   present a paywall that will fail.
  ///
  /// The three paywall "stages" are variations on the same default offering and
  /// are served server-side by RevenueCat, so no per-offering routing is needed
  /// here. Returns the [PaywallResult], or null when a paywall can't be shown.
  Future<PaywallResult?> presentPaywall() async {
    if (!_isConfigured) {
      debugPrint('⚠️ presentPaywall: RevenueCat not configured — skipping.');
      return null;
    }
    try {
      // Preflight: make sure there's actually something to sell before showing
      // the paywall (avoids the native failure path on a real device).
      final offerings = await Purchases.getOfferings();
      final current = offerings.current;
      if (current == null || current.availablePackages.isEmpty) {
        debugPrint('⚠️ presentPaywall: no current offering / packages available.');
        return null;
      }
      // Always show a close button so the user can dismiss the paywall.
      // (Ignored for v2 paywalls, which provide their own close control.)
      return await RevenueCatUI.presentPaywall(displayCloseButton: true);
    } on PlatformException catch (e) {
      debugPrint('❌ presentPaywall failed: ${e.message}');
      return null;
    } catch (e) {
      debugPrint('❌ presentPaywall error: $e');
      return null;
    }
  }

  /// Opens the platform's promo-code redemption flow.
  ///
  /// NOTE: this deliberately does NOT go through a `redemption_button`
  /// component on the RevenueCat-hosted paywall. That component type is not
  /// decodable by any current mobile SDK (verified against RevenueCat /
  /// RevenueCatUI 5.90.2 via purchases_flutter 10.13.2) — and worse, when it
  /// appears inside a Workflow the whole remote config fails to decode and
  /// takes `getOfferings()` down with it (BackendError 8). The native flows
  /// below are the supported path.
  ///
  ///  - **iOS**: presents Apple's in-app offer-code redemption sheet.
  ///  - **Android**: opens the Play Store redeem page (Play has no in-app
  ///    sheet; codes are always redeemed in the Play Store app).
  ///
  /// Neither platform reports the redemption result synchronously, so callers
  /// must re-check entitlements afterwards — this method already performs a
  /// [hardRefreshCustomerInfo] on iOS, and callers should re-check on resume
  /// for the Android path.
  ///
  /// Returns false when no redemption flow could be opened.
  Future<bool> redeemPromoCode() async {
    if (!_isConfigured) {
      debugPrint('⚠️ redeemPromoCode: RevenueCat not configured — skipping.');
      return false;
    }

    if (Platform.isIOS) {
      try {
        await Purchases.presentCodeRedemptionSheet();
        // StoreKit finishes the transaction asynchronously and gives us no
        // callback, so force a server read rather than trusting the cache.
        await hardRefreshCustomerInfo();
        return true;
      } on PlatformException catch (e) {
        debugPrint('❌ presentCodeRedemptionSheet failed: ${e.message}');
        return false;
      } catch (e) {
        debugPrint('❌ presentCodeRedemptionSheet error: $e');
        return false;
      }
    }

    if (Platform.isAndroid) {
      try {
        final uri = Uri.parse('https://play.google.com/redeem');
        if (await canLaunchUrl(uri)) {
          return await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
        debugPrint('❌ redeemPromoCode: cannot launch Play redeem URL.');
        return false;
      } catch (e) {
        debugPrint('❌ redeemPromoCode (Android) error: $e');
        return false;
      }
    }

    return false;
  }

  /// Purchase a package
  Future<CustomerInfo> purchasePackage(Package package) async {
    if (!_isConfigured) {
      throw StateError('RevenueCat not configured — cannot purchase.');
    }
    try {
      final purchaserInfo = await Purchases.purchasePackage(package);
      _cachedCustomerInfo = purchaserInfo.customerInfo;
      debugPrint('✅ Purchase successful');
      return purchaserInfo.customerInfo;
    } on PlatformException catch (e) {
      final errorCode = PurchasesErrorHelper.getErrorCode(e);
      if (errorCode == PurchasesErrorCode.purchaseCancelledError) {
        debugPrint('ℹ️ Purchase cancelled by user');
      } else {
        debugPrint('❌ Purchase failed: ${e.message}');
      }
      rethrow;
    }
  }

  /// Set user email for RevenueCat
  Future<void> setEmail(String email) async {
    if (!_isConfigured) return;
    try {
      await _boundOnAndroid(Purchases.setEmail(email));
      debugPrint('✅ Set RevenueCat email: $email');
    } catch (e) {
      debugPrint('❌ Failed to set RevenueCat email: $e');
    }
  }

  /// Log in a user with a custom App User ID (e.g. Supabase UID)
  Future<void> logIn(String userId) async {
    if (!_isConfigured) return;
    try {
      final result = await _boundOnAndroid(Purchases.logIn(userId));
      _cachedCustomerInfo = result.customerInfo;
      debugPrint('✅ RevenueCat: Logged in as $userId');
      _updateListener?.call(result.customerInfo);
    } catch (e) {
      debugPrint('❌ RevenueCat: Log in failed: $e');
    }
  }

  /// Sign-in awaits [logIn] and [setEmail], and on some Android devices the
  /// native call can hang indefinitely, leaving the sign-in spinner stuck.
  /// Cap the wait on Android so sign-in always completes; the SDK still
  /// finishes in the background and the next launch logs in again anyway.
  /// iOS is left unbounded, matching its existing behaviour.
  Future<T> _boundOnAndroid<T>(Future<T> call) {
    if (!Platform.isAndroid) return call;
    return call.timeout(const Duration(seconds: 8));
  }

  /// Log out the current user and return to an anonymous ID
  Future<void> logOut() async {
    if (!_isConfigured) return;
    try {
      _cachedCustomerInfo = await Purchases.logOut();
      debugPrint('✅ RevenueCat: Logged out');
      _updateListener?.call(_cachedCustomerInfo!);
    } catch (e) {
      debugPrint('❌ RevenueCat: Log out failed: $e');
    }
  }

  /// Set listener for customer info updates
  void setUpdateListener(Function(CustomerInfo) callback) {
    _updateListener = callback;
  }

  /// Manage subscriptions by opening the appropriate store URL.
  ///
  /// Returns false if the store page couldn't be opened, so the caller can
  /// tell the user how to get there themselves.
  Future<bool> manageSubscriptions() async {
    try {
      final customerInfo = await getCustomerInfo();
      String? url = customerInfo.managementURL;
      
      if (url == null) {
        if (Platform.isIOS) {
          url = 'https://apps.apple.com/account/subscriptions';
        } else if (Platform.isAndroid) {
          url = 'https://play.google.com/store/account/subscriptions';
        }
      }

      if (url != null) {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri) &&
            await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          return true;
        }
        debugPrint('❌ Could not launch subscription management URL: $url');
      }
    } catch (e) {
      debugPrint('❌ Error managing subscriptions: $e');
    }
    return false;
  }

  /// Clear cached customer info (useful for testing)
  void clearCache() {
    _cachedCustomerInfo = null;
  }
}

enum SubscriptionStatus {
  none,
  monthly,
  yearly,
  other,
}
