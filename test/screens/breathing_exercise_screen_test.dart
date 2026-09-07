import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aiwellnesspal/screens/breathing_exercise_screen.dart';

void main() {
  group('BreathingExerciseScreen', () {
    Widget buildTestWidget() {
      return const MaterialApp(
        home: BreathingExerciseScreen(),
      );
    }

    testWidgets('renders with correct initial UI elements', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      // Title in app bar
      expect(find.text('Breathing Exercise'), findsOneWidget);

      // Close button present
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);

      // Elapsed time starts at 00:00
      expect(find.text('00:00'), findsOneWidget);

      // Complete button is present but disabled
      expect(find.text('Complete (3 min required)'), findsOneWidget);

      // The Complete button should be disabled initially
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Complete (3 min required)'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('displays breathing phase label', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      // One of the phase labels should be visible
      final inhale = find.text('Inhale...');
      final hold = find.text('Hold...');
      final exhale = find.text('Exhale...');

      expect(
        inhale.evaluate().isNotEmpty ||
            hold.evaluate().isNotEmpty ||
            exhale.evaluate().isNotEmpty,
        isTrue,
      );
    });

    testWidgets('timer increments elapsed seconds', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      // Initially 00:00
      expect(find.text('00:00'), findsOneWidget);

      // Advance 5 seconds
      await tester.pump(const Duration(seconds: 5));

      // Should now show 00:05
      expect(find.text('00:05'), findsOneWidget);
    });

    testWidgets('Complete button remains disabled before 3 minutes',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      // Advance 2 minutes and 59 seconds (just under 3 min)
      await tester.pump(const Duration(seconds: 179));

      // Button should still be disabled
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Complete (3 min required)'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('Complete button becomes enabled after 3 minutes',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      // Advance 3 minutes (180 seconds)
      await tester.pump(const Duration(seconds: 180));

      // Button text changes and becomes enabled
      expect(find.text('Complete'), findsOneWidget);
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Complete'),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('shows remaining time display before 3 minutes',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      // Should show remaining time
      expect(find.text('03:00 remaining'), findsOneWidget);

      // Advance 30 seconds
      await tester.pump(const Duration(seconds: 30));
      expect(find.text('02:30 remaining'), findsOneWidget);
    });

    testWidgets('elapsed time display shows correct format', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      // Advance to 1 minute 15 seconds
      await tester.pump(const Duration(seconds: 75));
      expect(find.text('01:15'), findsOneWidget);
    });

    testWidgets('tapping Complete after 3 minutes pops with true',
        (tester) async {
      bool? popResult;

      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              popResult = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => const BreathingExerciseScreen(),
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ));

      // Navigate to breathing screen
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300)); // route transition

      // Advance 3 minutes
      await tester.pump(const Duration(seconds: 180));

      // Tap Complete button
      await tester.tap(find.text('Complete'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300)); // route pop transition

      expect(popResult, true);
    });

    testWidgets('tapping close button pops with false', (tester) async {
      bool? popResult;

      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              popResult = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => const BreathingExerciseScreen(),
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ));

      // Navigate to breathing screen
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300)); // route transition

      // Tap close button
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300)); // route pop transition

      expect(popResult, false);
    });

    test('minimumDurationSeconds constant is 180 (3 minutes)', () {
      expect(BreathingExerciseScreen.minimumDurationSeconds, 180);
    });

    test('phaseDurationSeconds constant is 4 seconds per phase', () {
      expect(BreathingExerciseScreen.phaseDurationSeconds, 4);
    });
  });
}
