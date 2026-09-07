import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aiwellnesspal/services/connectivity_service.dart';
import 'package:aiwellnesspal/widgets/offline_indicator_banner.dart';

void main() {
  group('OfflineIndicatorBanner', () {
    testWidgets('shows offline message when device is offline', (tester) async {
      final controller =
          StreamController<List<ConnectivityResult>>.broadcast();
      final service = ConnectivityService.fromCallbacks(
        checkConnectivity: () async => [ConnectivityResult.none],
        connectivityChanges: controller.stream,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OfflineIndicatorBanner(
              connectivityService: service,
              hasCachedData: true,
            ),
          ),
        ),
      );

      // Allow FutureBuilder to resolve
      await tester.pumpAndSettle();

      expect(find.text('You are offline. Showing cached data.'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off), findsOneWidget);

      await controller.close();
    });

    testWidgets('shows "No data available offline yet." when no cached data',
        (tester) async {
      final controller =
          StreamController<List<ConnectivityResult>>.broadcast();
      final service = ConnectivityService.fromCallbacks(
        checkConnectivity: () async => [ConnectivityResult.none],
        connectivityChanges: controller.stream,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OfflineIndicatorBanner(
              connectivityService: service,
              hasCachedData: false,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('No data available offline yet.'), findsOneWidget);

      await controller.close();
    });

    testWidgets('hides when device is online', (tester) async {
      final controller =
          StreamController<List<ConnectivityResult>>.broadcast();
      final service = ConnectivityService.fromCallbacks(
        checkConnectivity: () async => [ConnectivityResult.wifi],
        connectivityChanges: controller.stream,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OfflineIndicatorBanner(
              connectivityService: service,
              hasCachedData: true,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('You are offline. Showing cached data.'), findsNothing);
      expect(find.text('No data available offline yet.'), findsNothing);

      await controller.close();
    });

    testWidgets('auto-dismisses when connectivity is restored', (tester) async {
      final controller =
          StreamController<List<ConnectivityResult>>.broadcast();
      final service = ConnectivityService.fromCallbacks(
        checkConnectivity: () async => [ConnectivityResult.none],
        connectivityChanges: controller.stream,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OfflineIndicatorBanner(
              connectivityService: service,
              hasCachedData: true,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Confirm banner is visible while offline
      expect(find.text('You are offline. Showing cached data.'), findsOneWidget);

      // Simulate connectivity restored
      controller.add([ConnectivityResult.wifi]);
      await tester.pumpAndSettle();

      // Banner should be gone
      expect(find.text('You are offline. Showing cached data.'), findsNothing);

      await controller.close();
    });

    testWidgets('reappears when connectivity is lost again', (tester) async {
      final controller =
          StreamController<List<ConnectivityResult>>.broadcast();
      final service = ConnectivityService.fromCallbacks(
        checkConnectivity: () async => [ConnectivityResult.wifi],
        connectivityChanges: controller.stream,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OfflineIndicatorBanner(
              connectivityService: service,
              hasCachedData: true,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Initially online, no banner
      expect(find.text('You are offline. Showing cached data.'), findsNothing);

      // Go offline
      controller.add([ConnectivityResult.none]);
      await tester.pumpAndSettle();

      expect(find.text('You are offline. Showing cached data.'), findsOneWidget);

      await controller.close();
    });
  });
}
