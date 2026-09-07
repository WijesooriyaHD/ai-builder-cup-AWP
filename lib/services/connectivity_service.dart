import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Wraps the `connectivity_plus` package to expose a simple online/offline API.
///
/// - [isOnline]: one-shot check of the current connectivity state.
/// - [onlineStream]: a broadcast stream that emits `true` when the device
///   transitions to an online state and `false` when it transitions to offline.
///
/// The service considers "online" to be any connectivity result that is not
/// [ConnectivityResult.none].
class ConnectivityService {
  final Future<List<ConnectivityResult>> Function() _checkConnectivity;
  final Stream<List<ConnectivityResult>> _connectivityChanges;

  /// Creates a [ConnectivityService] wrapping the provided [Connectivity]
  /// instance (defaults to the singleton).
  ConnectivityService({Connectivity? connectivity})
      : _checkConnectivity =
            (connectivity ?? Connectivity()).checkConnectivity,
        _connectivityChanges =
            (connectivity ?? Connectivity()).onConnectivityChanged;

  /// Creates a [ConnectivityService] from raw functions/streams for testing.
  ConnectivityService.fromCallbacks({
    required Future<List<ConnectivityResult>> Function() checkConnectivity,
    required Stream<List<ConnectivityResult>> connectivityChanges,
  })  : _checkConnectivity = checkConnectivity,
        _connectivityChanges = connectivityChanges;

  /// Returns `true` if the device currently has network connectivity.
  Future<bool> get isOnline async {
    final results = await _checkConnectivity();
    return _isConnected(results);
  }

  /// A broadcast stream that emits the current online status (`true`/`false`)
  /// whenever the device's connectivity state changes.
  ///
  /// Only emits when the boolean value actually changes (de-duplicated), so
  /// listeners won't be spammed when switching between Wi-Fi and cellular
  /// without losing connectivity.
  Stream<bool> get onlineStream {
    return _connectivityChanges
        .map(_isConnected)
        .distinct();
  }

  /// Determines if a list of connectivity results indicates the device is
  /// connected. A device is considered connected if the results list is
  /// non-empty and does not solely contain [ConnectivityResult.none].
  static bool _isConnected(List<ConnectivityResult> results) {
    if (results.isEmpty) return false;
    return results.any((r) => r != ConnectivityResult.none);
  }
}
