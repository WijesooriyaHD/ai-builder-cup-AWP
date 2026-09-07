import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aiwellnesspal/services/connectivity_service.dart';

void main() {
  group('ConnectivityService', () {
    group('isOnline', () {
      test('returns true when connected via wifi', () async {
        final service = ConnectivityService.fromCallbacks(
          checkConnectivity: () async => [ConnectivityResult.wifi],
          connectivityChanges: const Stream.empty(),
        );

        expect(await service.isOnline, isTrue);
      });

      test('returns true when connected via mobile', () async {
        final service = ConnectivityService.fromCallbacks(
          checkConnectivity: () async => [ConnectivityResult.mobile],
          connectivityChanges: const Stream.empty(),
        );

        expect(await service.isOnline, isTrue);
      });

      test('returns true when connected via ethernet', () async {
        final service = ConnectivityService.fromCallbacks(
          checkConnectivity: () async => [ConnectivityResult.ethernet],
          connectivityChanges: const Stream.empty(),
        );

        expect(await service.isOnline, isTrue);
      });

      test('returns false when no connectivity', () async {
        final service = ConnectivityService.fromCallbacks(
          checkConnectivity: () async => [ConnectivityResult.none],
          connectivityChanges: const Stream.empty(),
        );

        expect(await service.isOnline, isFalse);
      });

      test('returns false when results are empty', () async {
        final service = ConnectivityService.fromCallbacks(
          checkConnectivity: () async => [],
          connectivityChanges: const Stream.empty(),
        );

        expect(await service.isOnline, isFalse);
      });

      test('returns true when multiple results include non-none', () async {
        final service = ConnectivityService.fromCallbacks(
          checkConnectivity: () async =>
              [ConnectivityResult.none, ConnectivityResult.wifi],
          connectivityChanges: const Stream.empty(),
        );

        expect(await service.isOnline, isTrue);
      });
    });

    group('onlineStream', () {
      test('emits true when connectivity is restored', () async {
        final controller =
            StreamController<List<ConnectivityResult>>.broadcast();
        final service = ConnectivityService.fromCallbacks(
          checkConnectivity: () async => [ConnectivityResult.none],
          connectivityChanges: controller.stream,
        );

        final emissions = <bool>[];
        final sub = service.onlineStream.listen(emissions.add);

        controller.add([ConnectivityResult.wifi]);
        await Future.delayed(Duration.zero);

        expect(emissions, [true]);

        await sub.cancel();
        await controller.close();
      });

      test('emits false when connectivity is lost', () async {
        final controller =
            StreamController<List<ConnectivityResult>>.broadcast();
        final service = ConnectivityService.fromCallbacks(
          checkConnectivity: () async => [ConnectivityResult.wifi],
          connectivityChanges: controller.stream,
        );

        final emissions = <bool>[];
        final sub = service.onlineStream.listen(emissions.add);

        controller.add([ConnectivityResult.none]);
        await Future.delayed(Duration.zero);

        expect(emissions, [false]);

        await sub.cancel();
        await controller.close();
      });

      test('de-duplicates consecutive identical boolean values', () async {
        final controller =
            StreamController<List<ConnectivityResult>>.broadcast();
        final service = ConnectivityService.fromCallbacks(
          checkConnectivity: () async => [],
          connectivityChanges: controller.stream,
        );

        final emissions = <bool>[];
        final sub = service.onlineStream.listen(emissions.add);

        // wifi (true), mobile (true — de-duped), none (false), none (false — de-duped)
        controller.add([ConnectivityResult.wifi]);
        await Future.delayed(Duration.zero);
        controller.add([ConnectivityResult.mobile]);
        await Future.delayed(Duration.zero);
        controller.add([ConnectivityResult.none]);
        await Future.delayed(Duration.zero);
        controller.add([ConnectivityResult.none]);
        await Future.delayed(Duration.zero);

        expect(emissions, [true, false]);

        await sub.cancel();
        await controller.close();
      });

      test('emits transitions correctly across online/offline cycles',
          () async {
        final controller =
            StreamController<List<ConnectivityResult>>.broadcast();
        final service = ConnectivityService.fromCallbacks(
          checkConnectivity: () async => [],
          connectivityChanges: controller.stream,
        );

        final emissions = <bool>[];
        final sub = service.onlineStream.listen(emissions.add);

        controller.add([ConnectivityResult.wifi]);
        await Future.delayed(Duration.zero);
        controller.add([ConnectivityResult.none]);
        await Future.delayed(Duration.zero);
        controller.add([ConnectivityResult.mobile]);
        await Future.delayed(Duration.zero);

        expect(emissions, [true, false, true]);

        await sub.cancel();
        await controller.close();
      });

      test('handles empty results list as offline', () async {
        final controller =
            StreamController<List<ConnectivityResult>>.broadcast();
        final service = ConnectivityService.fromCallbacks(
          checkConnectivity: () async => [],
          connectivityChanges: controller.stream,
        );

        final emissions = <bool>[];
        final sub = service.onlineStream.listen(emissions.add);

        controller.add([]);
        await Future.delayed(Duration.zero);

        expect(emissions, [false]);

        await sub.cancel();
        await controller.close();
      });
    });
  });
}
