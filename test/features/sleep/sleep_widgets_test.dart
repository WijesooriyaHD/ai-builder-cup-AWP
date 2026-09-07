import 'package:aiwellnesspal/features/sleep/domain/sleep_models.dart';
import 'package:aiwellnesspal/features/sleep/presentation/widgets/sleep_cards.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

SleepSession _demo() => SleepSession(
      id: 't',
      date: DateTime(2026, 8, 31),
      bedtime: DateTime(2026, 8, 30, 23),
      wakeTime: DateTime(2026, 8, 31, 7),
      stages: const [
        SleepStage(type: SleepStageType.awake, minutes: 18),
        SleepStage(type: SleepStageType.rem, minutes: 102),
        SleepStage(type: SleepStageType.core, minutes: 291),
        SleepStage(type: SleepStageType.deep, minutes: 69), // total asleep 462 = 7h42m
      ],
    );

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('SleepScoreCard shows duration + score + band', (tester) async {
    await tester.pumpWidget(_wrap(SleepScoreCard(
      greeting: 'Good morning 🌙',
      session: _demo(),
      score: const SleepScore(86),
    )));
    expect(find.text('7h 42m'), findsOneWidget);
    expect(find.text('86'), findsOneWidget);
    expect(find.textContaining('Great'), findsOneWidget);
  });

  testWidgets('SleepStagesCard lists all four stages', (tester) async {
    await tester.pumpWidget(_wrap(SleepStagesCard(session: _demo())));
    expect(find.text('Awake'), findsOneWidget);
    expect(find.text('REM'), findsOneWidget);
    expect(find.text('Core'), findsOneWidget);
    expect(find.text('Deep'), findsOneWidget);
  });

  testWidgets('AISleepInsightCard shows analyzing state', (tester) async {
    await tester.pumpWidget(
        _wrap(const AISleepInsightCard(isAnalyzing: true)));
    expect(find.textContaining('Analyzing your sleep'), findsOneWidget);
  });

  testWidgets('AISleepInsightCard shows error + retry', (tester) async {
    await tester.pumpWidget(_wrap(AISleepInsightCard(
      aiFailed: true,
      onRetry: () {},
    )));
    expect(find.textContaining("couldn't generate"), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('AISleepInsightCard renders a loaded insight', (tester) async {
    await tester.pumpWidget(_wrap(const AISleepInsightCard(
      insight: SleepInsight(
        summary: 'Your sleep improved by 24 minutes.',
        contributingFactors: ['Less caffeine may have helped.'],
        recommendation:
            SleepRecommendation(title: 'Dinner before 8:30 PM', detail: 'x'),
      ),
    )));
    expect(find.text('Your sleep improved by 24 minutes.'), findsOneWidget);
    expect(find.textContaining('Less caffeine'), findsOneWidget);
  });

  testWidgets('AIRecommendationCard add-to-routine fires callback',
      (tester) async {
    var tapped = false;
    await tester.pumpWidget(_wrap(AIRecommendationCard(
      recommendation:
          const SleepRecommendation(title: 'Dinner before 8:30 PM', detail: 'x'),
      onAddToRoutine: () => tapped = true,
    )));
    await tester.tap(find.text('Add to my routine'));
    expect(tapped, isTrue);
  });

  testWidgets('FoodSleepCard shows empty prompt with no dinner',
      (tester) async {
    await tester.pumpWidget(_wrap(const FoodSleepCard()));
    expect(find.textContaining('Log your meals'), findsOneWidget);
  });
}
