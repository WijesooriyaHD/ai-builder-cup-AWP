import 'package:flutter_test/flutter_test.dart';
import 'package:aiwellnesspal/providers/personalization_state.dart';
import 'package:aiwellnesspal/models/check_in.dart';
import 'package:aiwellnesspal/models/user_behavior_profile.dart';
import 'package:aiwellnesspal/models/wellness_action.dart';
import 'package:aiwellnesspal/models/wellness_enums.dart';
import 'package:aiwellnesspal/services/personalization_service.dart';

/// A fake PersonalizationService that stores profiles in memory.
class FakePersonalizationService extends PersonalizationService {
  UserBehaviorProfile? storedProfile;
  bool loadCalled = false;
  bool updateCalled = false;

  FakePersonalizationService() : super(firestore: null);

  @override
  Future<UserBehaviorProfile?> loadProfile(String userId) async {
    loadCalled = true;
    return storedProfile;
  }

  @override
  Future<void> updateProfile(
      String userId, UserBehaviorProfile profile) async {
    updateCalled = true;
    storedProfile = profile;
  }
}

void main() {
  late FakePersonalizationService fakeService;
  late PersonalizationState state;

  setUp(() {
    fakeService = FakePersonalizationService();
    state = PersonalizationState(service: fakeService);
  });

  group('PersonalizationState.loadProfile', () {
    test('loads existing profile and sets tier', () async {
      fakeService.storedProfile = UserBehaviorProfile(
        userId: 'user1',
        totalCheckIns: 15,
      );

      await state.loadProfile('user1', isPremium: true);

      expect(state.profile, isNotNull);
      expect(state.profile!.userId, 'user1');
      expect(state.profile!.totalCheckIns, 15);
      expect(state.tier, PersonalizationTier.prefill);
      expect(fakeService.loadCalled, isTrue);
    });

    test('creates default profile when none exists', () async {
      fakeService.storedProfile = null;

      await state.loadProfile('user2', isPremium: false);

      expect(state.profile, isNotNull);
      expect(state.profile!.userId, 'user2');
      expect(state.profile!.totalCheckIns, 0);
      expect(state.tier, PersonalizationTier.standard);
    });

    test('sets proactive tier for 28+ check-ins with premium', () async {
      fakeService.storedProfile = UserBehaviorProfile(
        userId: 'user3',
        totalCheckIns: 30,
      );

      await state.loadProfile('user3', isPremium: true);

      expect(state.tier, PersonalizationTier.proactive);
    });

    test('sets standard tier for 28+ check-ins without premium', () async {
      fakeService.storedProfile = UserBehaviorProfile(
        userId: 'user4',
        totalCheckIns: 30,
      );

      await state.loadProfile('user4', isPremium: false);

      expect(state.tier, PersonalizationTier.standard);
    });
  });

  group('PersonalizationState.updateProfile', () {
    test('increments totalCheckIns and updates field value counts', () async {
      fakeService.storedProfile = UserBehaviorProfile(
        userId: 'user1',
        totalCheckIns: 5,
        fieldValueCounts: {
          'energyScore': {'3': 3, '4': 2},
          'moodState': {'calm': 4, 'stressed': 1},
        },
      );
      await state.loadProfile('user1');

      final checkIn = CheckIn(
        id: 'ci_1',
        date: DateTime(2024, 3, 1),
        energyScore: 4,
        moodState: MoodState.calm,
        recoveryStatus: RecoveryStatus.wellRested,
        availableTime: AvailableTimeRange.range20_40,
      );

      await state.updateProfile(checkIn, []);

      expect(state.profile!.totalCheckIns, 6);
      expect(state.profile!.fieldValueCounts['energyScore']!['4'], 3);
      expect(state.profile!.fieldValueCounts['moodState']!['calm'], 5);
      expect(
          state.profile!.fieldValueCounts['recoveryStatus']!['wellRested'], 1);
      expect(
          state.profile!.fieldValueCounts['availableTime']!['range20_40'], 1);
      expect(fakeService.updateCalled, isTrue);
    });

    test('updates action category completion counts', () async {
      fakeService.storedProfile = UserBehaviorProfile(
        userId: 'user1',
        totalCheckIns: 10,
        actionCategoryCompleteCounts: {'flexibility': 2, 'stress': 1},
      );
      await state.loadProfile('user1');

      final checkIn = CheckIn(
        id: 'ci_2',
        date: DateTime(2024, 3, 2),
        energyScore: 3,
      );

      final completedActions = [
        WellnessAction(
          id: 'a1',
          title: 'Stretch',
          durationMinutes: 10,
          category: WellnessCategory.flexibility,
          intensityLevel: IntensityLevel.low,
          isCompleted: true,
        ),
        WellnessAction(
          id: 'a2',
          title: 'Breathwork',
          durationMinutes: 5,
          category: WellnessCategory.stress,
          intensityLevel: IntensityLevel.low,
          isCompleted: true,
        ),
      ];

      await state.updateProfile(checkIn, completedActions);

      expect(state.profile!.actionCategoryCompleteCounts['flexibility'], 3);
      expect(state.profile!.actionCategoryCompleteCounts['stress'], 2);
    });

    test('recalculates tier after update', () async {
      fakeService.storedProfile = UserBehaviorProfile(
        userId: 'user1',
        totalCheckIns: 13,
      );
      await state.loadProfile('user1', isPremium: true);
      expect(state.tier, PersonalizationTier.standard);

      final checkIn = CheckIn(
        id: 'ci_3',
        date: DateTime(2024, 3, 3),
        energyScore: 3,
      );

      await state.updateProfile(checkIn, [], isPremium: true);

      // Now totalCheckIns = 14 with premium → prefill
      expect(state.profile!.totalCheckIns, 14);
      expect(state.tier, PersonalizationTier.prefill);
    });

    test('does nothing when profile is null', () async {
      // Don't load a profile
      final checkIn = CheckIn(
        id: 'ci_4',
        date: DateTime(2024, 3, 4),
        energyScore: 3,
      );

      await state.updateProfile(checkIn, []);

      expect(state.profile, isNull);
      expect(fakeService.updateCalled, isFalse);
    });

    test('handles skipped check-in fields gracefully', () async {
      fakeService.storedProfile = UserBehaviorProfile(
        userId: 'user1',
        totalCheckIns: 5,
      );
      await state.loadProfile('user1');

      final checkIn = CheckIn(
        id: 'ci_5',
        date: DateTime(2024, 3, 5),
        // All fields null (skipped)
        skippedFields: ['energyScore', 'moodState', 'recoveryStatus', 'availableTime'],
      );

      await state.updateProfile(checkIn, []);

      expect(state.profile!.totalCheckIns, 6);
      // No field value counts should have been updated
      expect(state.profile!.fieldValueCounts['energyScore'], isNull);
      expect(state.profile!.fieldValueCounts['moodState'], isNull);
    });
  });

  group('PersonalizationState.summarizePreferences', () {
    test('returns default message when profile is null', () {
      expect(
        state.summarizePreferences(),
        'Not enough data yet. Complete a few check-ins to see your patterns.',
      );
    });

    test('returns default message when totalCheckIns is 0', () async {
      fakeService.storedProfile = UserBehaviorProfile(
        userId: 'user1',
        totalCheckIns: 0,
      );
      await state.loadProfile('user1');

      expect(
        state.summarizePreferences(),
        'Not enough data yet. Complete a few check-ins to see your patterns.',
      );
    });

    test('includes typical energy range', () async {
      fakeService.storedProfile = UserBehaviorProfile(
        userId: 'user1',
        totalCheckIns: 10,
        fieldValueCounts: {
          'energyScore': {'3': 5, '4': 3, '2': 2},
        },
      );
      await state.loadProfile('user1');

      final summary = state.summarizePreferences();
      expect(summary, contains('Typical energy: 3-4'));
    });

    test('includes most common mood', () async {
      fakeService.storedProfile = UserBehaviorProfile(
        userId: 'user1',
        totalCheckIns: 10,
        fieldValueCounts: {
          'moodState': {'calm': 6, 'stressed': 3, 'tired': 1},
        },
      );
      await state.loadProfile('user1');

      final summary = state.summarizePreferences();
      expect(summary, contains('Most common mood: calm'));
    });

    test('includes preferred time as human-readable label', () async {
      fakeService.storedProfile = UserBehaviorProfile(
        userId: 'user1',
        totalCheckIns: 10,
        fieldValueCounts: {
          'availableTime': {'range20_40': 7, 'range10_20': 3},
        },
      );
      await state.loadProfile('user1');

      final summary = state.summarizePreferences();
      expect(summary, contains('Preferred time: 20-40 minutes'));
    });

    test('includes deprioritized categories', () async {
      fakeService.storedProfile = UserBehaviorProfile(
        userId: 'user1',
        totalCheckIns: 10,
        fieldValueCounts: {
          'energyScore': {'3': 5, '4': 5},
        },
        deprioritizedCategories: ['sleep', 'recovery'],
      );
      await state.loadProfile('user1');

      final summary = state.summarizePreferences();
      expect(summary, contains('Categories you tend to skip: [sleep, recovery]'));
    });

    test('produces full summary with all sections', () async {
      fakeService.storedProfile = UserBehaviorProfile(
        userId: 'user1',
        totalCheckIns: 20,
        fieldValueCounts: {
          'energyScore': {'3': 8, '4': 6, '2': 4, '5': 2},
          'moodState': {'calm': 10, 'energized': 5, 'tired': 5},
          'availableTime': {'range20_40': 12, 'range10_20': 5, 'over60': 3},
        },
        deprioritizedCategories: ['sleep'],
      );
      await state.loadProfile('user1');

      final summary = state.summarizePreferences();
      expect(summary, contains('Typical energy:'));
      expect(summary, contains('Most common mood: calm'));
      expect(summary, contains('Preferred time: 20-40 minutes'));
      expect(summary, contains('Categories you tend to skip: [sleep]'));
      expect(summary, endsWith('.'));
    });
  });

  group('PersonalizationState notifyListeners', () {
    test('notifies listeners on loadProfile', () async {
      fakeService.storedProfile = UserBehaviorProfile(
        userId: 'user1',
        totalCheckIns: 5,
      );

      int notifyCount = 0;
      state.addListener(() => notifyCount++);

      await state.loadProfile('user1');

      expect(notifyCount, 1);
    });

    test('notifies listeners on updateProfile', () async {
      fakeService.storedProfile = UserBehaviorProfile(
        userId: 'user1',
        totalCheckIns: 5,
      );
      await state.loadProfile('user1');

      int notifyCount = 0;
      state.addListener(() => notifyCount++);

      final checkIn = CheckIn(
        id: 'ci_6',
        date: DateTime(2024, 3, 6),
        energyScore: 4,
      );

      await state.updateProfile(checkIn, []);

      expect(notifyCount, 1);
    });
  });
}
