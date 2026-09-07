import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aiwellnesspal/widgets/ai_wellness_insight_card.dart';

void main() {
  Widget buildTestWidget({
    String? aiInsight,
    bool isPro = true,
    bool insightsEnabled = true,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: AIWellnessInsightCard(
          aiInsight: aiInsight,
          isPro: isPro,
          insightsEnabled: insightsEnabled,
        ),
      ),
    );
  }

  group('AIWellnessInsightCard', () {
    testWidgets('displays insight text when Premium, enabled, and insight is non-null',
        (tester) async {
      const insight = 'Based on your moderate energy and calm mood, gentle movement will support your flexibility goal today.';

      await tester.pumpWidget(buildTestWidget(aiInsight: insight));
      await tester.pumpAndSettle();

      expect(find.text(insight), findsOneWidget);
      expect(find.text('AI Wellness Insight'), findsOneWidget);
    });

    testWidgets('renders SizedBox.shrink when user is not Premium',
        (tester) async {
      const insight = 'Some insight text here.';

      await tester.pumpWidget(buildTestWidget(
        aiInsight: insight,
        isPro: false,
      ));
      await tester.pumpAndSettle();

      expect(find.text(insight), findsNothing);
      expect(find.text('AI Wellness Insight'), findsNothing);
      // SizedBox.shrink has zero size
      expect(find.byType(SizedBox), findsOneWidget);
    });

    testWidgets('renders SizedBox.shrink when insights are disabled',
        (tester) async {
      const insight = 'Some insight text here.';

      await tester.pumpWidget(buildTestWidget(
        aiInsight: insight,
        insightsEnabled: false,
      ));
      await tester.pumpAndSettle();

      expect(find.text(insight), findsNothing);
      expect(find.text('AI Wellness Insight'), findsNothing);
    });

    testWidgets('renders SizedBox.shrink when aiInsight is null',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(aiInsight: null));
      await tester.pumpAndSettle();

      expect(find.text('AI Wellness Insight'), findsNothing);
    });

    testWidgets('renders SizedBox.shrink when aiInsight is empty string',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(aiInsight: ''));
      await tester.pumpAndSettle();

      expect(find.text('AI Wellness Insight'), findsNothing);
    });

    testWidgets('renders SizedBox.shrink when aiInsight is whitespace only',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(aiInsight: '   '));
      await tester.pumpAndSettle();

      expect(find.text('AI Wellness Insight'), findsNothing);
    });

    testWidgets('shows sparkle icon', (tester) async {
      const insight = 'Gentle stretching today.';

      await tester.pumpWidget(buildTestWidget(aiInsight: insight));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.auto_awesome_rounded), findsOneWidget);
    });
  });
}
