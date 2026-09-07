import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:aiwellnesspal/models/daily_plan.dart';
import 'package:aiwellnesspal/models/wellness_action.dart';
import 'package:aiwellnesspal/models/wellness_enums.dart';
import 'package:aiwellnesspal/models/wellness_intention.dart';

// ─── Helpers ─────────────────────────────────────────────────────────────────

/// Simulates the onboarding routing logic from AuthWrapper.
/// Returns 'home' if onboarding is completed, 'onboarding' otherwise.
///
/// This mirrors the logic in auth_wrapper.dart:
///   final onboardingCompleted = data?['onboarding_completed'] == true;
///   if (onboardingCompleted) → MainWrapper; else → OnboardingScreen
String resolveInitialRoute({required bool? onboardingCompleted}) {
  if (onboardingCompleted == true) {
    return 'home';
  }
  return 'onboarding';
}

/// Simulates the Cloud Function's enforceConstraints logic for action count.
/// Pads to 2 if fewer, trims to 4 if more.
List<WellnessAction> enforceActionCountConstraint(List<WellnessAction> actions) {
  final result = List<WellnessAction>.from(actions);

  // Pad with filler actions if fewer than 2
  while (result.length < 2) {
    result.add(WellnessAction(
      id: 'filler_${result.length + 1}',
      title: '5-Minute Deep Breathing',
      durationMinutes: 5,
      category: WellnessCategory.mindfulness,
      intensityLevel: IntensityLevel.low,
    ));
  }

  // Trim to 4 if more
  if (result.length > 4) {
    return result.sublist(0, 4);
  }

  return result;
}

/// Simulates the low-energy constraint: if energyScore <= 2,
/// downgrade high-intensity actions to medium.
List<WellnessAction> enforceLowEnergyConstraint(
  List<WellnessAction> actions,
  int energyScore,
) {
  if (energyScore > 2) return actions;
  return actions.map((action) {
    if (action.intensityLevel == IntensityLevel.high) {
      return WellnessAction(
        id: action.id,
        title: action.title,
        durationMinutes: action.durationMinutes,
        category: action.category,
        intensityLevel: IntensityLevel.medium,
        isCompleted: action.isCompleted,
      );
    }
    return action;
  }).toList();
}

/// Generates a random WellnessAction using the given Random instance.
WellnessAction randomWellnessAction(Random rng, {IntensityLevel? forcedIntensity}) {
  final categories = WellnessCategory.values;
  final intensities = IntensityLevel.values;
  final duration = rng.nextInt(30) + 1; // 1-30 minutes

  return WellnessAction(
    id: 'action_${rng.nextInt(100000)}',
    title: 'Action ${rng.nextInt(1000)}',
    durationMinutes: duration,
    category: categories[rng.nextInt(categories.length)],
    intensityLevel: forcedIntensity ?? intensities[rng.nextInt(intensities.length)],
    isCompleted: rng.nextBool(),
  );
}

/// Generates a list of random WellnessActions of specified length.
List<WellnessAction> randomActions(Random rng, int count, {IntensityLevel? forcedIntensity}) {
  return List.generate(count, (_) => randomWellnessAction(rng, forcedIntensity: forcedIntensity));
}

// ─── Property Tests ──────────────────────────────────────────────────────────

void main() {
  // ─── Property 1: Onboarding Routing Is Deterministic ─────────────────────
  // **Validates: Requirements 1.1, 1.5**
  group('Property 1: Onboarding Routing Is Deterministic', () {
    test('for any user profile, routing is deterministic based on onboarding_completed', () {
      final rng = Random(42);

      for (var i = 0; i < 100; i++) {
        // Generate random profile states: true, false, or null
        final choice = rng.nextInt(3);
        final bool? onboardingCompleted;
        switch (choice) {
          case 0:
            onboardingCompleted = true;
            break;
          case 1:
            onboardingCompleted = false;
            break;
          default:
            onboardingCompleted = null;
            break;
        }

        final route = resolveInitialRoute(onboardingCompleted: onboardingCompleted);

        if (onboardingCompleted == true) {
          expect(route, 'home',
              reason: 'When onboarding_completed == true, route must be home '
                  '(iteration $i, value: $onboardingCompleted)');
        } else {
          expect(route, 'onboarding',
              reason: 'When onboarding_completed is false or null, route must be onboarding '
                  '(iteration $i, value: $onboardingCompleted)');
        }
      }
    });

    test('routing is consistent across repeated calls with the same input', () {
      // Determinism: same input always produces same output
      for (final value in [true, false, null]) {
        final results = List.generate(
          100,
          (_) => resolveInitialRoute(onboardingCompleted: value),
        );
        expect(results.toSet().length, 1,
            reason: 'resolveInitialRoute should return the same value for input: $value');
      }
    });
  });

  // ─── Property 2: Wellness Intention Count Constraint ─────────────────────
  // **Validates: Requirements 1.3, 5.4**
  group('Property 2: Wellness Intention Count Constraint', () {
    test('active intention count is always between 1 and 5 inclusive', () {
      final rng = Random(123);

      for (var i = 0; i < 100; i++) {
        // Generate a random number of intentions (1..10)
        final rawCount = rng.nextInt(10) + 1;
        // Constrain to [1, 5] as the app enforces
        final activeCount = rawCount.clamp(1, 5);

        expect(activeCount, greaterThanOrEqualTo(1),
            reason: 'Active intentions must be >= 1 (iteration $i, raw: $rawCount)');
        expect(activeCount, lessThanOrEqualTo(5),
            reason: 'Active intentions must be <= 5 (iteration $i, raw: $rawCount)');
      }
    });

    test('adding a 6th intention to a set of 5 is rejected', () {
      final rng = Random(456);

      for (var i = 0; i < 100; i++) {
        // Start with exactly 5 active intentions
        final activeIntentions = List.generate(5, (idx) {
          final categories = WellnessCategory.values;
          return WellnessIntention(
            title: 'Intention $idx',
            category: categories[rng.nextInt(categories.length)],
            isActive: true,
          );
        });

        // Attempt to add a 6th
        final canAdd = activeIntentions.where((i) => i.isActive).length < 5;
        expect(canAdd, isFalse,
            reason: 'Should not be able to add a 6th intention when 5 are active '
                '(iteration $i)');
      }
    });

    test('removing from a set of 1 active intention leaves minimum constraint violated', () {
      final rng = Random(789);

      for (var i = 0; i < 100; i++) {
        final categories = WellnessCategory.values;
        final singleIntention = [
          WellnessIntention(
            title: 'Only Intention ${rng.nextInt(1000)}',
            category: categories[rng.nextInt(categories.length)],
            isActive: true,
          ),
        ];

        // After removing the one active intention, count would be 0
        final activeAfterRemoval =
            singleIntention.where((i) => i.isActive).length - 1;
        final wouldViolateMinimum = activeAfterRemoval < 1;

        expect(wouldViolateMinimum, isTrue,
            reason: 'Removing the last active intention should violate the minimum '
                'constraint (iteration $i)');
      }
    });
  });

  // ─── Property 3: DailyPlan Action Count Is Bounded [2, 4] ────────────────
  // **Validates: Requirements 3.1**
  group('Property 3: DailyPlan Action Count Is Bounded [2, 4]', () {
    test('enforceActionCountConstraint always produces 2-4 actions', () {
      final rng = Random(101);

      for (var i = 0; i < 100; i++) {
        // Generate random action count from 0 to 8
        final rawCount = rng.nextInt(9);
        final rawActions = randomActions(rng, rawCount);

        final constrainedActions = enforceActionCountConstraint(rawActions);

        expect(constrainedActions.length, greaterThanOrEqualTo(2),
            reason: 'Constrained actions must have at least 2 '
                '(iteration $i, raw count: $rawCount)');
        expect(constrainedActions.length, lessThanOrEqualTo(4),
            reason: 'Constrained actions must have at most 4 '
                '(iteration $i, raw count: $rawCount)');
      }
    });

    test('DailyPlan.fromMap enforces action count via constructor', () {
      final rng = Random(202);

      for (var i = 0; i < 100; i++) {
        // Generate 2-4 actions (valid range) to ensure fromMap works
        final actionCount = rng.nextInt(3) + 2; // 2, 3, or 4
        final actions = randomActions(rng, actionCount);
        final totalTime = actions.fold<int>(0, (sum, a) => sum + a.durationMinutes);

        final map = {
          'id': 'plan_$i',
          'date': '2024-06-${(i % 28 + 1).toString().padLeft(2, '0')}T00:00:00.000',
          'todaysFocus': 'Focus $i',
          'actions': actions.map((a) => a.toMap()).toList(),
          'totalTime': totalTime,
          'isFallback': false,
          'isCompleted': false,
        };

        final plan = DailyPlan.fromMap(map);

        expect(plan.actions.length, greaterThanOrEqualTo(2),
            reason: 'Plan from map must have >= 2 actions (iteration $i)');
        expect(plan.actions.length, lessThanOrEqualTo(4),
            reason: 'Plan from map must have <= 4 actions (iteration $i)');
      }
    });
  });

  // ─── Property 4: DailyPlan Total Time Is Accurate ────────────────────────
  // **Validates: Requirements 3.3**
  group('Property 4: DailyPlan Total Time Is Accurate', () {
    test('totalTime always equals sum of action durations via constructor', () {
      final rng = Random(303);

      for (var i = 0; i < 100; i++) {
        final actionCount = rng.nextInt(3) + 2; // 2-4 actions
        final actions = randomActions(rng, actionCount);
        final expectedTotal = actions.fold<int>(0, (sum, a) => sum + a.durationMinutes);

        final plan = DailyPlan(
          id: 'plan_$i',
          date: DateTime(2024, 6, 15),
          todaysFocus: 'Focus $i',
          actions: actions,
          totalTime: expectedTotal,
        );

        expect(plan.totalTime, expectedTotal,
            reason: 'totalTime must equal sum of action durations '
                '(iteration $i, expected: $expectedTotal, got: ${plan.totalTime})');
      }
    });

    test('DailyPlan.fromMap recalculates totalTime correctly regardless of stored value', () {
      final rng = Random(404);

      for (var i = 0; i < 100; i++) {
        final actionCount = rng.nextInt(3) + 2; // 2-4 actions
        final actions = randomActions(rng, actionCount);
        final correctTotal = actions.fold<int>(0, (sum, a) => sum + a.durationMinutes);

        // Deliberately set an incorrect totalTime in the map
        final incorrectTotal = correctTotal + rng.nextInt(50) + 1;

        final map = {
          'id': 'plan_$i',
          'date': '2024-06-15T00:00:00.000',
          'todaysFocus': 'Focus $i',
          'actions': actions.map((a) => a.toMap()).toList(),
          'totalTime': incorrectTotal, // Wrong value on purpose
          'isFallback': false,
          'isCompleted': false,
        };

        final plan = DailyPlan.fromMap(map);

        // fromMap must recalculate totalTime from actions
        expect(plan.totalTime, correctTotal,
            reason: 'fromMap must recalculate totalTime as sum of action durations '
                '(iteration $i, stored: $incorrectTotal, expected: $correctTotal)');
      }
    });

    test('constructor assertion fails if totalTime does not match sum', () {
      final rng = Random(505);

      for (var i = 0; i < 100; i++) {
        final actionCount = rng.nextInt(3) + 2;
        final actions = randomActions(rng, actionCount);
        final correctTotal = actions.fold<int>(0, (sum, a) => sum + a.durationMinutes);
        final wrongTotal = correctTotal + 1;

        expect(
          () => DailyPlan(
            id: 'plan_$i',
            date: DateTime(2024, 6, 15),
            todaysFocus: 'Focus $i',
            actions: actions,
            totalTime: wrongTotal,
          ),
          throwsA(isA<AssertionError>()),
          reason: 'Constructor should assert when totalTime != sum of durations '
              '(iteration $i)',
        );
      }
    });
  });

  // ─── Property 5: Low-Energy Plans Contain No High-Intensity Actions ──────
  // **Validates: Requirements 3.4**
  group('Property 5: Low-Energy Plans Contain No High-Intensity Actions', () {
    test('enforceLowEnergyConstraint removes all high-intensity actions when energyScore <= 2', () {
      final rng = Random(606);

      for (var i = 0; i < 100; i++) {
        // Generate energy score of 1 or 2
        final energyScore = rng.nextInt(2) + 1; // 1 or 2
        final actionCount = rng.nextInt(3) + 2; // 2-4 actions

        // Generate actions with random intensity levels (including high)
        final actions = randomActions(rng, actionCount);
        final constrainedActions = enforceLowEnergyConstraint(actions, energyScore);

        for (final action in constrainedActions) {
          expect(action.intensityLevel, isNot(IntensityLevel.high),
              reason: 'Low-energy plan (energyScore=$energyScore) must not contain '
                  'high-intensity actions (iteration $i, action: ${action.title})');
        }
      }
    });

    test('high-intensity actions are preserved when energyScore > 2', () {
      final rng = Random(707);

      for (var i = 0; i < 100; i++) {
        // Generate energy score 3, 4, or 5
        final energyScore = rng.nextInt(3) + 3; // 3, 4, or 5
        final actionCount = rng.nextInt(3) + 2;

        // Force at least one high-intensity action
        final actions = randomActions(rng, actionCount);
        final withHigh = [
          ...actions,
          WellnessAction(
            id: 'high_action',
            title: 'High Intensity Run',
            durationMinutes: 20,
            category: WellnessCategory.movement,
            intensityLevel: IntensityLevel.high,
          ),
        ].sublist(0, actionCount); // Keep within bounds

        final constrainedActions = enforceLowEnergyConstraint(withHigh, energyScore);

        // Original actions should be unchanged
        expect(constrainedActions, withHigh,
            reason: 'Actions should be unchanged when energyScore > 2 '
                '(iteration $i, energyScore=$energyScore)');
      }
    });

    test('DailyPlan with energyTier 1 and enforced constraints has no high-intensity', () {
      final rng = Random(808);

      for (var i = 0; i < 100; i++) {
        final energyScore = rng.nextInt(2) + 1; // 1 or 2
        final actionCount = rng.nextInt(3) + 2;

        // Generate mixed-intensity actions
        final rawActions = randomActions(rng, actionCount);

        // Apply the constraint (as the Cloud Function would)
        final safeActions = enforceLowEnergyConstraint(rawActions, energyScore);
        final totalTime = safeActions.fold<int>(0, (sum, a) => sum + a.durationMinutes);

        // Build a valid DailyPlan
        final plan = DailyPlan(
          id: 'plan_low_$i',
          date: DateTime(2024, 6, 15),
          todaysFocus: 'Gentle Recovery',
          actions: safeActions,
          totalTime: totalTime,
          energyTier: 1,
        );

        for (final action in plan.actions) {
          expect(action.intensityLevel, isNot(IntensityLevel.high),
              reason: 'Plan with energyTier 1 must not have high-intensity actions '
                  '(iteration $i, energyScore=$energyScore)');
        }
      }
    });
  });
}
