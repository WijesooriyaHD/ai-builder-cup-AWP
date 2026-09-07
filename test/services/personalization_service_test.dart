import 'package:flutter_test/flutter_test.dart';
import 'package:aiwellnesspal/services/personalization_service.dart';
import 'package:aiwellnesspal/models/check_in.dart';
import 'package:aiwellnesspal/models/user_behavior_profile.dart';
import 'package:aiwellnesspal/models/wellness_enums.dart';

void main() {
  late PersonalizationService service;

  setUp(() {
    // Use the service without Firestore for pure logic tests
    service = PersonalizationService();
  });

  group('PersonalizationService.computeTier', () {
    test('returns standard for 1-13 check-ins regardless of premium', () {
      expect(service.computeTier(1, false), PersonalizationTier.standard);
      expect(service.computeTier(1, true), PersonalizationTier.standard);
      expect(service.computeTier(13, false), PersonalizationTier.standard);
      expect(service.computeTier(13, true), PersonalizationTier.standard);
    });

    test('returns prefill for 14-27 check-ins with premium', () {
      expect(service.computeTier(14, true), PersonalizationTier.prefill);
      expect(service.computeTier(20, true), PersonalizationTier.prefill);
      expect(service.computeTier(27, true), PersonalizationTier.prefill);
    });

    test('returns standard for 14-27 check-ins without premium', () {
      expect(service.computeTier(14, false), PersonalizationTier.standard);
      expect(service.computeTier(20, false), PersonalizationTier.standard);
      expect(service.computeTier(27, false), PersonalizationTier.standard);
    });

    test('returns proactive for 28+ check-ins with premium', () {
      expect(service.computeTier(28, true), PersonalizationTier.proactive);
      expect(service.computeTier(50, true), PersonalizationTier.proactive);
      expect(service.computeTier(100, true), PersonalizationTier.proactive);
    });

    test('returns standard for 28+ check-ins without premium', () {
      expect(service.computeTier(28, false), PersonalizationTier.standard);
      expect(service.computeTier(50, false), PersonalizationTier.standard);
      expect(service.computeTier(100, false), PersonalizationTier.standard);
    });

    test('handles zero check-ins', () {
      expect(service.computeTier(0, false), PersonalizationTier.standard);
      expect(service.computeTier(0, true), PersonalizationTier.standard);
    });
  });

  group('PersonalizationService.computePrefill', () {
    test('returns mode for each field', () {
      // energyScore: 3 appears 8 times, 4 appears 6 times → mode = 3
      // moodState: calm appears 9 times, stressed 5 → mode = calm
      final checkIns = List.generate(14, (i) {
        return CheckIn(
          id: 'id_$i',
          date: DateTime(2024, 1, 14 - i),
          energyScore: i < 8 ? 3 : 4,
          moodState: i < 9 ? MoodState.calm : MoodState.stressed,
          recoveryStatus: i < 10 ? RecoveryStatus.wellRested : RecoveryStatus.sore,
          availableTime:
              i < 7 ? AvailableTimeRange.range20_40 : AvailableTimeRange.range10_20,
        );
      });

      final result = service.computePrefill(checkIns);

      expect(result.energyScore, 3);
      expect(result.moodState, MoodState.calm);
      expect(result.recoveryStatus, RecoveryStatus.wellRested);
      expect(result.availableTime, AvailableTimeRange.range20_40);
    });

    test('tie broken by recency — most recent value wins', () {
      // 7 check-ins with energyScore=3, 7 with energyScore=4
      // Index 0 is most recent. Index 0 has energyScore=4.
      final checkIns = List.generate(14, (i) {
        return CheckIn(
          id: 'id_$i',
          date: DateTime(2024, 1, 14 - i),
          energyScore: i < 7 ? 4 : 3,
          moodState: MoodState.calm,
          recoveryStatus: RecoveryStatus.wellRested,
          availableTime: AvailableTimeRange.range20_40,
        );
      });

      final result = service.computePrefill(checkIns);

      // Both have count 7, but energyScore=4 appears at index 0 (most recent)
      expect(result.energyScore, 4);
    });

    test('handles all null/skipped fields gracefully', () {
      final checkIns = List.generate(14, (i) {
        return CheckIn(
          id: 'id_$i',
          date: DateTime(2024, 1, 14 - i),
          // All fields null (skipped)
        );
      });

      final result = service.computePrefill(checkIns);

      expect(result.energyScore, isNull);
      expect(result.moodState, isNull);
      expect(result.recoveryStatus, isNull);
      expect(result.availableTime, isNull);
    });

    test('handles mixed null and non-null values', () {
      final checkIns = List.generate(14, (i) {
        return CheckIn(
          id: 'id_$i',
          date: DateTime(2024, 1, 14 - i),
          energyScore: i < 5 ? null : 2,
          moodState: i % 3 == 0 ? MoodState.anxious : null,
        );
      });

      final result = service.computePrefill(checkIns);

      // energyScore: 2 appears 9 times, null doesn't count → mode = 2
      expect(result.energyScore, 2);
      // moodState: anxious appears for i=0,3,6,9,12 → 5 times, null not counted → mode = anxious
      expect(result.moodState, MoodState.anxious);
    });

    test('handles empty list', () {
      final result = service.computePrefill([]);

      expect(result.energyScore, isNull);
      expect(result.moodState, isNull);
      expect(result.recoveryStatus, isNull);
      expect(result.availableTime, isNull);
    });

    test('handles single check-in', () {
      final checkIns = [
        CheckIn(
          id: 'id_0',
          date: DateTime(2024, 1, 1),
          energyScore: 5,
          moodState: MoodState.energized,
          recoveryStatus: RecoveryStatus.wellRested,
          availableTime: AvailableTimeRange.over60,
        ),
      ];

      final result = service.computePrefill(checkIns);

      expect(result.energyScore, 5);
      expect(result.moodState, MoodState.energized);
      expect(result.recoveryStatus, RecoveryStatus.wellRested);
      expect(result.availableTime, AvailableTimeRange.over60);
    });
  });

  group('PersonalizationService.computeActionWeights', () {
    test('computes weight as completeCount / (completeCount + skipCount)', () {
      final profile = UserBehaviorProfile(
        userId: 'user1',
        actionCategoryCompleteCounts: {'flexibility': 8, 'stress': 5},
        actionCategorySkipCounts: {'flexibility': 2, 'stress': 5},
      );

      final weights = service.computeActionWeights(profile);

      expect(weights['flexibility'], closeTo(0.8, 0.001)); // 8/(8+2)
      expect(weights['stress'], closeTo(0.5, 0.001)); // 5/(5+5)
    });

    test('defaults to 1.0 when no data for a category', () {
      final profile = UserBehaviorProfile(
        userId: 'user1',
        actionCategoryCompleteCounts: {'flexibility': 0},
        actionCategorySkipCounts: {'flexibility': 0},
      );

      final weights = service.computeActionWeights(profile);

      expect(weights['flexibility'], 1.0);
    });

    test('handles category in only skip counts', () {
      final profile = UserBehaviorProfile(
        userId: 'user1',
        actionCategoryCompleteCounts: {},
        actionCategorySkipCounts: {'sleep': 5},
      );

      final weights = service.computeActionWeights(profile);

      // 0 / (0 + 5) = 0.0
      expect(weights['sleep'], closeTo(0.0, 0.001));
    });

    test('handles category in only complete counts', () {
      final profile = UserBehaviorProfile(
        userId: 'user1',
        actionCategoryCompleteCounts: {'movement': 10},
        actionCategorySkipCounts: {},
      );

      final weights = service.computeActionWeights(profile);

      // 10 / (10 + 0) = 1.0
      expect(weights['movement'], 1.0);
    });

    test('returns empty map when profile has no category data', () {
      final profile = UserBehaviorProfile(
        userId: 'user1',
        actionCategoryCompleteCounts: {},
        actionCategorySkipCounts: {},
      );

      final weights = service.computeActionWeights(profile);

      expect(weights, isEmpty);
    });
  });

  group('PersonalizationService.hasRecurringPattern', () {
    test('returns true when a value appears >= 3 times', () {
      final checkIns = List.generate(7, (i) {
        return CheckIn(
          id: 'id_$i',
          date: DateTime(2024, 1, 7 - i),
          energyScore: i < 3 ? 4 : (i + 1),
          moodState: MoodState.calm,
        );
      });

      // energyScore: 4 appears 3 times (indices 0,1,2)
      expect(service.hasRecurringPattern('energyScore', checkIns), isTrue);
    });

    test('returns false when no value appears >= 3 times', () {
      // Each energyScore value appears at most twice
      final checkIns = [
        CheckIn(id: '1', date: DateTime(2024, 1, 7), energyScore: 1),
        CheckIn(id: '2', date: DateTime(2024, 1, 6), energyScore: 1),
        CheckIn(id: '3', date: DateTime(2024, 1, 5), energyScore: 2),
        CheckIn(id: '4', date: DateTime(2024, 1, 4), energyScore: 2),
        CheckIn(id: '5', date: DateTime(2024, 1, 3), energyScore: 3),
        CheckIn(id: '6', date: DateTime(2024, 1, 2), energyScore: 4),
        CheckIn(id: '7', date: DateTime(2024, 1, 1), energyScore: 5),
      ];

      // Max occurrence is 2 for values 1 and 2
      expect(service.hasRecurringPattern('energyScore', checkIns), isFalse);
    });

    test('works with moodState field', () {
      final checkIns = List.generate(7, (i) {
        return CheckIn(
          id: 'id_$i',
          date: DateTime(2024, 1, 7 - i),
          moodState: i < 4 ? MoodState.stressed : MoodState.calm,
        );
      });

      // stressed appears 4 times
      expect(service.hasRecurringPattern('moodState', checkIns), isTrue);
    });

    test('works with recoveryStatus field', () {
      final checkIns = List.generate(7, (i) {
        return CheckIn(
          id: 'id_$i',
          date: DateTime(2024, 1, 7 - i),
          recoveryStatus:
              i < 3 ? RecoveryStatus.fatigued : RecoveryStatus.wellRested,
        );
      });

      // fatigued appears 3 times
      expect(service.hasRecurringPattern('recoveryStatus', checkIns), isTrue);
    });

    test('works with availableTime field', () {
      final checkIns = List.generate(7, (i) {
        return CheckIn(
          id: 'id_$i',
          date: DateTime(2024, 1, 7 - i),
          availableTime:
              i < 3 ? AvailableTimeRange.under10 : AvailableTimeRange.over60,
        );
      });

      // under10 appears 3 times
      expect(service.hasRecurringPattern('availableTime', checkIns), isTrue);
    });

    test('returns false for unknown field name', () {
      final checkIns = List.generate(7, (i) {
        return CheckIn(
          id: 'id_$i',
          date: DateTime(2024, 1, 7 - i),
          energyScore: 3,
        );
      });

      expect(service.hasRecurringPattern('unknownField', checkIns), isFalse);
    });

    test('ignores null values in the count', () {
      final checkIns = List.generate(7, (i) {
        return CheckIn(
          id: 'id_$i',
          date: DateTime(2024, 1, 7 - i),
          energyScore: null, // all null
        );
      });

      expect(service.hasRecurringPattern('energyScore', checkIns), isFalse);
    });

    test('returns false for empty list', () {
      expect(service.hasRecurringPattern('energyScore', []), isFalse);
    });

    test('exactly 3 occurrences returns true', () {
      final checkIns = [
        CheckIn(id: '1', date: DateTime(2024, 1, 7), moodState: MoodState.calm),
        CheckIn(id: '2', date: DateTime(2024, 1, 6), moodState: MoodState.calm),
        CheckIn(id: '3', date: DateTime(2024, 1, 5), moodState: MoodState.calm),
        CheckIn(id: '4', date: DateTime(2024, 1, 4), moodState: MoodState.anxious),
        CheckIn(id: '5', date: DateTime(2024, 1, 3), moodState: MoodState.stressed),
        CheckIn(id: '6', date: DateTime(2024, 1, 2), moodState: MoodState.tired),
        CheckIn(id: '7', date: DateTime(2024, 1, 1), moodState: MoodState.energized),
      ];

      expect(service.hasRecurringPattern('moodState', checkIns), isTrue);
    });
  });
}
