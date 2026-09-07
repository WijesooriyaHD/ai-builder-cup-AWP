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
        await RevenueCatService().logIn(currentUser.uid);
        if (currentUser.email != null) {
          await RevenueCatService().setEmail(currentUser.email!);
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
