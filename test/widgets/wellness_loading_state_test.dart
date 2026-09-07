import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aiwellnesspal/widgets/wellness_loading_state.dart';

void main() {
  group('WellnessLoadingState', () {
    testWidgets('displays the first phrase on initial render', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: WellnessLoadingState()),
        ),
      );

      expect(
        find.text(WellnessLoadingState.phrases[0]),
        findsOneWidget,
      );
    });

    testWidgets('contains at least 3 supportive phrases', (tester) async {
      expect(WellnessLoadingState.phrases.length, greaterThanOrEqualTo(3));
    });

    testWidgets('cycles to the next phrase after 3 seconds', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: WellnessLoadingState()),
        ),
      );

      // Verify first phrase is shown
      expect(find.text(WellnessLoadingState.phrases[0]), findsOneWidget);

      // Advance time by 3 seconds (the cycle duration)
      await tester.pump(const Duration(seconds: 3));
      // Allow the crossfade animation to complete
      await tester.pump(const Duration(milliseconds: 600));

      // Second phrase should now be displayed
      expect(find.text(WellnessLoadingState.phrases[1]), findsOneWidget);
    });

    testWidgets('wraps around to the first phrase after cycling through all',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: WellnessLoadingState()),
        ),
      );

      // Cycle through all phrases
      final phraseCount = WellnessLoadingState.phrases.length;
      for (int i = 0; i < phraseCount; i++) {
        await tester.pump(const Duration(seconds: 3));
        await tester.pump(const Duration(milliseconds: 600));
      }

      // Should wrap back to the first phrase
      expect(find.text(WellnessLoadingState.phrases[0]), findsOneWidget);
    });

    testWidgets('fills its parent container', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: WellnessLoadingState()),
        ),
      );

      final container = tester.widget<Container>(find.byType(Container).first);
      expect(container.constraints?.maxWidth, double.infinity);
      expect(container.constraints?.maxHeight, double.infinity);
    });

    testWidgets('does not contain a CircularProgressIndicator or LinearProgressIndicator',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: WellnessLoadingState()),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('uses AnimatedSwitcher for crossfade transitions',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: WellnessLoadingState()),
        ),
      );

      expect(find.byType(AnimatedSwitcher), findsOneWidget);
    });

    testWidgets('text is centered', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: WellnessLoadingState()),
        ),
      );

      final text = tester.widget<Text>(find.byType(Text));
      expect(text.textAlign, TextAlign.center);
    });

    testWidgets('cleans up timer on dispose without errors', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: WellnessLoadingState()),
        ),
      );

      // Dispose the widget by replacing it
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SizedBox()),
        ),
      );

      // No errors should occur after disposal
      expect(tester.takeException(), isNull);
    });
  });
}
