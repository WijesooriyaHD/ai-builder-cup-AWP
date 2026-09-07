import 'package:flutter/material.dart';

/// A non-blocking, user-dismissible banner displayed when a Firestore
/// sign-in sync attempt fails.
///
/// Per requirement 14.4: "IF a Firestore sync attempt fails on sign-in,
/// THEN THE App SHALL display a non-blocking, user-dismissible error banner
/// informing the user that data may not be current; the banner SHALL clear
/// automatically upon the next successful Firestore sync."
///
/// This widget renders only when [isVisible] is `true`. The parent is
/// responsible for setting [isVisible] to `false` on successful sync
/// (auto-clear) or when the user taps dismiss ([onDismiss] callback).
///
/// The banner does not block interaction with underlying content — it is
/// designed to be placed in a [Stack] or similar overlay structure.
class SyncErrorBanner extends StatelessWidget {
  const SyncErrorBanner({
    super.key,
    required this.isVisible,
    required this.onDismiss,
  });

  /// Whether the sync error banner should be shown.
  final bool isVisible;

  /// Callback invoked when the user manually dismisses the banner.
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    if (!isVisible) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    return Material(
      elevation: 2,
      color: theme.colorScheme.secondaryContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(
                Icons.sync_problem,
                size: 20,
                color: theme.colorScheme.onSecondaryContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Data may not be current. Sync will retry automatically.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.close,
                  size: 18,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
                onPressed: onDismiss,
                tooltip: 'Dismiss',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
