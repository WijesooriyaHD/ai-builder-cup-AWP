import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:aiwellnesspal/screens/check_in_screen.dart';
import 'package:aiwellnesspal/screens/breathing_exercise_screen.dart';
import 'package:aiwellnesspal/widgets/daily_plan_card.dart';
import 'package:aiwellnesspal/models/check_in.dart';
import 'package:aiwellnesspal/models/daily_plan.dart';
import 'package:aiwellnesspal/models/wellness_action.dart';
import 'package:aiwellnesspal/models/wellness_enums.dart';
import 'package:aiwellnesspal/providers/check_in_state.dart';
import 'package:aiwellnesspal/providers/wellness_plan_state.dart';

// Minimal mock for CheckInState
class _MockCheckInState extends ChangeNotifier implements CheckInState {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  @override
  List<CheckIn> get recentCheckIns => [];

  @override
  CheckIn? get prefillValues => null;

  @override
  bool get hasCheckedInToday => false;

  @override
  CheckIn? get todaysCheckIn => null;

  @override
  bool get isSubmitting => false;

  @override
  bool get isPremium => false;
}

// Minimal mock for WellnessPlanState
class _MockWellnessPlanState extends ChangeNotifier
    implements WellnessPlanState {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  @override
  DailyPlan? get todaysPlan => null;

  @override
  bool get isGenerating => false;

  @override
  String? get generationError => null;

  @override
  List<DailyPlan> get recentPlans => [];

  @override
  bool get isFallbackBannerVisible => false;
}

void main() {
  group('Accessibility - Semantics verification', () {
    group('CheckInScreen - energy scale', () {
      Widget buildCheckInScreen() {
        return MultiProvider(
          providers: [
            ChangeNotifierProvider<CheckInState>(
              create: (_) => _MockCheckInState(),
            ),
          ],
          child: const MaterialApp(
            home: CheckInScreen(),
          ),
        );
      }

      testWidgets('energy scale buttons have Semantics widgets with labels',
          (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(buildCheckInScreen());
        await tester.pump();

        // Verify Semantics widgets exist for each energy level
        // Find Semantics widgets with the expected labels
        final semanticsWidgets = find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label != null &&
              widget.properties.label!.startsWith('Energy level'),
        );
        expect(semanticsWidgets, findsNWidgets(5));

        handle.dispose();
      });

      testWidgets('energy buttons include descriptive labels', (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(buildCheckInScreen());
        await tester.pump();

        // Check for specific labels
        final drainedButton = find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label ==
                  'Energy level 1: Completely Drained',
        );
        expect(drainedButton, findsOneWidget);

        final energizedButton = find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label ==
                  'Energy level 5: Fully Energized',
        );
        expect(energizedButton, findsOneWidget);

        handle.dispose();
      });
    });

    group('CheckInScreen - mood cards', () {
      Widget buildCheckInScreen() {
        return MultiProvider(
          providers: [
            ChangeNotifierProvider<CheckInState>(
              create: (_) => _MockCheckInState(),
            ),
          ],
          child: const MaterialApp(
            home: CheckInScreen(),
          ),
        );
      }

      testWidgets('mood cards have Semantics widgets', (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(buildCheckInScreen());
        await tester.pump();

        // Navigate to mood step: tap energy option first, then Next
        final energyOption = find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label ==
                  'Energy level 3: Moderate Energy',
        );
        await tester.tap(energyOption);
        await tester.pump();
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();

        // Verify mood cards have Semantics
        final moodCards = find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label != null &&
              widget.properties.label!.startsWith('Mood:'),
        );
        expect(moodCards, findsNWidgets(6));

        handle.dispose();
      });
    });

    group('CheckInScreen - recovery options', () {
      Widget buildCheckInScreen() {
        return MultiProvider(
          providers: [
            ChangeNotifierProvider<CheckInState>(
              create: (_) => _MockCheckInState(),
            ),
          ],
          child: const MaterialApp(
            home: CheckInScreen(),
          ),
        );
      }

      testWidgets('recovery options have Semantics widgets', (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(buildCheckInScreen());
        await tester.pump();

        // Navigate to recovery step: energy -> mood -> recovery
        final energyOption = find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label ==
                  'Energy level 3: Moderate Energy',
        );
        await tester.tap(energyOption);
        await tester.pump();
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();

        // Select mood
        final moodOption = find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label == 'Mood: Calm',
        );
        await tester.tap(moodOption);
        await tester.pump();
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();

        // Verify recovery options have Semantics
        final recoveryOptions = find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label != null &&
              widget.properties.label!.startsWith('Recovery status:'),
        );
        expect(recoveryOptions, findsNWidgets(4));

        handle.dispose();
      });
    });

    group('BreathingExerciseScreen', () {
      testWidgets('complete button has state-aware Semantics label',
          (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          const MaterialApp(home: BreathingExerciseScreen()),
        );
        await tester.pump();

        // Before 3 minutes: button should have disabled label
        final disabledButton = find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label != null &&
              widget.properties.label!.contains('Complete button disabled'),
        );
        expect(disabledButton, findsOneWidget);

        // Advance past 3 minutes
        await tester.pump(const Duration(seconds: 180));

        // After 3 minutes: button should have enabled label
        final enabledButton = find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label == 'Complete breathing exercise',
        );
        expect(enabledButton, findsOneWidget);

        handle.dispose();
      });

      testWidgets('breathing animation has Semantics label', (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          const MaterialApp(home: BreathingExerciseScreen()),
        );
        await tester.pump();

        // The breathing circle should have an accessible label
        final animationSemantics = find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label != null &&
              widget.properties.label!.startsWith('Breathing animation'),
        );
        expect(animationSemantics, findsOneWidget);

        handle.dispose();
      });
    });

    group('DailyPlanCard', () {
      DailyPlan createTestPlan({bool withCompletedAction = false}) {
        return DailyPlan(
          id: 'test-plan-1',
          date: DateTime(2024, 1, 15),
          todaysFocus: 'Gentle Recovery',
          actions: [
            WellnessAction(
              id: 'action-1',
              title: '15-Minute Morning Stretch',
              durationMinutes: 15,
              category: WellnessCategory.flexibility,
              intensityLevel: IntensityLevel.low,
              isCompleted: withCompletedAction,
            ),
            WellnessAction(
              id: 'action-2',
              title: '5-Minute Breathwork',
              durationMinutes: 5,
              category: WellnessCategory.stress,
              intensityLevel: IntensityLevel.low,
              isCompleted: false,
            ),
          ],
          totalTime: 20,
          energyTier: 2,
        );
      }

      Widget buildDailyPlanCard({bool withCompletedAction = false}) {
        return MultiProvider(
          providers: [
            ChangeNotifierProvider<WellnessPlanState>(
              create: (_) => _MockWellnessPlanState(),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: DailyPlanCard(
                plan: createTestPlan(
                    withCompletedAction: withCompletedAction),
              ),
            ),
          ),
        );
      }

      testWidgets('action cards have Semantics labels with title and status',
          (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(buildDailyPlanCard());
        await tester.pump();

        // Action cards should have descriptive semantics
        final actionSemantics = find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label != null &&
              widget.properties.label!.contains('15-Minute Morning Stretch'),
        );
        expect(actionSemantics, findsOneWidget);

        final breathworkSemantics = find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label != null &&
              widget.properties.label!.contains('5-Minute Breathwork'),
        );
        expect(breathworkSemantics, findsOneWidget);

        handle.dispose();
      });

      testWidgets('action checkboxes have accessible Semantics',
          (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(buildDailyPlanCard());
        await tester.pump();

        // Checkboxes should have semantics indicating their purpose
        final checkboxSemantics = find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label == 'Mark action as complete',
        );
        expect(checkboxSemantics, findsWidgets);

        handle.dispose();
      });

      testWidgets('completed action reflects state in Semantics',
          (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
            buildDailyPlanCard(withCompletedAction: true));
        await tester.pump();

        // The completed action's Semantics label should indicate "completed"
        final completedAction = find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label != null &&
              widget.properties.label!.contains('completed') &&
              widget.properties.label!
                  .contains('15-Minute Morning Stretch'),
        );
        expect(completedAction, findsOneWidget);

        // The completed action's checkbox should show "Action completed"
        final completedCheckbox = find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label == 'Action completed',
        );
        expect(completedCheckbox, findsOneWidget);

        handle.dispose();
      });
    });
  });
}
