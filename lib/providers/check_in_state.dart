import 'package:flutter/foundation.dart';

import '../models/check_in.dart';
import '../models/wellness_enums.dart';
import '../models/user_behavior_profile.dart';
import '../services/check_in_service.dart';
import '../services/personalization_service.dart';
import '../services/notification_service.dart';

/// State provider for the daily wellness check-in flow.
///
/// Manages today's check-in status, recent check-in history (for pre-fill),
/// and the submission lifecycle. Uses [CheckInService] for persistence and
/// [PersonalizationService] for computing pre-fill values and updating
/// the user's behavior profile.
class CheckInState extends ChangeNotifier {
  final CheckInService _checkInService;
  final PersonalizationService _personalizationService;

  CheckIn? _todaysCheckIn;
  List<CheckIn> _recentCheckIns = [];
  bool _isSubmitting = false;
  bool _isPremium = false;
  String? _userId;

  /// Creates a [CheckInState] with the required services.
  ///
  /// The [isPremium] flag controls whether pre-fill values are available
  /// (requires Premium + >= 14 check-ins per Requirement 2.10 / 11.3).
  CheckInState({
    required CheckInService checkInService,
    required PersonalizationService personalizationService,
    bool isPremium = false,
  })  : _checkInService = checkInService,
        _personalizationService = personalizationService,
        _isPremium = isPremium;

  // ---------------------------------------------------------------------------
  // Getters
  // ---------------------------------------------------------------------------

  /// The check-in completed today, or null if no check-in has been submitted.
  CheckIn? get todaysCheckIn => _todaysCheckIn;

  /// The most recent check-ins (up to 14), ordered most-recent-first.
  List<CheckIn> get recentCheckIns => _recentCheckIns;

  /// Whether a check-in submission is currently in progress.
  bool get isSubmitting => _isSubmitting;

  /// Whether the user has a Premium subscription.
  bool get isPremium => _isPremium;

  /// Whether the user has already checked in today.
  ///
  /// Compares the stored check-in date to today in the user's local timezone.
  /// Requirements: 2.1
  bool get hasCheckedInToday {
    if (_todaysCheckIn == null) return false;

    final now = DateTime.now();
    final checkInDate = _todaysCheckIn!.date.toLocal();

    return checkInDate.year == now.year &&
        checkInDate.month == now.month &&
        checkInDate.day == now.day;
  }

  /// Returns pre-filled check-in values when the user qualifies.
  ///
  /// Qualification: at least 14 recent check-ins AND user is Premium.
  /// Returns the result of [PersonalizationService.computePrefill] when
  /// qualified, or null otherwise.
  /// Requirements: 2.10, 11.3
  CheckIn? get prefillValues {
    if (_recentCheckIns.length < 14) return null;
    if (!_isPremium) return null;

    return _personalizationService.computePrefill(_recentCheckIns);
  }

  // ---------------------------------------------------------------------------
  // Setters
  // ---------------------------------------------------------------------------

  /// Updates the premium status. Call this when subscription state changes.
  set isPremiumUser(bool value) {
    if (_isPremium != value) {
      _isPremium = value;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Public methods
  // ---------------------------------------------------------------------------

  /// Loads today's check-in for the given user.
  ///
  /// Strategy: check local SharedPreferences cache first (fast), then
  /// query Firestore for authoritative data. Also loads recent check-ins
  /// for pre-fill computation.
  /// Requirements: 2.1
  Future<void> loadTodaysCheckIn(String userId) async {
    _userId = userId;

    // 1. Try loading from local cache first (fast path)
    final cachedCheckIn = await _checkInService.loadCachedCheckIn();
    if (cachedCheckIn != null) {
      _todaysCheckIn = cachedCheckIn;
      notifyListeners();
    }

    // 2. Load from Firestore for authoritative data
    final today = DateTime.now();
    final firestoreCheckIn =
        await _checkInService.loadCheckInForDate(userId, today);

    if (firestoreCheckIn != null) {
      _todaysCheckIn = firestoreCheckIn;
    } else if (cachedCheckIn == null) {
      // Neither cache nor Firestore check_ins has today's check-in.
      // Fall back to the user's root doc only if the stored data is
      // from today (survives app reinstall since it's in Firestore).
      final latestFromDoc = await _checkInService.loadLatestFromUserDoc(userId);
      if (latestFromDoc != null && _isToday(latestFromDoc.date)) {
        _todaysCheckIn = latestFromDoc;
      } else {
        // Data is stale or doesn't exist — leave null so check-in is prompted
        _todaysCheckIn = null;
      }
    }

    // 4. Load recent check-ins for pre-fill
    _recentCheckIns = await _checkInService.loadRecentCheckIns(userId);

    // 5. Schedule or cancel the daily notification based on check-in status
    try {
      if (_todaysCheckIn == null) {
        // No check-in today — schedule a 6pm reminder
        await NotificationService().scheduleDailyCheckInReminder();
      } else {
        // Already checked in — ensure no lingering notification
        await NotificationService().cancelDailyCheckInReminder();
      }
    } catch (e) {
      debugPrint('CheckInState: Notification scheduling error: $e');
    }

    notifyListeners();
  }

  /// Submits a completed check-in.
  ///
  /// Saves via [CheckInService], updates the user's behavior profile via
  /// [PersonalizationService], and sets the local state.
  /// Requirements: 2.6, 11.1
  Future<void> submitCheckIn(CheckIn checkIn) async {
    if (_isSubmitting) return;
    assert(_userId != null, 'loadTodaysCheckIn must be called before submitCheckIn');

    _isSubmitting = true;
    notifyListeners();

    try {
      final userId = _userId!;

      // 1. Save the check-in (Firestore + local cache)
      await _checkInService.saveCheckIn(userId, checkIn);

      // 2. Update local state
      _todaysCheckIn = checkIn;

      // 3. Update recent check-ins list (prepend and cap at 14)
      _recentCheckIns = [checkIn, ..._recentCheckIns];
      if (_recentCheckIns.length > 14) {
        _recentCheckIns = _recentCheckIns.sublist(0, 14);
      }

      // 4. Update behavior profile
      await _updateBehaviorProfile(userId, checkIn);

      // 5. Cancel the daily check-in reminder notification
      try {
        await NotificationService().cancelDailyCheckInReminder();
      } catch (e) {
        debugPrint('CheckInState: Failed to cancel notification: $e');
      }
    } catch (e) {
      debugPrint('CheckInState.submitCheckIn error: $e');
      rethrow;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  /// Updates today's check-in energy score, recovery status, and/or available
  /// time and persists it (Firestore + local cache).
  ///
  /// If no check-in exists yet for today, a new one is created. Returns the
  /// updated [CheckIn] so callers can immediately regenerate a plan from it.
  Future<CheckIn> updateEnergyAndRecovery({
    int? energyScore,
    RecoveryStatus? recoveryStatus,
    AvailableTimeRange? availableTime,
  }) async {
    final base = _todaysCheckIn ??
        CheckIn(
          id: 'checkin_${DateTime.now().millisecondsSinceEpoch}',
          date: DateTime.now(),
        );

    // Remove any updated fields from skippedFields.
    final skipped = List<String>.from(base.skippedFields);
    if (energyScore != null) skipped.remove('energyScore');
    if (recoveryStatus != null) skipped.remove('recoveryStatus');
    if (availableTime != null) skipped.remove('availableTime');

    final updated = base.copyWith(
      energyScore: energyScore,
      recoveryStatus: recoveryStatus,
      availableTime: availableTime,
      skippedFields: skipped,
    );

    _todaysCheckIn = updated;
    notifyListeners();

    if (_userId != null) {
      try {
        await _checkInService.saveCheckIn(_userId!, updated);
      } catch (e) {
        debugPrint('CheckInState.updateEnergyAndRecovery save error: $e');
      }
    }
    return updated;
  }

  /// Handles the case where a user exits the check-in without completing it.
  ///
  /// Uses the most recent stored check-in (or creates an empty one) and
  /// sets it as today's check-in so plan generation can proceed.
  /// The UI should show a 4-second non-overlay banner after calling this.
  /// Requirements: 2.9
  Future<void> skipCheckIn() async {
    if (_todaysCheckIn != null) return; // Already has today's check-in

    CheckIn fallbackCheckIn;

    if (_recentCheckIns.isNotEmpty) {
      // Use most recent stored check-in values
      final last = _recentCheckIns.first;
      fallbackCheckIn = CheckIn(
        id: '${last.id}_reused_${DateTime.now().millisecondsSinceEpoch}',
        date: DateTime.now(),
        energyScore: last.energyScore,
        moodState: last.moodState,
        recoveryStatus: last.recoveryStatus,
        availableTime: last.availableTime,
        skippedFields: ['energyScore', 'moodState', 'recoveryStatus', 'availableTime'],
      );
    } else {
      // No prior check-in exists — pass empty check-in data
      fallbackCheckIn = CheckIn(
        id: 'empty_${DateTime.now().millisecondsSinceEpoch}',
        date: DateTime.now(),
        skippedFields: ['energyScore', 'moodState', 'recoveryStatus', 'availableTime'],
      );
    }

    _todaysCheckIn = fallbackCheckIn;
    notifyListeners();

    // Persist the fallback check-in
    if (_userId != null) {
      try {
        await _checkInService.saveCheckIn(_userId!, fallbackCheckIn);
      } catch (e) {
        debugPrint('CheckInState.skipCheckIn save error: $e');
      }
    }
  }

  /// Resets state — useful on sign-out or user switch.
  void reset() {
    _todaysCheckIn = null;
    _recentCheckIns = [];
    _isSubmitting = false;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Updates the user's behavior profile with the new check-in data.
  Future<void> _updateBehaviorProfile(String userId, CheckIn checkIn) async {
    try {
      // Load existing profile
      final existingProfile =
          await _personalizationService.loadProfile(userId);

      final profile = existingProfile ??
          UserBehaviorProfile(userId: userId, totalCheckIns: 0);

      // Increment total check-ins and update field value counts
      final updatedFieldCounts =
          Map<String, Map<String, int>>.from(
            profile.fieldValueCounts.map(
              (key, value) => MapEntry(key, Map<String, int>.from(value)),
            ),
          );

      _incrementFieldCount(updatedFieldCounts, 'energyScore',
          checkIn.energyScore?.toString());
      _incrementFieldCount(
          updatedFieldCounts, 'moodState', checkIn.moodState?.name);
      _incrementFieldCount(
          updatedFieldCounts, 'recoveryStatus', checkIn.recoveryStatus?.name);
      _incrementFieldCount(
          updatedFieldCounts, 'availableTime', checkIn.availableTime?.name);

      final updatedProfile = UserBehaviorProfile(
        userId: userId,
        totalCheckIns: profile.totalCheckIns + 1,
        fieldValueCounts: updatedFieldCounts,
        actionCategorySkipCounts: profile.actionCategorySkipCounts,
        actionCategoryCompleteCounts: profile.actionCategoryCompleteCounts,
        actionCategoryWeights: profile.actionCategoryWeights,
        deprioritizedCategories: profile.deprioritizedCategories,
        lastUpdated: DateTime.now(),
      );

      await _personalizationService.updateProfile(userId, updatedProfile);
    } catch (e) {
      // Non-critical: log but don't fail the check-in submission
      debugPrint('CheckInState._updateBehaviorProfile error: $e');
    }
  }

  /// Increments the count for a field value in the field-value counts map.
  void _incrementFieldCount(
    Map<String, Map<String, int>> fieldCounts,
    String fieldName,
    String? value,
  ) {
    if (value == null) return;

    fieldCounts.putIfAbsent(fieldName, () => {});
    final valueCounts = fieldCounts[fieldName]!;
    valueCounts[value] = (valueCounts[value] ?? 0) + 1;
  }

  /// Returns true if the given [date] is today in the local timezone.
  bool _isToday(DateTime date) {
    final now = DateTime.now();
    final local = date.toLocal();
    return local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
  }
}
