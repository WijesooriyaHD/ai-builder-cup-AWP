import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aiwellnesspal/models/check_in.dart';
import 'package:aiwellnesspal/models/daily_plan.dart';
import 'package:aiwellnesspal/models/wellness_action.dart';
import 'package:aiwellnesspal/models/wellness_enums.dart';
import 'package:aiwellnesspal/models/wellness_intention.dart';
import 'package:aiwellnesspal/providers/wellness_plan_state.dart';
import 'package:aiwellnesspal/models/voice_command.dart';
import 'package:aiwellnesspal/services/ai_service.dart';
import 'package:aiwellnesspal/services/wellness_plan_service.dart';

// ---------------------------------------------------------------------------
// Fake AIService — overrides all methods so the super constructor
// FirebaseFunctions.instance is never reached.
// ---------------------------------------------------------------------------

class FakeAIService implements AIService {
  DailyPlan? planToReturn;
  bool shouldThrow = false;
  int generatePlanCallCount = 0;

  @override
  Future<DailyPlan?> generatePlan({
    required String userId,
    required CheckIn checkIn,
    required List<WellnessIntention> intentions,
    required List<DailyPlan> recentPlans,
  }) async {
    generatePlanCallCount++;
    if (shouldThrow) throw Exception('AI generation failed');
    return planToReturn;
  }

  @override
  Future<List<String>> generateReflectionPrompts({
    required String userId,
    CheckIn? checkIn,
    List<WellnessIntention>? intentions,
  }) async {
    return ['How are you feeling?', 'What do you need?', 'What feels good?'];
  }

  @override
  Future<String?> generateWellnessInsight({
    required String userId,
    DailyPlan? plan,
    String? summary,
  }) async {
    return null;
  }

  @override
  Future<String?> generateWeeklySummary({
    required String userId,
    required List weekEntries,
  }) async {
    return null;
  }

  @override
  Future<String?> generateReflectionInsight({
    required String userId,
    required String entryContent,
    String? entryTitle,
  }) async {
    return 'Test AI insight for reflection entry.';
  }

  @override
  Future<List<Map<String, dynamic>>> generateDreamTasks({
    required String dream,
    int days = 7,
  }) async {
    return [];
  }

  @override
  Future<String?> generateIntentionTitle(String rawInput) async {
    return null;
  }

  @override
  Future<VoiceCommand?> parseVoiceCommand(String speech) async {
    return null;
  }

  @override
  Future<String?> generateVoiceReply(String question) async {
    return null;
  }

  @override
  Future<List<Map<String, dynamic>>> generateStudioRecommendations({
    required CheckIn? checkIn,
    required List recentPlans,
    required List intentions,
    int count = 4,
  }) async {
    return [];
  }

  @override
  Future<String?> generateActivityGuidance({
    required String title,
    required String category,
    required int durationMinutes,
  }) async {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Test Helpers
// ---------------------------------------------------------------------------

DailyPlan _createTestPlan({
  String id = 'plan_1',
  DateTime? date,
  bool isFallback = false,
  bool isCompleted = false,
}) {
  final actions = [
    WellnessAction(
      id: 'action_1',
      title: '10-Minute Stretch',
      durationMinutes: 10,
      category: WellnessCategory.flexibility,
      intensityLevel: IntensityLevel.low,
    ),
    WellnessAction(
      id: 'action_2',
      title: '5-Minute Breathwork',
      durationMinutes: 5,
      category: WellnessCategory.stress,
      intensityLevel: IntensityLevel.low,
    ),
  ];

  return DailyPlan(
    id: id,
    date: date ?? DateTime.now(),
    todaysFocus: 'Gentle Recovery',
    actions: actions,
    totalTime: 15,
    isFallback: isFallback,
    isCompleted: isCompleted,
    energyTier: 2,
  );
}

CheckIn _createTestCheckIn({int energyScore = 3}) => CheckIn(
      id: 'checkin_1',
      date: DateTime.now(),
      energyScore: energyScore,
      moodState: MoodState.calm,
      recoveryStatus: RecoveryStatus.wellRested,
      availableTime: AvailableTimeRange.range20_40,
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAIService fakeAIService;
  late WellnessPlanService fakePlanService;
  late WellnessPlanState state;
  late FakeFirebaseFirestore fakeFirestore;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fakeAIService = FakeAIService();
    fakeFirestore = FakeFirebaseFirestore();
    fakePlanService = WellnessPlanService(firestore: fakeFirestore);

    state = WellnessPlanState(
      aiService: fakeAIService,
      planService: fakePlanService,
    );
  });

  group('WellnessPlanState initial state', () {
    test('todaysPlan is null initially', () {
      expect(state.todaysPlan, isNull);
    });

    test('isGenerating is false initially', () {
      expect(state.isGenerating, isFalse);
    });

    test('generationError is null initially', () {
      expect(state.generationError, isNull);
    });

    test('recentPlans is empty initially', () {
      expect(state.recentPlans, isEmpty);
    });

    test('isFallbackBannerVisible is false initially', () {
      expect(state.isFallbackBannerVisible, isFalse);
    });
  });

  group('WellnessPlanState.loadTodaysPlan', () {
    test('loads plan from Firestore when no cache exists (Req 3.13)', () async {
      final testPlan = _createTestPlan();
      await fakePlanService.savePlan('user1', testPlan);

      await state.loadTodaysPlan('user1');

      expect(state.todaysPlan, isNotNull);
      expect(state.todaysPlan!.id, 'plan_1');
      expect(state.todaysPlan!.todaysFocus, 'Gentle Recovery');
    });

    test('returns null when no plan exists for today', () async {
      await state.loadTodaysPlan('user1');

      expect(state.todaysPlan, isNull);
    });

    test('loads plan from local cache when available', () async {
      // Prime the cache by saving a plan first
      final testPlan = _createTestPlan();
      final planJson = jsonEncode(testPlan.toMap());
      SharedPreferences.setMockInitialValues({
        'wellness_daily_plan': planJson,
      });

      final freshState = WellnessPlanState(
        aiService: fakeAIService,
        planService: fakePlanService,
      );

      await freshState.loadTodaysPlan('user1');

      expect(freshState.todaysPlan, isNotNull);
      expect(freshState.todaysPlan!.id, 'plan_1');
    });

    test('does not trigger AI generation if plan exists (Req 3.13)', () async {
      final testPlan = _createTestPlan();
      await fakePlanService.savePlan('user1', testPlan);

      await state.loadTodaysPlan('user1');

      expect(fakeAIService.generatePlanCallCount, 0);
    });

    test('does not use cache from a previous day', () async {
      final yesterdayPlan = _createTestPlan(
        date: DateTime.now().subtract(const Duration(days: 1)),
      );
      SharedPreferences.setMockInitialValues({
        'wellness_daily_plan': jsonEncode(yesterdayPlan.toMap()),
      });

      final freshState = WellnessPlanState(
        aiService: fakeAIService,
        planService: fakePlanService,
      );

      await freshState.loadTodaysPlan('user1');

      // Yesterday's plan should not be used; Firestore has no plan for today
      expect(freshState.todaysPlan, isNull);
    });
  });

  group('WellnessPlanState.generatePlan', () {
    test('sets todaysPlan on successful AI generation (Req 3.1)', () async {
      fakeAIService.planToReturn = _createTestPlan();

      await state.generatePlan('user1', _createTestCheckIn());

      expect(state.todaysPlan, isNotNull);
      expect(state.todaysPlan!.id, 'plan_1');
      expect(state.todaysPlan!.todaysFocus, 'Gentle Recovery');
      expect(state.isFallbackBannerVisible, isFalse);
    });

    test('isGenerating is false after completion', () async {
      fakeAIService.planToReturn = _createTestPlan();

      await state.generatePlan('user1', _createTestCheckIn());

      expect(state.isGenerating, isFalse);
    });

    test('uses fallback plan when AI returns null (Req 3.10)', () async {
      fakeAIService.planToReturn = null;

      await state.generatePlan('user1', _createTestCheckIn());

      expect(state.todaysPlan, isNotNull);
      expect(state.todaysPlan!.isFallback, isTrue);
      expect(state.isFallbackBannerVisible, isTrue);
    });

    test('uses fallback plan when AI throws exception', () async {
      fakeAIService.shouldThrow = true;

      await state.generatePlan('user1', _createTestCheckIn());

      expect(state.todaysPlan, isNotNull);
      expect(state.todaysPlan!.isFallback, isTrue);
      expect(state.isFallbackBannerVisible, isTrue);
      expect(state.generationError, isNotNull);
    });

    test('saves generated plan to Firestore via planService', () async {
      fakeAIService.planToReturn = _createTestPlan();

      await state.generatePlan('user1', _createTestCheckIn());

      final loaded =
          await fakePlanService.loadPlanForDate('user1', DateTime.now());
      expect(loaded, isNotNull);
      expect(loaded!.id, 'plan_1');
    });
  });

  group('WellnessPlanState.markActionComplete', () {
    setUp(() async {
      fakeAIService.planToReturn = _createTestPlan();
      await state.generatePlan('user1', _createTestCheckIn());
    });

    test('optimistically updates local state (Req 3.6)', () async {
      await state.markActionComplete('plan_1', 'action_1', userId: 'user1');

      expect(state.todaysPlan!.actions[0].isCompleted, isTrue);
      expect(state.todaysPlan!.actions[1].isCompleted, isFalse);
    });

    test('updates cache after marking action complete', () async {
      await state.markActionComplete('plan_1', 'action_1', userId: 'user1');

      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString('wellness_daily_plan');
      expect(cachedJson, isNotNull);

      final cachedPlan =
          DailyPlan.fromMap(jsonDecode(cachedJson!) as Map<String, dynamic>);
      expect(cachedPlan.actions[0].isCompleted, isTrue);
    });

    test('does nothing when planId does not match', () async {
      await state.markActionComplete('wrong_plan', 'action_1', userId: 'user1');

      expect(state.todaysPlan!.actions[0].isCompleted, isFalse);
    });

    test('retains local update even if Firestore service returns without error', () async {
      // The updateActionCompletion looks up by planId which may not match
      // the date-keyed document. If no doc is found, service returns
      // gracefully (no sync queue needed). Local state remains updated.
      await state.markActionComplete('plan_1', 'action_1', userId: 'user1');

      // Optimistic update still holds
      expect(state.todaysPlan!.actions[0].isCompleted, isTrue);
    });
  });

  group('WellnessPlanState.markPlanComplete', () {
    setUp(() async {
      fakeAIService.planToReturn = _createTestPlan();
      await state.generatePlan('user1', _createTestCheckIn());
    });

    test('sets plan isCompleted to true (Req 3.8)', () async {
      await state.markPlanComplete('plan_1', userId: 'user1');

      expect(state.todaysPlan!.isCompleted, isTrue);
    });

    test('does nothing when planId does not match', () async {
      await state.markPlanComplete('wrong_plan', userId: 'user1');

      expect(state.todaysPlan!.isCompleted, isFalse);
    });

    test('updates cache with completion status', () async {
      await state.markPlanComplete('plan_1', userId: 'user1');

      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString('wellness_daily_plan');
      final cachedPlan =
          DailyPlan.fromMap(jsonDecode(cachedJson!) as Map<String, dynamic>);
      expect(cachedPlan.isCompleted, isTrue);
    });

    test('handles Firestore failure gracefully', () async {
      // markPlanComplete uses planId as doc key — which may not exist in
      // fake Firestore. The provider handles this gracefully and still
      // updates local state.
      await state.markPlanComplete('plan_1', userId: 'user1');

      // Local state should still reflect completion
      expect(state.todaysPlan!.isCompleted, isTrue);
    });
  });

  group('WellnessPlanState.useFallbackPlan', () {
    test('selects and sets a fallback plan (Req 3.10)', () async {
      await state.useFallbackPlan(2, 'range20_40', userId: 'user1');

      expect(state.todaysPlan, isNotNull);
      expect(state.todaysPlan!.isFallback, isTrue);
      expect(state.isFallbackBannerVisible, isTrue);
    });
  });

  group('WellnessPlanState.dismissFallbackBanner', () {
    test('sets isFallbackBannerVisible to false', () async {
      fakeAIService.planToReturn = null;
      await state.generatePlan('user1', _createTestCheckIn());
      expect(state.isFallbackBannerVisible, isTrue);

      state.dismissFallbackBanner();

      expect(state.isFallbackBannerVisible, isFalse);
    });
  });

  group('WellnessPlanState ChangeNotifier', () {
    test('notifies listeners on generatePlan', () async {
      fakeAIService.planToReturn = _createTestPlan();
      int notifyCount = 0;
      state.addListener(() => notifyCount++);

      await state.generatePlan('user1', _createTestCheckIn());

      // Notified at least for: isGenerating=true, then final result
      expect(notifyCount, greaterThanOrEqualTo(2));
    });

    test('notifies listeners on markActionComplete', () async {
      fakeAIService.planToReturn = _createTestPlan();
      await state.generatePlan('user1', _createTestCheckIn());

      int notifyCount = 0;
      state.addListener(() => notifyCount++);

      await state.markActionComplete('plan_1', 'action_1', userId: 'user1');

      expect(notifyCount, greaterThanOrEqualTo(1));
    });

    test('notifies listeners on dismissFallbackBanner', () {
      int notifyCount = 0;
      state.addListener(() => notifyCount++);

      state.dismissFallbackBanner();

      expect(notifyCount, 1);
    });
  });
}
