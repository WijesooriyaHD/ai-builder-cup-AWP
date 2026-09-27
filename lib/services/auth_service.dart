import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'revenue_cat_service.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// SharedPreferences key to track whether the user is logged in.
  static const String _isLoggedInKey = 'is_logged_in';

  /// Persist logged-in state so the app can silently skip the auth screen
  /// on next launch.
  Future<void> setLoggedIn(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_isLoggedInKey, value);
  }

  /// Check whether the user was previously logged in (and never signed out).
  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_isLoggedInKey) ?? false;
  }

  /// Firebase Auth is initialized automatically via firebase_core (Firebase.initializeApp).
  /// This method syncs the currently signed-in user with RevenueCat on startup
  /// and initializes Google Sign-In.
  static Future<void> initialize() async {
    try {
      // Initialize Google Sign-In with timeout to prevent blocking on real devices
      try {
        await GoogleSignIn.instance.initialize()
            .timeout(const Duration(seconds: 5));
      } catch (e) {
        debugPrint('⚠️ GoogleSignIn initialization failed/timed out: $e');
      }

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        await RevenueCatService()
            .logIn(currentUser.uid)
            .timeout(const Duration(seconds: 5));
        if (currentUser.email != null) {
          await RevenueCatService()
              .setEmail(currentUser.email!)
              .timeout(const Duration(seconds: 5));
        }
      }
      debugPrint('✅ AuthService initialized successfully');
    } catch (e) {
      debugPrint('❌ AuthService initialization failed: $e');
    }
  }

  /// Get current user
  User? get currentUser => _auth.currentUser;

  /// Stream of auth state changes
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Sign up with email and password
  Future<UserCredential> signUp({
    required String email,
    required String password,
    String? displayName,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Set display name if provided
      if (displayName != null && displayName.isNotEmpty) {
        await credential.user?.updateDisplayName(displayName);
        await credential.user?.reload();
      }

      // Sync to RevenueCat
      if (credential.user != null) {
        await RevenueCatService().logIn(credential.user!.uid);
        if (credential.user!.email != null) {
          await RevenueCatService().setEmail(credential.user!.email!);
        }
      }

      // Persist login state for silent sign-in on next launch
      await setLoggedIn(true);

      return credential;
    } on FirebaseAuthException catch (e) {
      debugPrint('❌ Sign up failed: ${e.message}');
      rethrow;
    }
  }

  /// Sign in with email and password
  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Sync to RevenueCat
      if (credential.user != null) {
        await RevenueCatService().logIn(credential.user!.uid);
        if (credential.user!.email != null) {
          await RevenueCatService().setEmail(credential.user!.email!);
        }
      }

      // Persist login state for silent sign-in on next launch
      await setLoggedIn(true);

      return credential;
    } on FirebaseAuthException catch (e) {
      debugPrint('❌ Sign in failed: ${e.message}');
      rethrow;
    }
  }

  /// Sign in with Google (works for both login and sign-up).
  ///
  /// Returns the [UserCredential] on success, or `null` if the user
  /// cancelled the Google sign-in flow.
  Future<UserCredential?> signInWithGoogle() async {
    try {
      // Authenticate with Google
      final googleUser = await GoogleSignIn.instance.authenticate();

      // Get the ID token for Firebase Auth
      final idToken = googleUser.authentication.idToken;

      final credential = GoogleAuthProvider.credential(
        idToken: idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);

      // Sync to RevenueCat
      if (userCredential.user != null) {
        await RevenueCatService().logIn(userCredential.user!.uid);
        if (userCredential.user!.email != null) {
          await RevenueCatService().setEmail(userCredential.user!.email!);
        }
      }

      // Persist login state for silent sign-in on next launch
      await setLoggedIn(true);

      return userCredential;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return null; // User cancelled
      }
      debugPrint('❌ Google sign in failed: $e');
      rethrow;
    } on FirebaseAuthException catch (e) {
      debugPrint('❌ Google sign in Firebase error: ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('❌ Google sign in error: $e');
      rethrow;
    }
  }

  /// Sign in with Apple (works for both login and sign-up).
  ///
  /// Uses Firebase's native Apple provider, which presents the system
  /// Sign in with Apple sheet on iOS. Returns the [UserCredential] on
  /// success, or `null` if the user cancelled.
  Future<UserCredential?> signInWithApple() async {
    try {
      final provider = AppleAuthProvider()
        ..addScope('email')
        ..addScope('name');

      final userCredential = await _auth.signInWithProvider(provider);

      // Sync to RevenueCat
      if (userCredential.user != null) {
        await RevenueCatService().logIn(userCredential.user!.uid);
        if (userCredential.user!.email != null) {
          await RevenueCatService().setEmail(userCredential.user!.email!);
        }
      }

      // Persist login state for silent sign-in on next launch
      await setLoggedIn(true);

      return userCredential;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'canceled' || e.code == 'web-context-canceled') {
        return null; // User cancelled
      }
      debugPrint('❌ Apple sign in Firebase error: ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('❌ Apple sign in error: $e');
      rethrow;
    }
  }

  /// Re-authenticates an Apple user and revokes their Apple tokens.
  ///
  /// Apple requires apps that offer Sign in with Apple to revoke the
  /// user's tokens when they delete their account. Call this right before
  /// `user.delete()`.
  Future<void> reauthenticateAndRevokeApple(User user) async {
    final provider = AppleAuthProvider()..addScope('email');
    final credential = await user.reauthenticateWithProvider(provider);
    final authCode = credential.additionalUserInfo?.authorizationCode;
    if (authCode != null) {
      await _auth.revokeTokenWithAuthorizationCode(authCode);
    }
  }

  /// Sign out
  Future<void> signOut() async {
    try {
      // Clear all SharedPreferences so no stale data persists for the
      // next login session. Preserve only the fresh-install marker.
      final prefs = await SharedPreferences.getInstance();
      final hasLaunched = prefs.getBool('app_has_launched_before') ?? false;
      await prefs.clear();
      if (hasLaunched) {
        await prefs.setBool('app_has_launched_before', true);
      }

      await _auth.signOut();
      try {
        await RevenueCatService().logOut();
      } catch (_) {
        // RevenueCat logout is non-critical
      }
    } on FirebaseAuthException catch (e) {
      debugPrint('❌ Sign out failed: ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('❌ Sign out error: $e');
    }
  }

  /// Returns [url] if it can be shown as the user's avatar, otherwise null.
  ///
  /// Older builds offered preset avatars hotlinked from a stock-image site we
  /// are not licensed to ship. Accounts that saved one of those still carry
  /// the URL in photoURL, so it is ignored here and the UI falls back to the
  /// initials/icon avatar instead.
  static String? usablePhotoUrl(String? url) {
    if (url == null || url.trim().isEmpty) return null;
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    if (host == 'freepik.com' || host.endsWith('.freepik.com')) return null;
    return url;
  }

  /// Clears the user's photo URL so the initials avatar is shown.
  Future<void> clearUserPhoto() async {
    final user = _auth.currentUser;
    if (user == null) return;
    await user.updatePhotoURL(null);
    await user.reload();
  }

  /// Update user display name and/or photo URL
  Future<void> updateUserMetadata({
    String? displayName,
    String? avatarUrl,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      if (displayName != null) await user.updateDisplayName(displayName);
      if (avatarUrl != null) await user.updatePhotoURL(avatarUrl);
      await user.reload();

      debugPrint('✅ User metadata updated');
    } on FirebaseAuthException catch (e) {
      debugPrint('❌ Update user metadata failed: ${e.message}');
      rethrow;
    }
  }
}
