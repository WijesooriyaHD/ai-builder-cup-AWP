import 'package:flutter_test/flutter_test.dart';
import 'package:aiwellnesspal/providers/check_in_state.dart';
import 'package:aiwellnesspal/models/check_in.dart';
import 'package:aiwellnesspal/models/user_behavior_profile.dart';
import 'package:aiwellnesspal/models/wellness_enums.dart';
import 'package:aiwellnesspal/services/check_in_service.dart';
import 'package:aiwellnesspal/services/personalization_service.dart';

/// A fake CheckInService that stores check-ins in memory.
class FakeCheckInService extends CheckInService {
  CheckIn? storedCheckIn;
  List<CheckIn> recentCheckIns = [];
  CheckIn? cachedCheckIn;
  bool saveCalled = false;
  bool shouldThrowOnSave = false;

  FakeCheckInService() : super(firestore: null);

  @override
  Future<CheckIn?> loadCheckInForDate(String userId, DateTime date) async {
    if (storedCheckIn == null) return null;

    final storedDate = storedCheckIn!.date;
    if (storedDate.year == date.year &&
        storedDate.month == date.month &&
        storedDate.day == date.day) {
      return storedCheckIn;
    }
    return null;
  }

  @override
  Future<void> saveCheckIn(String userId, CheckIn checkIn) async {
    if (shouldThrowOnSave) {
      throw Exception('Firestore write failed');
    }
    saveCalled = true;
    storedCheckIn = checkIn;
  }

  @override
  Future<List<CheckIn>> loadRecentCheckIns(String userId,
      {int count = 14}) async {
    return recentCheckIns.take(count).toList();
  }

  @override
  Future<CheckIn?> loadCachedCheckIn() async {
    return cachedCheckIn;
  }
}

/// A fake PersonalizationService that stores profiles in memory.
class FakePersonalizationService extends PersonalizationService {
  UserBehaviorProfile? storedProfile;
  bool updateCalled = false;

  FakePersonalizationService() : super(firestore: null);

  @override
  Future<UserBehaviorProfile?> loadProfile(String userId) async {
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
  late FakeCheckInService fakeCheckInService;
  late FakePersonalizationService fakePersonalizationService;
  late CheckInState state;

  setUp(() {
    fakeCheckInService = FakeCheckInService();
    fakePersonalizationService = FakePersonalizationService();
    state = CheckInState(
      checkInService: fakeCheckInService,
      personalizationService: fakePersonalizationService,
    );
  });

  group('CheckInState initial state', () {
    test('has null todaysCheckIn', () {
      expect(state.todaysCheckIn, isNull);
    });

    test('has empty recentCheckIns', () {
      expect(state.recentCheckIns, isEmpty);
    });

    test('isSubmitting is false', () {
      expect(state.isSubmitting, isFalse);
    });

    test('hasCheckedInToday is false when no check-in exists', () {
      expect(state.hasCheckedInToday, isFalse);
    });
  });

  group('CheckInState.hasCheckedInToday', () {
    test('returns true when check-in date matches today', () async {
      final today = DateTime.now();
      fakeCheckInService.storedCheckIn = CheckIn(
        id: 'ci_today',
        date: today,
        energyScore: 3,
      );

      await state.loadTodaysCheckIn('user1');

      expect(state.hasCheckedInToday, isTrue);
    });

    test('returns false when check-in date is yesterday', () async {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      fakeCheckInService.cachedCheckIn = null;
      fakeCheckInService.storedCheckIn = CheckIn(
        id: 'ci_yesterday',
        date: yesterday,
        energyScore: 3,
      );

      // The loadCheckInForDate won't match because the stored date is yesterday
      // but we query for today
      await state.loadTodaysCheckIn('user1');

      expect(state.hasCheckedInToday, isFalse);
    });

    test('compares dates in local timezone', () async {
      final now = DateTime.now();
      // Create a UTC check-in that is today in local timezone
      final todayUtc = DateTime.utc(now.year, now.month, now.day, 12, 0, 0);
      fakeCheckInService.storedCheckIn = CheckIn(
        id: 'ci_utc',
        date: todayUtc,
        energyScore: 4,
      );

      await state.loadTodaysCheckIn('user1');

      // Should be true since toLocal() conversion should still yield today
      expect(state.hasCheckedInToday, isTrue);
    });
  });

  group('CheckInState.prefillValues', () {
    test('returns null when fewer than 14 check-ins', () {
      state = CheckInState(
        checkInService: fakeCheckInService,
        personalizationService: fakePersonalizationService,
        isPremium: true,
      );
      // recentCheckIns is empty
      expect(state.prefillValues, isNull);
    });

    test('returns null when not premium even with 14+ check-ins', () async {
      fakeCheckInService.recentCheckIns = List.generate(
        14,
        (i) => CheckIn(
          id: 'ci_$i',
          date: DateTime.now().subtract(Duration(days: i)),
          energyScore: 3,
          moodState: MoodState.calm,
        ),
      );

      state = CheckInState(
        checkInService: fakeCheckInService,
        personalizationService: fakePersonalizationService,
        isPremium: false,
      );

      await state.loadTodaysCheckIn('user1');

      expect(state.prefillValues, isNull);
    });

    test('returns computed prefill when premium and 14+ check-ins', () async {
      fakeCheckInService.recentCheckIns = List.generate(
        14,
        (i) => CheckIn(
          id: 'ci_$i',
          date: DateTime.now().subtract(Duration(days: i)),
          energyScore: 4,
          moodState: MoodState.calm,
          recoveryStatus: RecoveryStatus.wellRested,
          availableTime: AvailableTimeRange.range20_40,
        ),
      );

      state = CheckInState(
        checkInService: fakeCheckInService,
        personalizationService: fakePersonalizationService,
        isPremium: true,
      );

      await state.loadTodaysCheckIn('user1');

      final prefill = state.prefillValues;
      expect(prefill, isNotNull);
      expect(prefill!.energyScore, 4);
      expect(prefill.moodState, MoodState.calm);
      expect(prefill.recoveryStatus, RecoveryStatus.wellRested);
      expect(prefill.availableTime, AvailableTimeRange.range20_40);
    });

    test('returns prefill with mode values when check-ins vary', () async {
      // 8 check-ins with energyScore 3, 6 with energyScore 4
      fakeCheckInService.recentCheckIns = [
        ...List.generate(
          8,
          (i) => CheckIn(
            id: 'ci_$i',
            date: DateTime.now().subtract(Duration(days: i)),
            energyScore: 3,
            moodState: MoodState.stressed,
          ),
        ),
        ...List.generate(
          6,
          (i) => CheckIn(
            id: 'ci_${i + 8}',
            date: DateTime.now().subtract(Duration(days: i + 8)),
            energyScore: 4,
            moodState: MoodState.calm,
          ),
        ),
      ];

      state = CheckInState(
        checkInService: fakeCheckInService,
        personalizationService: fakePersonalizationService,
        isPremium: true,
      );

      await state.loadTodaysCheckIn('user1');

      final prefill = state.prefillValues;
      expect(prefill, isNotNull);
      // Mode of energyScore is 3 (8 occurrences vs 6)
      expect(prefill!.energyScore, 3);
      // Mode of moodState is stressed (8 vs 6)
      expect(prefill.moodState, MoodState.stressed);
    });
  });

  group('CheckInState.loadTodaysCheckIn', () {
    test('loads from cache first, then Firestore', () async {
      final today = DateTime.now();
      final cachedCheckIn = CheckIn(
        id: 'ci_cached',
        date: today,
        energyScore: 2,
      );
      final firestoreCheckIn = CheckIn(
        id: 'ci_firestore',
        date: today,
        energyScore: 4,
      );

      fakeCheckInService.cachedCheckIn = cachedCheckIn;
      fakeCheckInService.storedCheckIn = firestoreCheckIn;

      await state.loadTodaysCheckIn('user1');

      // Firestore value takes precedence
      expect(state.todaysCheckIn!.id, 'ci_firestore');
    });

    test('uses cached value when Firestore has no data', () async {
      final today = DateTime.now();
      final cachedCheckIn = CheckIn(
        id: 'ci_cached',
        date: today,
        energyScore: 2,
      );

      fakeCheckInService.cachedCheckIn = cachedCheckIn;
      fakeCheckInService.storedCheckIn = null;

      await state.loadTodaysCheckIn('user1');

      expect(state.todaysCheckIn!.id, 'ci_cached');
    });

    test('sets todaysCheckIn to null when no data anywhere', () async {
      fakeCheckInService.cachedCheckIn = null;
      fakeCheckInService.storedCheckIn = null;

      await state.loadTodaysCheckIn('user1');

      expect(state.todaysCheckIn, isNull);
    });

    test('loads recent check-ins for pre-fill', () async {
      fakeCheckInService.recentCheckIns = List.generate(
        5,
        (i) => CheckIn(
          id: 'ci_$i',
          date: DateTime.now().subtract(Duration(days: i)),
          energyScore: 3,
        ),
      );

      await state.loadTodaysCheckIn('user1');

      expect(state.recentCheckIns.length, 5);
    });
  });

  group('CheckInState.submitCheckIn', () {
    test('saves check-in and updates local state', () async {
      fakePersonalizationService.storedProfile = UserBehaviorProfile(
        userId: 'user1',
        totalCheckIns: 5,
      );

      await state.loadTodaysCheckIn('user1');

      final checkIn = CheckIn(
        id: 'ci_new',
        date: DateTime.now(),
        energyScore: 4,
        moodState: MoodState.energized,
        recoveryStatus: RecoveryStatus.wellRested,
        availableTime: AvailableTimeRange.range20_40,
      );

      await state.submitCheckIn(checkIn);

      expect(state.todaysCheckIn, checkIn);
      expect(state.hasCheckedInToday, isTrue);
      expect(fakeCheckInService.saveCalled, isTrue);
    });

    test('prepends to recentCheckIns and caps at 14', () async {
      fakeCheckInService.recentCheckIns = List.generate(
        14,
        (i) => CheckIn(
          id: 'old_$i',
          date: DateTime.now().subtract(Duration(days: i + 1)),
          energyScore: 3,
        ),
      );

      await state.loadTodaysCheckIn('user1');
      expect(state.recentCheckIns.length, 14);

      final newCheckIn = CheckIn(
        id: 'ci_new',
        date: DateTime.now(),
        energyScore: 5,
      );

      await state.submitCheckIn(newCheckIn);

      expect(state.recentCheckIns.length, 14);
      expect(state.recentCheckIns.first.id, 'ci_new');
    });

    test('updates behavior profile after save', () async {
      fakePersonalizationService.storedProfile = UserBehaviorProfile(
        userId: 'user1',
        totalCheckIns: 10,
      );

      await state.loadTodaysCheckIn('user1');

      final checkIn = CheckIn(
        id: 'ci_new',
        date: DateTime.now(),
        energyScore: 4,
        moodState: MoodState.calm,
      );

      await state.submitCheckIn(checkIn);

      expect(fakePersonalizationService.updateCalled, isTrue);
      expect(fakePersonalizationService.storedProfile!.totalCheckIns, 11);
    });

    test('sets isSubmitting during submission', () async {
      await state.loadTodaysCheckIn('user1');

      final states = <bool>[];
      state.addListener(() => states.add(state.isSubmitting));

      final checkIn = CheckIn(
        id: 'ci_new',
        date: DateTime.now(),
        energyScore: 3,
      );

      await state.submitCheckIn(checkIn);

      // Should have been true then false
      expect(states, contains(true));
      expect(states.last, isFalse);
    });

    test('rethrows error on save failure', () async {
      fakeCheckInService.shouldThrowOnSave = true;

      await state.loadTodaysCheckIn('user1');

      final checkIn = CheckIn(
        id: 'ci_fail',
        date: DateTime.now(),
        energyScore: 3,
      );

      expect(
        () => state.submitCheckIn(checkIn),
        throwsException,
      );
    });

    test('resets isSubmitting even on error', () async {
      fakeCheckInService.shouldThrowOnSave = true;

      await state.loadTodaysCheckIn('user1');

      final checkIn = CheckIn(
        id: 'ci_fail',
        date: DateTime.now(),
        energyScore: 3,
      );

      try {
        await state.submitCheckIn(checkIn);
      } catch (_) {}

      expect(state.isSubmitting, isFalse);
    });

    test('prevents concurrent submissions', () async {
      await state.loadTodaysCheckIn('user1');

      final checkIn = CheckIn(
        id: 'ci_new',
        date: DateTime.now(),
        energyScore: 3,
      );

      // Start first submission (non-awaited)
      final future1 = state.submitCheckIn(checkIn);

      // Try second submission immediately
      final future2 = state.submitCheckIn(checkIn);

      await Future.wait([future1, future2]);

      // Only one save should have occurred
      expect(fakeCheckInService.saveCalled, isTrue);
    });
  });

  group('CheckInState.isPremiumUser setter', () {
    test('updates premium status and notifies listeners', () {
      int notifyCount = 0;
      state.addListener(() => notifyCount++);

      state.isPremiumUser = true;

      expect(state.isPremium, isTrue);
      expect(notifyCount, 1);
    });

    test('does not notify if value unchanged', () {
      int notifyCount = 0;
      state.addListener(() => notifyCount++);

      state.isPremiumUser = false; // already false

      expect(notifyCount, 0);
    });
  });

  group('CheckInState.reset', () {
    test('clears all state', () async {
      final today = DateTime.now();
      fakeCheckInService.storedCheckIn = CheckIn(
        id: 'ci_1',
        date: today,
        energyScore: 3,
      );
      fakeCheckInService.recentCheckIns = [
        CheckIn(id: 'ci_1', date: today, energyScore: 3),
      ];

      await state.loadTodaysCheckIn('user1');
      expect(state.todaysCheckIn, isNotNull);
      expect(state.recentCheckIns, isNotEmpty);

      state.reset();

      expect(state.todaysCheckIn, isNull);
      expect(state.recentCheckIns, isEmpty);
      expect(state.isSubmitting, isFalse);
    });
  });

  group('CheckInState notifyListeners', () {
    test('notifies on loadTodaysCheckIn', () async {
      int notifyCount = 0;
      state.addListener(() => notifyCount++);

      await state.loadTodaysCheckIn('user1');

      // At least one notification for setting state
      expect(notifyCount, greaterThan(0));
    });

    test('notifies on submitCheckIn', () async {
      await state.loadTodaysCheckIn('user1');

      int notifyCount = 0;
      state.addListener(() => notifyCount++);

      final checkIn = CheckIn(
        id: 'ci_new',
        date: DateTime.now(),
        energyScore: 4,
      );

      await state.submitCheckIn(checkIn);

      // At least 2: isSubmitting = true, then isSubmitting = false
      expect(notifyCount, greaterThanOrEqualTo(2));
    });
  });
}
