import 'package:flutter/material.dart';

import '../services/connectivity_service.dart';

/// A persistent banner shown when the device is offline.
///
/// Uses [ConnectivityService.onlineStream] via a [StreamBuilder] to
/// reactively show/hide itself. When offline and no cached data exists,
/// it displays "No data available offline yet." Otherwise it shows a
/// generic offline indicator message.
///
/// Auto-dismisses (removes itself from the widget tree) the moment
/// connectivity is restored.
class OfflineIndicatorBanner extends StatelessWidget {
  const OfflineIndicatorBanner({
    super.key,
    required this.connectivityService,
    this.hasCachedData = true,
  });

  /// The [ConnectivityService] instance to observe for connectivity changes.
  final ConnectivityService connectivityService;

  /// Whether there is cached plan/check-in data available for offline use.
  /// When `false`, the banner shows "No data available offline yet."
  final bool hasCachedData;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: connectivityService.onlineStream,
      initialData: null,
      builder: (context, snapshot) {
        // While we haven't received any stream event yet, check initial state.
        // We use a FutureBuilder internally for the initial check.
        if (!snapshot.hasData) {
          return _InitialConnectivityCheck(
            connectivityService: connectivityService,
            hasCachedData: hasCachedData,
          );
        }

        final isOnline = snapshot.data!;
        if (isOnline) {
          return const SizedBox.shrink();
        }

        return _OfflineBannerContent(hasCachedData: hasCachedData);
      },
    );
  }
}

/// Handles the initial connectivity check before the stream emits.
class _InitialConnectivityCheck extends StatelessWidget {
  const _InitialConnectivityCheck({
    required this.connectivityService,
    required this.hasCachedData,
  });

  final ConnectivityService connectivityService;
  final bool hasCachedData;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: connectivityService.isOnline,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final isOnline = snapshot.data!;
        if (isOnline) {
          return const SizedBox.shrink();
        }

        return _OfflineBannerContent(hasCachedData: hasCachedData);
      },
    );
  }
}

/// The visual content of the offline banner.
class _OfflineBannerContent extends StatelessWidget {
  const _OfflineBannerContent({required this.hasCachedData});

  final bool hasCachedData;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      elevation: 2,
      color: theme.colorScheme.errorContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(
                Icons.cloud_off,
                size: 20,
                color: theme.colorScheme.onErrorContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  hasCachedData
                      ? 'You are offline. Showing cached data.'
                      : 'No data available offline yet.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
