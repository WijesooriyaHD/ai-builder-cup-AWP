import 'dart:async';
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart' show globalNavigatorKey;
import '../providers/app_state.dart';
import '../providers/check_in_state.dart';
import '../providers/wellness_plan_state.dart';
import '../services/auth_service.dart';
import '../services/onesignal_service.dart';
import '../services/revenue_cat_service.dart';
import 'wellnesspal_snackbar.dart';

/// The account-deletion flow, shared by every entry point that offers it.
///
/// Apple requires account deletion to be easy to find, so it is offered from
/// more than one place (Settings and the profile sheet). This lives here rather
/// than on one screen's State so both entry points run byte-for-byte the same
/// flow — a second copy would inevitably drift, and this is the one flow where
/// drifting means either failing review or leaving a user's data behind.
///
/// Callers may pass [onBusyStart]/[onBusyEnd] to drive their own progress
/// affordance; screens without one can simply omit them.
class AccountDeletion {
  AccountDeletion._();

  /// Warning block shown inside the delete-account dialogs when the user has
  /// an active subscription.
  ///
  /// Required by Apple's account-deletion guidance: deleting the account does
  /// NOT cancel an App Store / Play subscription, so the user must be told
  /// billing continues, asked to cancel first, and given a direct route to the
  /// store's subscription management page. Without this a Premium user can
  /// delete their account and keep being charged with no app left to cancel
  /// from.
  ///
  /// Returns an empty list when there is no subscription, so callers can
  /// spread it unconditionally and the dialogs stay clean for free users.
  static List<Widget> _subscriptionWarning(BuildContext context) {
    if (!context.read<AppState>().isPro) return const [];
    final theme = Theme.of(context);
    final store = Platform.isIOS ? 'the App Store' : 'Google Play';
    return [
      Container(
        margin: const EdgeInsets.only(top: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline_rounded,
                    color: Colors.orange, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'You have an active subscription',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Deleting your account does NOT cancel your subscription. '
              'Billing continues through $store until you cancel it. '
              'Please cancel your subscription first.',
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _openSubscriptionManagement(context),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('Manage Subscription'),
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  /// Opens the store's subscription-management page, falling back to telling
  /// the user where to go when the page can't be opened.
  static Future<void> _openSubscriptionManagement(BuildContext context) async {
    final opened = await RevenueCatService().manageSubscriptions();
    if (opened || !context.mounted) return;
    WellnessPalSnackBar.show(
      context,
      message: Platform.isIOS
          ? 'Open Settings \u2192 your name \u2192 Subscriptions to cancel.'
          : 'Open the Play Store \u2192 Payments & subscriptions to cancel.',
      icon: Icons.info_outline_rounded,
      duration: const Duration(seconds: 5),
    );
  }

  static Future<void> start(
    BuildContext context, {
    VoidCallback? onBusyStart,
    VoidCallback? onBusyEnd,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Check if user signed in with Google or Apple
    final isGoogleUser = user.providerData.any((p) => p.providerId == 'google.com');
    final isAppleUser = user.providerData.any((p) => p.providerId == 'apple.com');

    if (isGoogleUser || isAppleUser) {
      // Google/Apple user — simple confirmation, no password needed
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Delete Account',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'This action is permanent and cannot be undone. '
                    'All your data will be deleted, including your wellness plans, '
                    'check-in history, journal entries, intentions, and uploaded files.\n\n'
                    'You will be asked to verify your ${isAppleUser ? 'Apple ID' : 'Google account'}.',
                  ),
                  ..._subscriptionWarning(context),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                child: const Text(
                  'Delete My Account',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          );
        },
      );

      if (confirmed == true && context.mounted) {
        await _performAccountDeletionSocial(context,
            isApple: isAppleUser,
            onBusyStart: onBusyStart,
            onBusyEnd: onBusyEnd);
      }
    } else {
      // Email/password user — ask for password
      final passwordController = TextEditingController();
      final password = await showDialog<String?>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Delete Account',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'This action is permanent and cannot be undone. '
                    'All your data will be deleted, including your wellness plans, '
                    'check-in history, journal entries, intentions, and uploaded files.',
                  ),
                  ..._subscriptionWarning(context),
                  const SizedBox(height: 16),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Enter your password to confirm',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(null),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(passwordController.text),
                style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                child: const Text(
                  'Delete My Account',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          );
        },
      );

      if (password != null && password.isNotEmpty && context.mounted) {
        await _performAccountDeletionEmail(context, password,
            onBusyStart: onBusyStart, onBusyEnd: onBusyEnd);
      }
    }
  }

  static Future<void> _performAccountDeletionSocial(
    BuildContext context, {
    required bool isApple,
    VoidCallback? onBusyStart,
    VoidCallback? onBusyEnd,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    onBusyStart?.call();

    final uid = user.uid;
    final checkInState = Provider.of<CheckInState>(context, listen: false);
    final wellnessPlanState = Provider.of<WellnessPlanState>(context, listen: false);

    try {
      if (isApple) {
        // Re-authenticate with Apple and revoke Apple tokens (required by
        // App Store Review Guideline 5.1.1(v) for Sign in with Apple)
        await AuthService().reauthenticateAndRevokeApple(user);
      } else {
        // Re-authenticate with Google
        final googleUser = await GoogleSignIn.instance.authenticate();
        final idToken = googleUser.authentication.idToken;
        final credential = GoogleAuthProvider.credential(idToken: idToken);
        await user.reauthenticateWithCredential(credential);
      }

      // Delete Firestore data and Firebase Auth user
      await Future.any([
        () async {
          await _deleteAllUserData(uid);
          await user.delete();
        }(),
        Future.delayed(const Duration(seconds: 30)).then((_) {
          throw TimeoutException('Account deletion exceeded 30 seconds.');
        }),
      ]);

      // Detach third-party identities from the deleted account
      // (non-critical — never block deletion on these).
      try {
        OneSignalService().logout();
      } catch (e) {
        debugPrint('OneSignal logout after deletion failed: $e');
      }
      try {
        await RevenueCatService().logOut().timeout(const Duration(seconds: 5));
      } catch (e) {
        debugPrint('RevenueCat logOut after deletion failed: $e');
      }

      // Clean up local state
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      checkInState.reset();
      wellnessPlanState.reset();

      // Drop the caller's busy affordance before the confirmation, so a modal
      // progress overlay doesn't sit behind (or reappear under) the dialog.
      onBusyEnd?.call();

      // Confirm completion, as Apple's account-deletion guidance requires.
      //
      // Deliberately NOT guarded by `context.mounted`: it is already false.
      // Deleting the auth user makes AuthWrapper's authStateChanges stream
      // emit null, which swaps the whole authenticated subtree — including
      // whichever screen started this flow — for the sign-in gateway, before
      // execution reaches here. Guarding on the dead context silently skipped
      // the confirmation entirely, and a snackbar cannot work either: it
      // belongs to a ScaffoldMessenger that no longer exists. Both the dialog
      // and the stack cleanup therefore go through the root navigator, which
      // outlives that rebuild.
      await _showDeletedConfirmation();
      globalNavigatorKey.currentState?.popUntil((route) => route.isFirst);
    } on TimeoutException catch (_) {
      if (!context.mounted) return;
      onBusyEnd?.call();
      WellnessPalSnackBar.show(context,
        message: 'Deletion timed out. Please try again.',
        icon: Icons.timer_off_rounded, isError: true,
        duration: const Duration(seconds: 4));
    } catch (e) {
      if (!context.mounted) return;
      onBusyEnd?.call();
      WellnessPalSnackBar.show(context,
        message: 'Failed to delete account. Please try again.',
        icon: Icons.error_outline_rounded, isError: true,
        duration: const Duration(seconds: 4));
    }
  }

  static Future<void> _performAccountDeletionEmail(
    BuildContext context,
    String password, {
    VoidCallback? onBusyStart,
    VoidCallback? onBusyEnd,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      WellnessPalSnackBar.show(
        context,
        message: 'No user signed in. Please sign in and try again.',
        icon: Icons.error_outline_rounded,
        isError: true,
      );
      return;
    }

    onBusyStart?.call();

    final uid = user.uid;
    // Capture provider references before async operations that may unmount us
    final checkInState = Provider.of<CheckInState>(context, listen: false);
    final wellnessPlanState = Provider.of<WellnessPlanState>(context, listen: false);

    try {
      // Re-authenticate the user so user.delete() won't fail with
      // 'requires-recent-login'.
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: password,
      );
      await user.reauthenticateWithCredential(credential);
      // Delete Firestore data and Firebase Auth user together.
      // user.delete() must happen while the user is still authenticated.
      await Future.any([
        () async {
          await _deleteAllUserData(uid);

          // Delete the Firebase Auth user IMMEDIATELY after Firestore data,
          // while the auth session is still fully valid.
          // This triggers sign-out on the auth stream automatically.
          await user.delete();
        }(),
        Future.delayed(const Duration(seconds: 30)).then((_) {
          throw TimeoutException('Account deletion exceeded 30 seconds.');
        }),
      ]);

      // Detach third-party identities from the deleted account
      // (non-critical — never block deletion on these).
      try {
        OneSignalService().logout();
      } catch (e) {
        debugPrint('OneSignal logout after deletion failed: $e');
      }
      try {
        await RevenueCatService().logOut().timeout(const Duration(seconds: 5));
      } catch (e) {
        debugPrint('RevenueCat logOut after deletion failed: $e');
      }

      // Clear SharedPreferences and reset providers AFTER successful deletion.
      // user.delete() already triggered sign-out, but we still clean up
      // local state so the next user session starts fresh.
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      checkInState.reset();
      wellnessPlanState.reset();

      // Drop the caller's busy affordance before the confirmation, so a modal
      // progress overlay doesn't sit behind (or reappear under) the dialog.
      onBusyEnd?.call();

      // Confirm completion, as Apple's account-deletion guidance requires.
      //
      // Deliberately NOT guarded by `context.mounted`: it is already false.
      // Deleting the auth user makes AuthWrapper's authStateChanges stream
      // emit null, which swaps the whole authenticated subtree — including
      // whichever screen started this flow — for the sign-in gateway, before
      // execution reaches here. Guarding on the dead context silently skipped
      // the confirmation entirely, and a snackbar cannot work either: it
      // belongs to a ScaffoldMessenger that no longer exists. Both the dialog
      // and the stack cleanup therefore go through the root navigator, which
      // outlives that rebuild.
      await _showDeletedConfirmation();
      globalNavigatorKey.currentState?.popUntil((route) => route.isFirst);
    } on TimeoutException catch (_) {
      if (!context.mounted) return;
      onBusyEnd?.call();
      WellnessPalSnackBar.show(
        context,
        message: 'Deletion timed out. Please try again.',
        icon: Icons.timer_off_rounded,
        isError: true,
        duration: const Duration(seconds: 4),
      );
    } on FirebaseAuthException catch (e) {
      if (!context.mounted) return;
      onBusyEnd?.call();
      final message = e.code == 'wrong-password' || e.code == 'invalid-credential'
          ? 'Incorrect password. Please try again.'
          : 'Authentication failed. Please try again.';
      WellnessPalSnackBar.show(
        context,
        message: message,
        icon: Icons.error_outline_rounded,
        isError: true,
        duration: const Duration(seconds: 4),
      );
    } catch (e) {
      if (!context.mounted) return;
      onBusyEnd?.call();
      WellnessPalSnackBar.show(
        context,
        message: 'Failed to delete account. Please try again.',
        icon: Icons.error_outline_rounded,
        isError: true,
        duration: const Duration(seconds: 4),
      );
    }
  }

  /// Deletes all Firestore documents under `users/{uid}/` and
  /// all Firebase Storage files belonging to the user.
  /// Blocking "account deleted" confirmation, anchored to the ROOT navigator.
  ///
  /// Required by Apple's account-deletion guidance, and the only signal that
  /// distinguishes "it worked" from "it silently failed and logged me out".
  ///
  /// It deliberately takes no BuildContext. By the time this runs the calling
  /// screen has been unmounted by AuthWrapper reacting to the deleted auth
  /// user, so any context captured earlier is dead and showDialog on it
  /// throws. The root navigator outlives that rebuild.
  ///
  /// Not dismissible by tapping outside, so it cannot be missed.
  static Future<void> _showDeletedConfirmation() async {
    // Wait for the auth-driven rebuild to settle, so the dialog is mounted on
    // the new tree rather than the one being torn down.
    await WidgetsBinding.instance.endOfFrame;
    final context = globalNavigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.green, size: 28),
            SizedBox(width: 12),
            Expanded(child: Text('Account deleted')),
          ],
        ),
        content: const Text(
          'Your account and all of its data have been permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  static Future<void> _deleteAllUserData(String uid) async {
    final firestore = FirebaseFirestore.instance;
    final storage = FirebaseStorage.instance;

    // Define all subcollections to delete
    final subcollections = [
      'wellness_intentions',
      'daily_plans',
      'check_ins',
      'journal_entries',
      'travel_memories',
      'behavior_profile',
      'weekly_summaries',
      'ai_reports',
      'challenges',
      'hydration',
      'journal_discussions',
      'live_conversations',
      'meals',
      'sleep',
      'wellness_library_bookmarks',
      'wellness_library_completions',
      'wellness_studio_sessions',
    ];

    // Batch delete all subcollection documents
    WriteBatch batch = firestore.batch();
    int operationCount = 0;
    const batchLimit = 400; // Firestore batch max is 500; leave room

    for (final subcollection in subcollections) {
      final snapshot = await firestore
          .collection('users')
          .doc(uid)
          .collection(subcollection)
          .get();

      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
        operationCount++;

        // Commit in chunks if approaching batch limit
        if (operationCount >= batchLimit) {
          await batch.commit();
          batch = firestore.batch();
          operationCount = 0;
        }
      }
    }

    // Delete the user's root document
    batch.delete(firestore.collection('users').doc(uid));
    operationCount++;

    if (operationCount > 0) {
      await batch.commit();
    }

    // Delete all Firebase Storage files for the user
    for (final folder in ['travel-photos/$uid', 'meal-photos/$uid']) {
      try {
        final listResult = await storage.ref(folder).listAll();
        for (final item in listResult.items) {
          await item.delete();
        }
      } catch (e) {
        // Storage folder may not exist — that's fine
        debugPrint('Storage cleanup note ($folder): $e');
      }
    }
  }
}
