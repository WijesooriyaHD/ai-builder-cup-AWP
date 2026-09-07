import 'dart:convert';
import 'dart:math';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aiwellnesspal/services/wellness_plan_service.dart';
import 'package:aiwellnesspal/models/daily_plan.dart';
import 'package:aiwellnesspal/models/wellness_action.dart';
import 'package:aiwellnesspal/models/wellness_enums.dart';

/// A seeded Random for deterministic test results.
class _SeededRandom implements Random {
  final int _seed;

  _SeededRandom([this._seed = 0]);

  @override
  int nextInt(int max) => _seed % max;

  @override
  double nextDouble() => 0.5;

  @override
  bool nextBool() => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Sample fallback plans JSON for testing
  final sampleFallbackPlans = jsonEncode([
    {
      "id": "fallback_1_under10",
      "energyTier": 1,
      "timeRange": "under10",
      "todaysFocus": "Gentle Recovery",
      "actions": [
        {"id": "a1", "title": "Deep Breathing", "durationMinutes": 4, "category": "mindfulness", "intensityLevel": "low"},
        {"id": "a2", "title": "Neck Release", "durationMinutes": 5, "category": "recovery", "intensityLevel": "low"}
      ],
      "totalTime": 9
    },
    {
      "id": "fallback_1_range10_20",
      "energyTier": 1,
      "timeRange": "range10_20",
      "todaysFocus": "Restore Energy",
      "actions": [
        {"id": "a1", "title": "Body Scan", "durationMinutes": 8, "category": "mindfulness", "intensityLevel": "low"},
        {"id": "a2", "title": "Seated Stretches", "durationMinutes": 7, "category": "flexibility", "intensityLevel": "low"}
      ],
      "totalTime": 15
    },
    {
      "id": "fallback_1_range20_40",
      "energyTier": 1,
      "timeRange": "range20_40",
      "todaysFocus": "Calm Restoration",
      "actions": [
        {"id": "a1", "title": "Restorative Yoga", "durationMinutes": 15, "category": "flexibility", "intensityLevel": "low"},
        {"id": "a2", "title": "Guided Relaxation", "durationMinutes": 10, "category": "stress", "intensityLevel": "low"}
      ],
      "totalTime": 25
    },
    {
      "id": "fallback_2_under10",
      "energyTier": 2,
      "timeRange": "under10",
      "todaysFocus": "Quick Balance Reset",
      "actions": [
        {"id": "a1", "title": "Box Breathing", "durationMinutes": 4, "category": "stress", "intensityLevel": "low"},
        {"id": "a2", "title": "Standing Stretch", "durationMinutes": 5, "category": "flexibility", "intensityLevel": "medium"}
      ],
      "totalTime": 9
    },
    {
      "id": "fallback_2_range10_20",
      "energyTier": 2,
      "timeRange": "range10_20",
      "todaysFocus": "Mindful Movement",
      "actions": [
        {"id": "a1", "title": "Walking Meditation", "durationMinutes": 10, "category": "mindfulness", "intensityLevel": "medium"},
        {"id": "a2", "title": "Upper Body Stretch", "durationMinutes": 8, "category": "flexibility", "intensityLevel": "low"}
      ],
      "totalTime": 18
    },
    {
      "id": "fallback_3_under10",
      "energyTier": 3,
      "timeRange": "under10",
      "todaysFocus": "Quick Energize",
      "actions": [
        {"id": "a1", "title": "Power Breathing", "durationMinutes": 3, "category": "energy", "intensityLevel": "medium"},
        {"id": "a2", "title": "Dynamic Stretches", "durationMinutes": 6, "category": "movement", "intensityLevel": "high"}
      ],
      "totalTime": 9
    },
    {
      "id": "fallback_3_range20_40",
      "energyTier": 3,
      "timeRange": "range20_40",
      "todaysFocus": "Active Wellness",
      "actions": [
        {"id": "a1", "title": "Pilates Flow", "durationMinutes": 20, "category": "movement", "intensityLevel": "high"},
        {"id": "a2", "title": "Cool Down Stretch", "durationMinutes": 10, "category": "flexibility", "intensityLevel": "low"}
      ],
      "totalTime": 30
    },
  ]);

  late WellnessPlanService service;
  late FakeFirebaseFirestore fakeFirestore;

  setUp(() {
    // Mock SharedPreferences
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/shared_preferences'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'getAll') {
          return <String, dynamic>{};
        }
        if (methodCall.method == 'setString') {
          return true;
        }
        return null;
      },
    );

    // Mock the rootBundle to return our sample fallback plans
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (ByteData? message) async {
      final key = utf8.decode(message!.buffer.asUint8List());
      if (key.contains('fallback_plans.json')) {
        return ByteData.view(
            Uint8List.fromList(utf8.encode(sampleFallbackPlans)).buffer);
      }
      return null;
    });

    fakeFirestore = FakeFirebaseFirestore();
    service = WellnessPlanService(
      firestore: fakeFirestore,
      random: _SeededRandom(0),
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/shared_preferences'),
      null,
    );
  });

  group('WellnessPlanService.selectFallbackPlan', () {
    test('returns a DailyPlan with isFallback set to true', () async {
      final plan = await service.selectFallbackPlan(1, 'under10');
      expect(plan.isFallback, isTrue);
    });

    test('selects plan matching exact energy tier', () async {
      final plan = await service.selectFallbackPlan(1, 'under10');
      expect(plan.energyTier, equals(1));
    });

    test('selects plan matching exact time range when available', () async {
      final plan = await service.selectFallbackPlan(2, 'under10');
      expect(plan.id, equals('fallback_2_under10'));
    });

    test('selects nearest time range when exact match is unavailable', () async {
      // Energy tier 3 has "under10" and "range20_40" but no "range10_20"
      // nearest to "range10_20" is "under10" (distance 1) and "range20_40" (distance 1)
      // With _SeededRandom(0), nextInt(2) returns 0, so picks first candidate
      final plan = await service.selectFallbackPlan(3, 'range10_20');
      expect(
        plan.id == 'fallback_3_under10' || plan.id == 'fallback_3_range20_40',
        isTrue,
      );
    });

    test('returned plan has actions and correct totalTime', () async {
      final plan = await service.selectFallbackPlan(1, 'range10_20');
      expect(plan.actions, isNotEmpty);
      expect(plan.totalTime, equals(15));
      expect(plan.todaysFocus, equals('Restore Energy'));
    });

    test('returned plan date is today', () async {
      final plan = await service.selectFallbackPlan(2, 'range10_20');
      final now = DateTime.now();
      expect(plan.date.year, equals(now.year));
      expect(plan.date.month, equals(now.month));
      expect(plan.date.day, equals(now.day));
    });

    test('returned plan has isCompleted set to false', () async {
      final plan = await service.selectFallbackPlan(1, 'under10');
      expect(plan.isCompleted, isFalse);
    });

    test('returns plan even when energy tier has only one option for time range', () async {
      final plan = await service.selectFallbackPlan(1, 'range20_40');
      expect(plan.id, equals('fallback_1_range20_40'));
      expect(plan.todaysFocus, equals('Calm Restoration'));
    });
  });

  group('WellnessPlanService Firestore operations', () {
    DailyPlan createTestPlan() {
      return DailyPlan(
        id: '2024-01-15',
        date: DateTime(2024, 1, 15),
        todaysFocus: 'Test Focus',
        actions: [
          WellnessAction(
            id: 'action1',
            title: 'Test Action',
            durationMinutes: 10,
            category: WellnessCategory.mindfulness,
            intensityLevel: IntensityLevel.low,
            isCompleted: false,
          ),
          WellnessAction(
            id: 'action2',
            title: 'Test Action 2',
            durationMinutes: 5,
            category: WellnessCategory.flexibility,
            intensityLevel: IntensityLevel.medium,
            isCompleted: false,
          ),
        ],
        totalTime: 15,
        isFallback: false,
        isCompleted: false,
        energyTier: 2,
      );
    }

    test('savePlan writes plan to Firestore under correct path', () async {
      final plan = createTestPlan();
      await service.savePlan('user123', plan);

      final doc = await fakeFirestore
          .collection('users')
          .doc('user123')
          .collection('daily_plans')
          .doc('2024-01-15')
          .get();

      expect(doc.exists, isTrue);
      expect(doc.data()!['todaysFocus'], equals('Test Focus'));
      expect(doc.data()!['totalTime'], equals(15));
    });

    test('loadPlanForDate retrieves saved plan', () async {
      final plan = createTestPlan();
      await service.savePlan('user123', plan);

      final loaded = await service.loadPlanForDate('user123', DateTime(2024, 1, 15));
      expect(loaded, isNotNull);
      expect(loaded!.id, equals('2024-01-15'));
      expect(loaded.todaysFocus, equals('Test Focus'));
      expect(loaded.actions.length, equals(2));
    });

    test('loadPlanForDate returns null for non-existent plan', () async {
      final loaded = await service.loadPlanForDate('user123', DateTime(2024, 1, 20));
      expect(loaded, isNull);
    });

    test('updateActionCompletion updates specific action', () async {
      final plan = createTestPlan();
      await service.savePlan('user123', plan);

      await service.updateActionCompletion('user123', '2024-01-15', 'action1', true);

      final doc = await fakeFirestore
          .collection('users')
          .doc('user123')
          .collection('daily_plans')
          .doc('2024-01-15')
          .get();

      final actions = doc.data()!['actions'] as List<dynamic>;
      final action1 = actions.firstWhere((a) => a['id'] == 'action1');
      final action2 = actions.firstWhere((a) => a['id'] == 'action2');

      expect(action1['isCompleted'], isTrue);
      expect(action2['isCompleted'], isFalse);
    });

    test('markPlanComplete sets isCompleted to true', () async {
      final plan = createTestPlan();
      await service.savePlan('user123', plan);

      await service.markPlanComplete('user123', '2024-01-15');

      final doc = await fakeFirestore
          .collection('users')
          .doc('user123')
          .collection('daily_plans')
          .doc('2024-01-15')
          .get();

      expect(doc.data()!['isCompleted'], isTrue);
    });

    test('loadRecentPlans returns plans within the date range', () async {
      // Create plans within the last 30 days
      final today = DateTime.now();
      for (int i = 0; i < 3; i++) {
        final date = today.subtract(Duration(days: i));
        final dateKey =
            '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        final plan = DailyPlan(
          id: dateKey,
          date: date,
          todaysFocus: 'Focus $i',
          actions: [
            WellnessAction(
              id: 'a$i',
              title: 'Action $i',
              durationMinutes: 10,
              category: WellnessCategory.mindfulness,
              intensityLevel: IntensityLevel.low,
            ),
          ],
          totalTime: 10,
          energyTier: 2,
        );
        await service.savePlan('user123', plan);
      }

      final plans = await service.loadRecentPlans('user123', days: 30);
      expect(plans.length, equals(3));
    });

    test('loadRecentPlans returns empty list when no plans exist', () async {
      final plans = await service.loadRecentPlans('user123', days: 30);
      expect(plans, isEmpty);
    });
  });
}
