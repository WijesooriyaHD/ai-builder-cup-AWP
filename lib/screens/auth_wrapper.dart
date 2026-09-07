import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../providers/app_state.dart';
import '../providers/wellness_plan_state.dart';
import 'auth_gateway_screen.dart';
import 'main_wrapper.dart';
import 'onboarding_screen.dart';

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  String? _lastUserId;
  String? _lastSyncedUserId;
  bool _wasOnboardingCompleted = false;
  bool _freshInstallCheckDone = false;

  static const String _hasLaunchedKey = 'app_has_launched_before';

  @override
  void initState() {
    super.initState();
    _checkFreshInstall();
  }

  /// On a fresh install, Firebase Auth may still have a persisted session
  /// from before the app was deleted (credentials stored in Keychain/Keystore).
  /// Sign out so the user starts from the auth screen — but only if our
  /// SharedPreferences flag indicates the user wasn't actively logged in.
  Future<void> _checkFreshInstall() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasLaunchedBefore = prefs.getBool(_hasLaunchedKey) ?? false;
      final wasLoggedIn = await AuthService.isLoggedIn();

      if (!hasLaunchedBefore) {
        if (!wasLoggedIn) {
          await AuthService().signOut();
        }
        await prefs.setBool(_hasLaunchedKey, true);
      }
    } catch (e) {
      debugPrint('❌ AuthWrapper._checkFreshInstall error: $e');
    }

    if (mounted) {
      setState(() {
        _freshInstallCheckDone = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Wait for fresh install check before showing anything
    if (!_freshInstallCheckDone) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return StreamBuilder<User?>(
      stream: AuthService().authStateChanges,
      builder: (context, snapshot) {
        final user = snapshot.data;
        final isLoggedIn = user != null;

        if (isLoggedIn) {
          if (_lastUserId != user.uid) {
            _lastUserId = user.uid;
            _wasOnboardingCompleted = false;
          }
          return _buildAuthenticatedView(user);
        } else {
          _lastUserId = null;
          _lastSyncedUserId = null;
          _wasOnboardingCompleted = false;
          return const AuthGatewayScreen();
        }
      },
    );
  }

  /// After authentication, checks the user's Firestore document for
  /// `onboarding_completed`. Routes to [OnboardingScreen] if false/missing,
  /// or [MainWrapper] (HomeScreen) if true.
  ///
  /// Requirements: 1.1, 1.5
  Widget _buildAuthenticatedView(User user) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        // Only show loading spinner on initial load when no data is available.
        // Once we have data, keep showing the routed screen even if the
        // stream briefly returns to waiting state (e.g. on widget rebuild).
        if (!snapshot.hasData &&
            snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        // Read onboarding_completed from the user document.
        final docSnapshot = snapshot.data;
        final data = docSnapshot?.data() as Map<String, dynamic>?;
        final onboardingCompleted = data?['onboarding_completed'] == true;

        if (onboardingCompleted) {
          _wasOnboardingCompleted = true;
          // Only sync data once per user session, and only after we've
          // confirmed the user has a valid Firestore document.
          if (_lastSyncedUserId != user.uid) {
            _lastSyncedUserId = user.uid;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final appState = context.read<AppState>();
              appState.syncAllData();
              // Always refresh Pro status on entering the authenticated view
              // with a fresh RevenueCat fetch, so the home badge / voice locks
              // match the true subscription state (independent of the
              // background sync path).
              appState.updateProStatus(forceRefresh: true);
              context.read<WellnessPlanState>().loadTodaysPlan(user.uid);
            });
          }
          return const MainWrapper();
        }

        // If the user previously had onboarding completed but now the doc
        // is missing or the flag is gone (account deleted mid-session),
        // show a loading spinner while the deletion flow completes.
        // The deletion flow calls user.delete() which triggers sign-out
        // on the auth stream automatically.
        if (_wasOnboardingCompleted) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        // Document doesn't exist or onboarding not completed (new user)
        return const OnboardingScreen();
      },
    );
  }
}
