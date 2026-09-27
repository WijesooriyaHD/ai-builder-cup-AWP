import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/onesignal_service.dart';

/// Push permission prompt: asks once, after the user has signed in and
/// finished onboarding, so the system sheet appears in context rather than
/// over the sign-in screen on first launch (Guidelines 4.5.4 / 5.1.1(iv)).
/// This is the
/// fix for iOS where a server-assigned subscription ID is only assigned
/// *after* permission is granted — so waiting for the ID before showing the
/// prompt creates an unresolvable chicken-and-egg deadlock.
///
/// (The OneSignal "integration complete" developer-verification dialog was
/// removed: it showed SDK test copy to every user on every launch, which
/// App Review treats as an unfinished build — Guideline 2.1.)
class OneSignalVerificationGate extends StatefulWidget {
  const OneSignalVerificationGate({super.key, required this.child});

  final Widget child;

  @override
  State<OneSignalVerificationGate> createState() =>
      _OneSignalVerificationGateState();
}

class _OneSignalVerificationGateState extends State<OneSignalVerificationGate> {
  final OneSignalService _oneSignal = OneSignalService();

  static const String _promptedKey = 'onesignal_permission_prompted';

  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userDocSub;
  bool _prompting = false;

  @override
  void initState() {
    super.initState();
    // Wait for a signed-in user who has completed onboarding, then prompt
    // once. This is the sole trigger on iOS, where permission must come
    // FIRST (before a server-assigned subscription ID can exist).
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      _userDocSub?.cancel();
      _userDocSub = null;
      if (user == null) return;
      _userDocSub = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots()
          .listen((doc) {
        if (doc.data()?['onboarding_completed'] == true) {
          _userDocSub?.cancel();
          _userDocSub = null;
          _maybePromptPermission();
        }
      }, onError: (Object e) {
        debugPrint('OneSignalVerificationGate: user doc listen failed: $e');
      });
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _userDocSub?.cancel();
    super.dispose();
  }

  Future<void> _maybePromptPermission() async {
    if (!mounted || _prompting) return;
    _prompting = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_promptedKey) == true) return; // already asked
      await prefs.setBool(_promptedKey, true);
      // Short delay so the app is fully painted before the OS sheet appears.
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      await _oneSignal.requestPermission();
    } catch (e) {
      debugPrint('OneSignalVerificationGate: permission prompt failed: $e');
    } finally {
      _prompting = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
