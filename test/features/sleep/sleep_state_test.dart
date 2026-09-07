import 'package:aiwellnesspal/features/sleep/data/demo_sleep_data_provider.dart';
import 'package:aiwellnesspal/features/sleep/data/sleep_factors_analyzer.dart';
import 'package:aiwellnesspal/features/sleep/domain/sleep_ai_service.dart';
import 'package:aiwellnesspal/features/sleep/domain/sleep_models.dart';
import 'package:aiwellnesspal/features/sleep/presentation/sleep_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A fake AI service so tests never touch Firebase/network.
class _FakeSleepAI implements SleepAIService {
  final bool fail;
  const _FakeSleepAI({this.fail = false});

  @override
  Future<SleepInsight> analyze(SleepAnalysisRequest request) async {
    if (fail) throw Exception('ai down');
    return const SleepInsight(
      summary: 'You slept well.',
      contributingFactors: ['Your hydration looked good.'],
      recommendation:
          SleepRecommendation(title: 'Consistent bedtime', detail: 'Keep it steady.'),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('DemoSleepDataProvider', () {
    const provider = DemoSleepDataProvider();

    test('returns a stable session for a past date', () async {
      final date = DateTime(2026, 8, 20);
      final a = await provider.getSession(date);
      final b = await provider.getSession(date);
      expect(a, isNotNull);
      expect(a!.totalSleepMinutes, b!.totalSleepMinutes);
      expect(a.stages.length, 4);
    });

    test('returns null for a future date', () async {
      final future = DateTime.now().add(const Duration(days: 5));
      expect(await provider.getSession(future), isNull);
    });

    test('recent sessions returns the requested count', () async {
      final list = await provider.getRecentSessions(days: 7);
      expect(list.length, 7);
    });
  });

  group('SleepState', () {
    test('loads a session and computes a score + factors', () async {
      final state = SleepState(
        provider: const DemoSleepDataProvider(),
        aiService: const _FakeSleepAI(),
      );
      state.setFactorInputs(const SleepFactorInputs(
        hydrationMl: 2400,
        exerciseMinutes: 42,
      ));
      // Select a fixed past date for determinism.
      await state.selectDate(DateTime(2026, 8, 20));
      expect(state.status, SleepStatus.loaded);
      expect(state.session, isNotNull);
      expect(state.score, isNotNull);
      expect(state.factors, isNotEmpty);
      expect(state.insight, isNotNull);
      expect(state.insight!.recommendation.title, isNotEmpty);
    });

    test('AI failure sets aiFailed but keeps the dashboard loaded', () async {
      final state = SleepState(
        provider: const DemoSleepDataProvider(),
        aiService: const _FakeSleepAI(fail: true),
      );
      await state.selectDate(DateTime(2026, 8, 20));
      expect(state.status, SleepStatus.loaded);
      expect(state.aiFailed, isTrue);
      expect(state.session, isNotNull); // dashboard still works
    });

    test('cannot navigate to a future day', () async {
      final state = SleepState(
        provider: const DemoSleepDataProvider(),
        aiService: const _FakeSleepAI(),
      );
      await state.selectDate(DateTime.now());
      expect(state.canGoNext, isFalse);
    });
  });
}
