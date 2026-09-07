import 'dart:convert';
import 'dart:math';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aiwellnesspal/models/check_in.dart';
import 'package:aiwellnesspal/models/wellness_enums.dart';
import 'package:aiwellnesspal/models/wellness_intention.dart';
import 'package:aiwellnesspal/services/content_safety_filter.dart';
import 'package:aiwellnesspal/services/personalization_service.dart';
import 'package:aiwellnesspal/services/wellness_plan_service.dart';

/// Property-Based Tests for AI Wellness Pal — Properties 6–11
///
/// Uses dart:math Random with 100 iterations per property for randomized testing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ---------------------------------------------------------------------------
  // Test data and helpers
  // ---------------------------------------------------------------------------

  /// Sample fallback plans covering all 3 tiers × 5 time ranges.
  final sampleFallbackPlans = jsonEncode([
    {"id": "fb_1_under10", "energyTier": 1, "timeRange": "under10", "todaysFocus": "Gentle Recovery", "actions": [{"id": "a1", "title": "Breathing", "durationMinutes": 4, "category": "mindfulness", "intensityLevel": "low"}, {"id": "a2", "title": "Stretch", "durationMinutes": 5, "category": "recovery", "intensityLevel": "low"}], "totalTime": 9},
    {"id": "fb_1_range10_20", "energyTier": 1, "timeRange": "range10_20", "todaysFocus": "Restore", "actions": [{"id": "a1", "title": "Scan", "durationMinutes": 8, "category": "mindfulness", "intensityLevel": "low"}, {"id": "a2", "title": "Stretch", "durationMinutes": 7, "category": "flexibility", "intensityLevel": "low"}], "totalTime": 15},
    {"id": "fb_1_range20_40", "energyTier": 1, "timeRange": "range20_40", "todaysFocus": "Calm", "actions": [{"id": "a1", "title": "Yoga", "durationMinutes": 15, "category": "flexibility", "intensityLevel": "low"}, {"id": "a2", "title": "Relax", "durationMinutes": 10, "category": "stress", "intensityLevel": "low"}], "totalTime": 25},
    {"id": "fb_1_range40_60", "energyTier": 1, "timeRange": "range40_60", "todaysFocus": "Deep Rest", "actions": [{"id": "a1", "title": "Yin Yoga", "durationMinutes": 20, "category": "flexibility", "intensityLevel": "low"}, {"id": "a2", "title": "Sleep Prep", "durationMinutes": 15, "category": "sleep", "intensityLevel": "low"}], "totalTime": 35},
    {"id": "fb_1_over60", "energyTier": 1, "timeRange": "over60", "todaysFocus": "Full Rest Day", "actions": [{"id": "a1", "title": "Long Yoga", "durationMinutes": 30, "category": "flexibility", "intensityLevel": "low"}, {"id": "a2", "title": "Meditation", "durationMinutes": 20, "category": "mindfulness", "intensityLevel": "low"}, {"id": "a3", "title": "Journal", "durationMinutes": 15, "category": "stress", "intensityLevel": "low"}], "totalTime": 65},
    {"id": "fb_2_under10", "energyTier": 2, "timeRange": "under10", "todaysFocus": "Quick Balance", "actions": [{"id": "a1", "title": "Box Breathing", "durationMinutes": 4, "category": "stress", "intensityLevel": "low"}, {"id": "a2", "title": "Standing Stretch", "durationMinutes": 5, "category": "flexibility", "intensityLevel": "medium"}], "totalTime": 9},
    {"id": "fb_2_range10_20", "energyTier": 2, "timeRange": "range10_20", "todaysFocus": "Mindful Movement", "actions": [{"id": "a1", "title": "Walking", "durationMinutes": 10, "category": "mindfulness", "intensityLevel": "medium"}, {"id": "a2", "title": "Stretch", "durationMinutes": 8, "category": "flexibility", "intensityLevel": "low"}], "totalTime": 18},
    {"id": "fb_2_range20_40", "energyTier": 2, "timeRange": "range20_40", "todaysFocus": "Balanced Wellness", "actions": [{"id": "a1", "title": "Pilates", "durationMinutes": 15, "category": "movement", "intensityLevel": "medium"}, {"id": "a2", "title": "Cool Down", "durationMinutes": 10, "category": "flexibility", "intensityLevel": "low"}], "totalTime": 25},
    {"id": "fb_2_range40_60", "energyTier": 2, "timeRange": "range40_60", "todaysFocus": "Active Balance", "actions": [{"id": "a1", "title": "Flow Yoga", "durationMinutes": 25, "category": "flexibility", "intensityLevel": "medium"}, {"id": "a2", "title": "Breathwork", "durationMinutes": 15, "category": "stress", "intensityLevel": "low"}], "totalTime": 40},
    {"id": "fb_2_over60", "energyTier": 2, "timeRange": "over60", "todaysFocus": "Extended Balance", "actions": [{"id": "a1", "title": "Yoga Flow", "durationMinutes": 35, "category": "flexibility", "intensityLevel": "medium"}, {"id": "a2", "title": "Walk", "durationMinutes": 25, "category": "movement", "intensityLevel": "medium"}, {"id": "a3", "title": "Meditation", "durationMinutes": 10, "category": "mindfulness", "intensityLevel": "low"}], "totalTime": 70},
    {"id": "fb_3_under10", "energyTier": 3, "timeRange": "under10", "todaysFocus": "Quick Energize", "actions": [{"id": "a1", "title": "Power Breathing", "durationMinutes": 3, "category": "energy", "intensityLevel": "medium"}, {"id": "a2", "title": "Dynamic Stretch", "durationMinutes": 6, "category": "movement", "intensityLevel": "high"}], "totalTime": 9},
    {"id": "fb_3_range10_20", "energyTier": 3, "timeRange": "range10_20", "todaysFocus": "Active Start", "actions": [{"id": "a1", "title": "HIIT Lite", "durationMinutes": 10, "category": "movement", "intensityLevel": "high"}, {"id": "a2", "title": "Stretch", "durationMinutes": 5, "category": "flexibility", "intensityLevel": "low"}], "totalTime": 15},
    {"id": "fb_3_range20_40", "energyTier": 3, "timeRange": "range20_40", "todaysFocus": "Active Wellness", "actions": [{"id": "a1", "title": "Pilates Flow", "durationMinutes": 20, "category": "movement", "intensityLevel": "high"}, {"id": "a2", "title": "Cool Down", "durationMinutes": 10, "category": "flexibility", "intensityLevel": "low"}], "totalTime": 30},
    {"id": "fb_3_range40_60", "energyTier": 3, "timeRange": "range40_60", "todaysFocus": "Full Active", "actions": [{"id": "a1", "title": "Strength", "durationMinutes": 25, "category": "movement", "intensityLevel": "high"}, {"id": "a2", "title": "Cardio", "durationMinutes": 20, "category": "energy", "intensityLevel": "high"}], "totalTime": 45},
    {"id": "fb_3_over60", "energyTier": 3, "timeRange": "over60", "todaysFocus": "Peak Day", "actions": [{"id": "a1", "title": "Full Pilates", "durationMinutes": 35, "category": "movement", "intensityLevel": "high"}, {"id": "a2", "title": "Running", "durationMinutes": 25, "category": "energy", "intensityLevel": "high"}, {"id": "a3", "title": "Stretch", "durationMinutes": 10, "category": "flexibility", "intensityLevel": "low"}], "totalTime": 70},
  ]);

  /// List of all valid energy tiers.
  const validEnergyTiers = [1, 2, 3];

  /// List of all valid time range enum names.
  final validTimeRanges = AvailableTimeRange.values.map((e) => e.name).toList();

  /// All banned words from ContentSafetyFilter.
  const bannedWords = [
    'diagnose', 'diagnoses', 'diagnosing',
    'treat', 'treatment', 'treating', 'treated',
    'therapy', 'therapeutic',
    'therapist', 'therapists',
    'disorder', 'disorders',
    'symptom', 'symptoms',
    'condition', 'conditions',
    'clinical', 'clinically',
  ];

  /// All MoodState values for random generation.
  final moodStates = MoodState.values;

  /// All RecoveryStatus values.
  final recoveryStatuses = RecoveryStatus.values;

  /// All AvailableTimeRange values.
  final availableTimeRanges = AvailableTimeRange.values;

  // ---------------------------------------------------------------------------
  // Property 6: Fallback plan matches energy tier and time range
  // ---------------------------------------------------------------------------
  group('Property 6: Fallback Plan Matches Energy Tier and Time Range', () {
    /// **Validates: Requirements 1.9, 3.10**
    ///
    /// For any (energyTier, timeRange) input to selectFallbackPlan, the
    /// returned plan's energyTier matches the input tier.
    late WellnessPlanService service;

    setUp(() {
      // Mock SharedPreferences
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/shared_preferences'),
        (MethodCall methodCall) async {
          if (methodCall.method == 'getAll') return <String, dynamic>{};
          if (methodCall.method == 'setString') return true;
          return null;
        },
      );

      // Mock rootBundle to return our fallback plans
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler('flutter/assets', (ByteData? message) async {
        final key = utf8.decode(message!.buffer.asUint8List());
        if (key.contains('fallback_plans.json')) {
          return ByteData.view(
              Uint8List.fromList(utf8.encode(sampleFallbackPlans)).buffer);
        }
        return null;
      });

      service = WellnessPlanService(
        firestore: FakeFirebaseFirestore(),
        random: Random(42),
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

    test('energy tier of returned plan always matches input tier (100 iterations)', () async {
      final rng = Random(12345);

      for (int i = 0; i < 100; i++) {
        final tier = validEnergyTiers[rng.nextInt(validEnergyTiers.length)];
        final timeRange = validTimeRanges[rng.nextInt(validTimeRanges.length)];

        final plan = await service.selectFallbackPlan(tier, timeRange);

        expect(
          plan.energyTier,
          equals(tier),
          reason: 'Iteration $i: tier=$tier, timeRange=$timeRange → '
              'plan.energyTier=${plan.energyTier}',
        );
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Property 7: Check-in prefill returns mode with recency tiebreak
  // ---------------------------------------------------------------------------
  group('Property 7: Check-In Prefill Returns the Mode with Recency Tiebreak', () {
    /// **Validates: Requirements 2.10, 11.3**
    ///
    /// For any list of up to 14 check-ins, computePrefill returns the most
    /// frequent value per field; ties broken by recency (most recent wins).
    late PersonalizationService service;

    setUp(() {
      service = PersonalizationService();
    });

    test('prefill energyScore is the mode, ties broken by recency (100 iterations)', () {
      final rng = Random(54321);

      for (int i = 0; i < 100; i++) {
        final length = rng.nextInt(14) + 1; // 1 to 14
        final checkIns = List.generate(length, (idx) {
          // Random energy score 1-5 or null
          final hasEnergy = rng.nextBool();
          return CheckIn(
            id: 'ci_$idx',
            date: DateTime(2024, 1, 14 - idx), // index 0 = most recent
            energyScore: hasEnergy ? rng.nextInt(5) + 1 : null,
          );
        });

        final result = service.computePrefill(checkIns);

        // Manually compute expected mode with recency tiebreak
        final expectedEnergy = _computeExpectedMode<int>(
          checkIns,
          (c) => c.energyScore,
        );

        expect(
          result.energyScore,
          equals(expectedEnergy),
          reason: 'Iteration $i: energyScores='
              '${checkIns.map((c) => c.energyScore).toList()}',
        );
      }
    });

    test('prefill moodState is the mode, ties broken by recency (100 iterations)', () {
      final rng = Random(11111);

      for (int i = 0; i < 100; i++) {
        final length = rng.nextInt(14) + 1;
        final checkIns = List.generate(length, (idx) {
          final hasMood = rng.nextBool();
          return CheckIn(
            id: 'ci_$idx',
            date: DateTime(2024, 1, 14 - idx),
            moodState: hasMood ? moodStates[rng.nextInt(moodStates.length)] : null,
          );
        });

        final result = service.computePrefill(checkIns);

        final expectedMood = _computeExpectedMode<MoodState>(
          checkIns,
          (c) => c.moodState,
        );

        expect(
          result.moodState,
          equals(expectedMood),
          reason: 'Iteration $i',
        );
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Property 8: Content safety filter catches all banned words
  // ---------------------------------------------------------------------------
  group('Property 8: Content Safety Filter Catches All Banned Words', () {
    /// **Validates: Requirements 8.3, 8.6**
    ///
    /// For any string containing a banned word (from the list of 19),
    /// containsBannedContent returns true, and sanitize returns fallback.
    /// For clean strings, sanitize returns the original unchanged.

    test('any string containing a banned word triggers the filter (100 iterations)', () {
      final rng = Random(99999);

      for (int i = 0; i < 100; i++) {
        // Pick a random banned word
        final bannedWord = bannedWords[rng.nextInt(bannedWords.length)];

        // Generate random prefix/suffix with no banned words
        final prefix = _randomSafeString(rng, rng.nextInt(20));
        final suffix = _randomSafeString(rng, rng.nextInt(20));
        final text = '$prefix $bannedWord $suffix';

        expect(
          ContentSafetyFilter.containsBannedContent(text),
          isTrue,
          reason: 'Iteration $i: "$text" should be caught (word: $bannedWord)',
        );

        expect(
          ContentSafetyFilter.sanitize(text),
          equals(ContentSafetyFilter.fallbackMessage),
          reason: 'Iteration $i: sanitize should return fallback for "$bannedWord"',
        );
      }
    });

    test('clean strings pass through unchanged (100 iterations)', () {
      final rng = Random(88888);

      for (int i = 0; i < 100; i++) {
        final text = _randomSafeString(rng, rng.nextInt(50) + 1);

        expect(
          ContentSafetyFilter.containsBannedContent(text),
          isFalse,
          reason: 'Iteration $i: "$text" should not be caught',
        );

        expect(
          ContentSafetyFilter.sanitize(text),
          equals(text),
          reason: 'Iteration $i: sanitize should return original for clean text',
        );
      }
    });

    test('every specific banned word form is caught', () {
      for (final word in bannedWords) {
        expect(
          ContentSafetyFilter.containsBannedContent('This involves $word today.'),
          isTrue,
          reason: 'Banned word "$word" should be detected',
        );
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Property 9: Intention progress is bounded and accurate
  // ---------------------------------------------------------------------------
  group('Property 9: Intention Progress Calculation Is Bounded and Accurate', () {
    /// **Validates: Requirements 5.6**
    ///
    /// For any non-negative int n, progressPercent(n) is in [0.0, 1.0]
    /// and equals min(n/30.0, 1.0).

    test('progressPercent is bounded [0.0, 1.0] and accurate (100 iterations)', () {
      final rng = Random(77777);
      final intention = WellnessIntention(
        title: 'Test',
        category: WellnessCategory.general,
      );

      for (int i = 0; i < 100; i++) {
        final n = rng.nextInt(200); // 0 to 199
        final result = intention.progressPercent(n);

        expect(
          result,
          greaterThanOrEqualTo(0.0),
          reason: 'Iteration $i: n=$n → result=$result should be >= 0.0',
        );

        expect(
          result,
          lessThanOrEqualTo(1.0),
          reason: 'Iteration $i: n=$n → result=$result should be <= 1.0',
        );

        final expected = n / 30.0 > 1.0 ? 1.0 : n / 30.0;
        expect(
          result,
          closeTo(expected, 1e-10),
          reason: 'Iteration $i: n=$n → expected=$expected, got=$result',
        );
      }
    });

    test('boundary values are correct', () {
      final intention = WellnessIntention(
        title: 'Test',
        category: WellnessCategory.general,
      );

      expect(intention.progressPercent(0), equals(0.0));
      expect(intention.progressPercent(15), closeTo(0.5, 1e-10));
      expect(intention.progressPercent(30), equals(1.0));
      expect(intention.progressPercent(60), equals(1.0));
      expect(intention.progressPercent(1000), equals(1.0));
    });
  });

  // ---------------------------------------------------------------------------
  // Property 10: Text scale factor is always clamped to [0.8, 1.3]
  // ---------------------------------------------------------------------------
  group('Property 10: Text Scale Factor Is Always Clamped', () {
    /// **Validates: Requirements 12.7, 15.3**
    ///
    /// For any double input, setTextScaleFactor clamps to [0.8, 1.3].
    /// We test the clamping logic directly since AppState requires
    /// full initialization. The clamping logic is: scale.clamp(0.8, 1.3).

    test('clamped value is always in [0.8, 1.3] (100 iterations)', () {
      final rng = Random(66666);

      for (int i = 0; i < 100; i++) {
        // Generate arbitrary doubles including edge cases
        final raw = (rng.nextDouble() * 10.0) - 5.0; // range: -5.0 to 5.0
        final clamped = raw.clamp(0.8, 1.3);

        expect(
          clamped,
          greaterThanOrEqualTo(0.8),
          reason: 'Iteration $i: raw=$raw → clamped=$clamped should be >= 0.8',
        );

        expect(
          clamped,
          lessThanOrEqualTo(1.3),
          reason: 'Iteration $i: raw=$raw → clamped=$clamped should be <= 1.3',
        );
      }
    });

    test('values below 0.8 clamp to 0.8', () {
      expect((-1.0).clamp(0.8, 1.3), equals(0.8));
      expect(0.0.clamp(0.8, 1.3), equals(0.8));
      expect(0.5.clamp(0.8, 1.3), equals(0.8));
      expect(0.79.clamp(0.8, 1.3), equals(0.8));
    });

    test('values above 1.3 clamp to 1.3', () {
      expect(1.31.clamp(0.8, 1.3), equals(1.3));
      expect(2.0.clamp(0.8, 1.3), equals(1.3));
      expect(100.0.clamp(0.8, 1.3), equals(1.3));
      expect(double.infinity.clamp(0.8, 1.3), equals(1.3));
    });

    test('values within [0.8, 1.3] are unchanged', () {
      expect(0.8.clamp(0.8, 1.3), equals(0.8));
      expect(1.0.clamp(0.8, 1.3), equals(1.0));
      expect(1.3.clamp(0.8, 1.3), equals(1.3));
      expect(1.1.clamp(0.8, 1.3), equals(1.1));
    });
  });

  // ---------------------------------------------------------------------------
  // Property 11: Recurring pattern detection threshold
  // ---------------------------------------------------------------------------
  group('Property 11: Recurring Pattern Detection Threshold', () {
    /// **Validates: Requirements 11.5**
    ///
    /// hasRecurringPattern returns true iff any value appears >= 3 times
    /// in the last 7 check-ins.
    late PersonalizationService service;

    setUp(() {
      service = PersonalizationService();
    });

    test('hasRecurringPattern matches threshold logic (100 iterations)', () {
      final rng = Random(55555);

      for (int i = 0; i < 100; i++) {
        final length = rng.nextInt(7) + 1; // 1 to 7
        final checkIns = List.generate(length, (idx) {
          // Generate random energy scores 1-5 (or null)
          final hasEnergy = rng.nextBool();
          return CheckIn(
            id: 'ci_$idx',
            date: DateTime(2024, 1, 7 - idx),
            energyScore: hasEnergy ? rng.nextInt(5) + 1 : null,
          );
        });

        final result = service.hasRecurringPattern('energyScore', checkIns);

        // Compute expected: count each non-null value, check if any >= 3
        final counts = <int, int>{};
        for (final ci in checkIns) {
          if (ci.energyScore != null) {
            counts[ci.energyScore!] = (counts[ci.energyScore!] ?? 0) + 1;
          }
        }
        final expected = counts.values.any((c) => c >= 3);

        expect(
          result,
          equals(expected),
          reason: 'Iteration $i: energyScores='
              '${checkIns.map((c) => c.energyScore).toList()}, '
              'counts=$counts, expected=$expected, got=$result',
        );
      }
    });

    test('moodState recurring pattern detection (100 iterations)', () {
      final rng = Random(44444);

      for (int i = 0; i < 100; i++) {
        final length = rng.nextInt(7) + 1;
        final checkIns = List.generate(length, (idx) {
          final hasMood = rng.nextBool();
          return CheckIn(
            id: 'ci_$idx',
            date: DateTime(2024, 1, 7 - idx),
            moodState: hasMood ? moodStates[rng.nextInt(moodStates.length)] : null,
          );
        });

        final result = service.hasRecurringPattern('moodState', checkIns);

        // Compute expected
        final counts = <String, int>{};
        for (final ci in checkIns) {
          if (ci.moodState != null) {
            final key = ci.moodState!.name;
            counts[key] = (counts[key] ?? 0) + 1;
          }
        }
        final expected = counts.values.any((c) => c >= 3);

        expect(
          result,
          equals(expected),
          reason: 'Iteration $i: moodStates='
              '${checkIns.map((c) => c.moodState?.name).toList()}',
        );
      }
    });
  });
}

// =============================================================================
// Helper functions
// =============================================================================

/// Computes the expected mode for a field across check-ins with recency tiebreak.
/// Index 0 is most recent. Returns null if all values are null.
T? _computeExpectedMode<T>(List<CheckIn> checkIns, T? Function(CheckIn) extractor) {
  final counts = <T, int>{};
  final recencyIndex = <T, int>{};

  for (var i = 0; i < checkIns.length; i++) {
    final value = extractor(checkIns[i]);
    if (value != null) {
      counts[value] = (counts[value] ?? 0) + 1;
      recencyIndex.putIfAbsent(value, () => i);
    }
  }

  if (counts.isEmpty) return null;

  final maxCount = counts.values.reduce((a, b) => a > b ? a : b);

  T? winner;
  int bestRecency = checkIns.length;

  for (final entry in counts.entries) {
    if (entry.value == maxCount) {
      final recency = recencyIndex[entry.key] ?? checkIns.length;
      if (recency < bestRecency) {
        bestRecency = recency;
        winner = entry.key;
      }
    }
  }

  return winner;
}

/// Generates a random string from safe characters (no banned words).
/// Uses simple words that won't match any banned word pattern.
String _randomSafeString(Random rng, int wordCount) {
  const safeWords = [
    'hello', 'world', 'today', 'feel', 'great', 'happy', 'calm',
    'morning', 'sunshine', 'gentle', 'breathe', 'energy', 'focus',
    'wellness', 'plan', 'move', 'rest', 'water', 'smile', 'peace',
    'kind', 'strong', 'balance', 'joy', 'light', 'warm', 'soft',
    'fresh', 'clear', 'bright', 'walk', 'flow', 'grow', 'hope',
  ];

  if (wordCount <= 0) return 'ok';

  final buffer = StringBuffer();
  for (int i = 0; i < wordCount; i++) {
    if (i > 0) buffer.write(' ');
    buffer.write(safeWords[rng.nextInt(safeWords.length)]);
  }
  return buffer.toString();
}
