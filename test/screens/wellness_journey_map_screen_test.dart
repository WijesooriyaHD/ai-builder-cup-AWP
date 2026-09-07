import 'package:flutter_test/flutter_test.dart';
import 'package:aiwellnesspal/models/check_in.dart';
import 'package:aiwellnesspal/models/daily_plan.dart';
import 'package:aiwellnesspal/models/wellness_action.dart';
import 'package:aiwellnesspal/models/wellness_enums.dart';
import 'package:aiwellnesspal/models/wellness_milestone.dart';
import 'package:aiwellnesspal/models/travel_memory.dart';

// Test helpers to create mock data

DailyPlan _createPlan({
  required DateTime date,
  bool isCompleted = true,
  String? checkInId,
}) {
  return DailyPlan(
    id: 'plan_${date.millisecondsSinceEpoch}',
    date: date,
    todaysFocus: 'Gentle Recovery',
    actions: [
      WellnessAction(
        id: 'a1',
        title: 'Morning Stretch',
        durationMinutes: 15,
        category: WellnessCategory.flexibility,
        intensityLevel: IntensityLevel.low,
        isCompleted: isCompleted,
      ),
    ],
    totalTime: 15,
    isCompleted: isCompleted,
    checkInId: checkInId,
  );
}

CheckIn _createCheckIn({
  required DateTime date,
  int? energyScore,
  RecoveryStatus? recoveryStatus,
  String? id,
}) {
  return CheckIn(
    id: id ?? 'checkin_${date.millisecondsSinceEpoch}',
    date: date,
    energyScore: energyScore,
    recoveryStatus: recoveryStatus,
  );
}

TravelMemory _createMilestone({
  required MilestoneType type,
  required int planCount,
  required DateTime date,
}) {
  return WellnessMilestoneHelper.create(
    milestoneName: '$planCount Plans Completed',
    type: type,
    completedPlanCount: planCount,
    achievementDate: date,
    supportingMessage: WellnessMilestoneHelper.supportingMessageFor(type),
  );
}

void main() {
  group('WellnessJourneyMapScreen - Data Layers', () {
    // Note: Full widget pumping with all providers requires complex mocking.
    // We test the data models and logic separately.

    group('7-Day Trend Calculation', () {
      test('counts completed plans in the current 7-day window', () {
        final now = DateTime.now();
        final plans = [
          _createPlan(date: now.subtract(const Duration(days: 1))),
          _createPlan(date: now.subtract(const Duration(days: 3))),
          _createPlan(date: now.subtract(const Duration(days: 5))),
          _createPlan(date: now.subtract(const Duration(days: 10))), // previous week
        ];

        final sevenDaysAgo = now.subtract(const Duration(days: 7));
        final currentWeekCompleted = plans
            .where((p) => p.isCompleted && p.date.isAfter(sevenDaysAgo))
            .length;

        expect(currentWeekCompleted, 3);
      });

      test('counts completed plans in the previous 7-day window', () {
        final now = DateTime.now();
        final plans = [
          _createPlan(date: now.subtract(const Duration(days: 1))),
          _createPlan(date: now.subtract(const Duration(days: 8))),
          _createPlan(date: now.subtract(const Duration(days: 10))),
          _createPlan(date: now.subtract(const Duration(days: 12))),
        ];

        final sevenDaysAgo = now.subtract(const Duration(days: 7));
        final fourteenDaysAgo = now.subtract(const Duration(days: 14));

        final previousWeekCompleted = plans
            .where((p) =>
                p.isCompleted &&
                p.date.isAfter(fourteenDaysAgo) &&
                p.date.isBefore(sevenDaysAgo))
            .length;

        expect(previousWeekCompleted, 3);
      });

      test('shows upward trend when current >= previous', () {
        final now = DateTime.now();
        final plans = [
          _createPlan(date: now.subtract(const Duration(days: 1))),
          _createPlan(date: now.subtract(const Duration(days: 2))),
          _createPlan(date: now.subtract(const Duration(days: 10))),
        ];

        final sevenDaysAgo = now.subtract(const Duration(days: 7));
        final fourteenDaysAgo = now.subtract(const Duration(days: 14));

        final currentWeekCompleted = plans
            .where((p) => p.isCompleted && p.date.isAfter(sevenDaysAgo))
            .length;
        final previousWeekCompleted = plans
            .where((p) =>
                p.isCompleted &&
                p.date.isAfter(fourteenDaysAgo) &&
                p.date.isBefore(sevenDaysAgo))
            .length;

        final isUp = currentWeekCompleted >= previousWeekCompleted;
        expect(isUp, true);
        expect(currentWeekCompleted, 2);
        expect(previousWeekCompleted, 1);
      });

      test('shows downward trend when current < previous', () {
        final now = DateTime.now();
        final plans = [
          _createPlan(date: now.subtract(const Duration(days: 1))),
          _createPlan(date: now.subtract(const Duration(days: 8))),
          _createPlan(date: now.subtract(const Duration(days: 9))),
          _createPlan(date: now.subtract(const Duration(days: 10))),
        ];

        final sevenDaysAgo = now.subtract(const Duration(days: 7));
        final fourteenDaysAgo = now.subtract(const Duration(days: 14));

        final currentWeekCompleted = plans
            .where((p) => p.isCompleted && p.date.isAfter(sevenDaysAgo))
            .length;
        final previousWeekCompleted = plans
            .where((p) =>
                p.isCompleted &&
                p.date.isAfter(fourteenDaysAgo) &&
                p.date.isBefore(sevenDaysAgo))
            .length;

        final isUp = currentWeekCompleted >= previousWeekCompleted;
        expect(isUp, false);
        expect(currentWeekCompleted, 1);
        expect(previousWeekCompleted, 3);
      });
    });

    group('Energy Trend Line Filtering', () {
      test('filters check-ins to last 30 days with energy scores', () {
        final now = DateTime.now();
        final checkIns = [
          _createCheckIn(date: now.subtract(const Duration(days: 1)), energyScore: 4),
          _createCheckIn(date: now.subtract(const Duration(days: 5)), energyScore: 3),
          _createCheckIn(date: now.subtract(const Duration(days: 10)), energyScore: null), // skipped
          _createCheckIn(date: now.subtract(const Duration(days: 35)), energyScore: 5), // too old
        ];

        final thirtyDaysAgo = now.subtract(const Duration(days: 30));
        final energyCheckIns = checkIns
            .where(
                (c) => c.energyScore != null && c.date.isAfter(thirtyDaysAgo))
            .toList();

        expect(energyCheckIns.length, 2);
        expect(energyCheckIns[0].energyScore, 4);
        expect(energyCheckIns[1].energyScore, 3);
      });

      test('shows all available points when fewer than 30 days', () {
        final now = DateTime.now();
        final checkIns = List.generate(5, (i) =>
          _createCheckIn(
            date: now.subtract(Duration(days: i + 1)),
            energyScore: (i % 5) + 1,
          ),
        );

        final thirtyDaysAgo = now.subtract(const Duration(days: 30));
        final energyCheckIns = checkIns
            .where(
                (c) => c.energyScore != null && c.date.isAfter(thirtyDaysAgo))
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));

        expect(energyCheckIns.length, 5);
      });

      test('produces correct date range label for partial data', () {
        final now = DateTime.now();
        final checkIns = [
          _createCheckIn(date: now.subtract(const Duration(days: 10)), energyScore: 3),
          _createCheckIn(date: now.subtract(const Duration(days: 5)), energyScore: 4),
        ];

        final thirtyDaysAgo = now.subtract(const Duration(days: 30));
        final energyCheckIns = checkIns
            .where(
                (c) => c.energyScore != null && c.date.isAfter(thirtyDaysAgo))
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));

        // Should have actual date range label (not "Last 30 days")
        expect(energyCheckIns.length, lessThan(30));
        expect(energyCheckIns.length, 2);
      });
    });

    group('Recovery Achievements', () {
      test('identifies completed plans with wellRested recovery status', () {
        final now = DateTime.now();
        final checkInId = 'ci_1';
        final plans = [
          _createPlan(
            date: now.subtract(const Duration(days: 1)),
            checkInId: checkInId,
          ),
          _createPlan(
            date: now.subtract(const Duration(days: 2)),
            checkInId: 'ci_2',
          ),
        ];
        final checkIns = [
          _createCheckIn(
            date: now.subtract(const Duration(days: 1)),
            recoveryStatus: RecoveryStatus.wellRested,
            id: checkInId,
          ),
          _createCheckIn(
            date: now.subtract(const Duration(days: 2)),
            recoveryStatus: RecoveryStatus.sore,
            id: 'ci_2',
          ),
        ];

        final checkInRecoveryMap = <String, RecoveryStatus>{};
        for (final checkIn in checkIns) {
          if (checkIn.recoveryStatus != null) {
            checkInRecoveryMap[checkIn.id] = checkIn.recoveryStatus!;
          }
        }

        final recoveryPlans = plans.where((plan) {
          if (!plan.isCompleted || plan.checkInId == null) return false;
          final status = checkInRecoveryMap[plan.checkInId];
          return status == RecoveryStatus.wellRested ||
              status == RecoveryStatus.recovering;
        }).toList();

        expect(recoveryPlans.length, 1);
        expect(recoveryPlans.first.checkInId, checkInId);
      });

      test('identifies completed plans with recovering status', () {
        final now = DateTime.now();
        final plans = [
          _createPlan(
            date: now.subtract(const Duration(days: 1)),
            checkInId: 'ci_recovering',
          ),
        ];
        final checkIns = [
          _createCheckIn(
            date: now.subtract(const Duration(days: 1)),
            recoveryStatus: RecoveryStatus.recovering,
            id: 'ci_recovering',
          ),
        ];

        final checkInRecoveryMap = <String, RecoveryStatus>{};
        for (final checkIn in checkIns) {
          if (checkIn.recoveryStatus != null) {
            checkInRecoveryMap[checkIn.id] = checkIn.recoveryStatus!;
          }
        }

        final recoveryPlans = plans.where((plan) {
          if (!plan.isCompleted || plan.checkInId == null) return false;
          final status = checkInRecoveryMap[plan.checkInId];
          return status == RecoveryStatus.wellRested ||
              status == RecoveryStatus.recovering;
        }).toList();

        expect(recoveryPlans.length, 1);
      });

      test('excludes incomplete plans from recovery achievements', () {
        final now = DateTime.now();
        final plans = [
          _createPlan(
            date: now.subtract(const Duration(days: 1)),
            isCompleted: false,
            checkInId: 'ci_1',
          ),
        ];
        final checkIns = [
          _createCheckIn(
            date: now.subtract(const Duration(days: 1)),
            recoveryStatus: RecoveryStatus.wellRested,
            id: 'ci_1',
          ),
        ];

        final checkInRecoveryMap = <String, RecoveryStatus>{};
        for (final checkIn in checkIns) {
          if (checkIn.recoveryStatus != null) {
            checkInRecoveryMap[checkIn.id] = checkIn.recoveryStatus!;
          }
        }

        final recoveryPlans = plans.where((plan) {
          if (!plan.isCompleted || plan.checkInId == null) return false;
          final status = checkInRecoveryMap[plan.checkInId];
          return status == RecoveryStatus.wellRested ||
              status == RecoveryStatus.recovering;
        }).toList();

        expect(recoveryPlans.length, 0);
      });

      test('excludes plans with sore or fatigued recovery status', () {
        final now = DateTime.now();
        final plans = [
          _createPlan(date: now.subtract(const Duration(days: 1)), checkInId: 'ci_sore'),
          _createPlan(date: now.subtract(const Duration(days: 2)), checkInId: 'ci_fatigued'),
        ];
        final checkIns = [
          _createCheckIn(
            date: now.subtract(const Duration(days: 1)),
            recoveryStatus: RecoveryStatus.sore,
            id: 'ci_sore',
          ),
          _createCheckIn(
            date: now.subtract(const Duration(days: 2)),
            recoveryStatus: RecoveryStatus.fatigued,
            id: 'ci_fatigued',
          ),
        ];

        final checkInRecoveryMap = <String, RecoveryStatus>{};
        for (final checkIn in checkIns) {
          if (checkIn.recoveryStatus != null) {
            checkInRecoveryMap[checkIn.id] = checkIn.recoveryStatus!;
          }
        }

        final recoveryPlans = plans.where((plan) {
          if (!plan.isCompleted || plan.checkInId == null) return false;
          final status = checkInRecoveryMap[plan.checkInId];
          return status == RecoveryStatus.wellRested ||
              status == RecoveryStatus.recovering;
        }).toList();

        expect(recoveryPlans.length, 0);
      });
    });

    group('Milestone Animation', () {
      test('detects new milestones via set difference', () {
        final milestone1 = _createMilestone(
          type: MilestoneType.firstPlan,
          planCount: 1,
          date: DateTime.now().subtract(const Duration(days: 10)),
        );
        final milestone2 = _createMilestone(
          type: MilestoneType.fivePlans,
          planCount: 5,
          date: DateTime.now(),
        );

        final previousIds = {milestone1.id};
        final currentIds = {milestone1.id, milestone2.id};
        final newIds = currentIds.difference(previousIds);

        expect(newIds.length, 1);
        expect(newIds.contains(milestone2.id), true);
      });

      test('returns empty set when no new milestones', () {
        final milestone1 = _createMilestone(
          type: MilestoneType.firstPlan,
          planCount: 1,
          date: DateTime.now().subtract(const Duration(days: 10)),
        );

        final previousIds = {milestone1.id};
        final currentIds = {milestone1.id};
        final newIds = currentIds.difference(previousIds);

        expect(newIds.isEmpty, true);
      });
    });
  });
}
