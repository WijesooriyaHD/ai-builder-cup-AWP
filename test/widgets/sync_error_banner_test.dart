import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aiwellnesspal/widgets/sync_error_banner.dart';

void main() {
  group('SyncErrorBanner', () {
    testWidgets('shows sync error message when isVisible is true',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SyncErrorBanner(
              isVisible: true,
              onDismiss: () {},
            ),
          ),
        ),
      );

      expect(
        find.text('Data may not be current. Sync will retry automatically.'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.sync_problem), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('hides when isVisible is false', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SyncErrorBanner(
              isVisible: false,
              onDismiss: () {},
            ),
          ),
        ),
      );

      expect(
        find.text('Data may not be current. Sync will retry automatically.'),
        findsNothing,
      );
    });

    testWidgets('calls onDismiss when close button is tapped', (tester) async {
      var dismissed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SyncErrorBanner(
              isVisible: true,
              onDismiss: () => dismissed = true,
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();

      expect(dismissed, isTrue);
    });

    testWidgets('does not block underlying content (is non-blocking)',
        (tester) async {
      var buttonTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(
                  bottom: 100,
                  left: 16,
                  child: ElevatedButton(
                    onPressed: () => buttonTapped = true,
                    child: const Text('Underlying Button'),
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SyncErrorBanner(
                    isVisible: true,
                    onDismiss: () {},
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      // The underlying button should still be tappable
      await tester.tap(find.text('Underlying Button'));
      await tester.pump();

      expect(buttonTapped, isTrue);
    });

    testWidgets('clears automatically when isVisible changes to false',
        (tester) async {
      // Simulate auto-clear on successful sync by toggling isVisible.
      final visibleNotifier = ValueNotifier<bool>(true);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: visibleNotifier,
              builder: (context, isVisible, _) {
                return SyncErrorBanner(
                  isVisible: isVisible,
                  onDismiss: () => visibleNotifier.value = false,
                );
              },
            ),
          ),
        ),
      );

      // Initially visible
      expect(
        find.text('Data may not be current. Sync will retry automatically.'),
        findsOneWidget,
      );

      // Simulate successful sync (parent sets isVisible to false)
      visibleNotifier.value = false;
      await tester.pump();

      expect(
        find.text('Data may not be current. Sync will retry automatically.'),
        findsNothing,
      );
    });
  });
}
