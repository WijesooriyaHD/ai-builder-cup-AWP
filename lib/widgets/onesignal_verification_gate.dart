import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/onesignal_service.dart';

/// Handles two distinct OneSignal flows:
///
/// 1. **First-launch permission prompt**: asks for push permission once,
///    after a short delay, when the user hasn't been prompted yet. This is
///    the fix for iOS where a server-assigned subscription ID is only assigned
///    *after* permission is granted — so waiting for the ID before showing the
///    prompt creates an unresolvable chicken-and-egg deadlock.
///
/// 2. **Integration-complete verification dialog**: once the device receives a
///    real, server-assigned subscription ID (non-empty, not `local-`), shows a
///    one-time developer-verification dialog confirming the SDK is wired up.
///    This follows the OneSignal integration guide requirement.
///
/// Both observers are retained for the lifetime of this [State] so they
/// are never garbage-collected by OneSignal's weak reference storage.
class OneSignalVerificationGate extends StatefulWidget {
  const OneSignalVerificationGate({super.key, required this.child});

  final Widget child;

  @override
  State<OneSignalVerificationGate> createState() =>
      _OneSignalVerificationGateState();
}

class _OneSignalVerificationGateState extends State<OneSignalVerificationGate> {
  final OneSignalService _oneSignal = OneSignalService();
  bool _verifyDialogShown = false;

  static const String _promptedKey = 'onesignal_permission_prompted';

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // 1. First-launch permission prompt.
      // We prompt once, ~2s after the app is ready, so the user has a moment
      // to see the app before the OS permission sheet appears. This is the
      // sole trigger on iOS where the permission must come FIRST (before a
      // server-assigned subscription ID can exist).
      await _maybePromptPermission();

      // 2. Integration-complete observer (retained in State).
      // Registers AND evaluates immediately in case the ID is already assigned
      // (e.g. on subsequent launches after permission was granted).
      _oneSignal.addPushSubscriptionObserver(_onSubscriptionChanged);
      _onSubscriptionChanged(_oneSignal.pushSubscriptionId);
    });
  }

  Future<void> _maybePromptPermission() async {
    if (!mounted) return;
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
    }
  }

  void _onSubscriptionChanged(String? id) {
    if (_verifyDialogShown || !mounted) return;
    if (!OneSignalService.isRegistered(id)) return;
    _verifyDialogShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showVerificationDialog();
    });
  }

  void _showVerificationDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Your OneSignal SDK integration is complete!'),
        content: const Text(
          'You can now send Push Notifications & In-App Messages through '
          'OneSignal. Tap below to enable push notifications.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _oneSignal.requestPermission();
            },
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
