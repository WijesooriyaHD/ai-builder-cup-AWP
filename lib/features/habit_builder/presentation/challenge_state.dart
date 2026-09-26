import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../../services/achievement_service.dart';
import '../domain/challenge_models.dart';

/// Outcome of [ChallengeState.logDay].
enum LogDayResult { logged, completed, alreadyLoggedToday, failed }

/// State provider for the Challenge Engine.
///
/// Persists user challenge progress to Firestore:
///   users/{uid}/challenges/{challengeId}
///
/// Falls back gracefully when offline — UI reads from the cached [challenges]
/// list which is populated on [load].
class ChallengeState extends ChangeNotifier {
  final FirebaseFirestore _db;
  static const _uuid = Uuid();

  ChallengeState({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  List<UserChallenge> _challenges = [];
  bool _isLoading = false;
  bool _loaded = false;

  List<UserChallenge> get challenges => _challenges;
  bool get isLoading => _isLoading;

  List<UserChallenge> get activeChallenges =>
      _challenges.where((c) => c.status == ChallengeStatus.active).toList();

  List<UserChallenge> get completedChallenges =>
      _challenges.where((c) => c.status == ChallengeStatus.completed).toList();

  // ---------------------------------------------------------------------------
  // Loading
  // ---------------------------------------------------------------------------

  Future<void> load() async {
    if (_loaded) return;
    _isLoading = true;
    notifyListeners();
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        final snap = await _db
            .collection('users')
            .doc(uid)
            .collection('challenges')
            .orderBy('startDate', descending: true)
            .get();
        _challenges = snap.docs
            .map((d) => UserChallenge.fromFirestore(d.id, d.data()))
            .toList();
        // Auto-evaluate completion for any active challenge past its end date.
        await _evaluateCompletions(uid);
      }
      _loaded = true;
    } catch (e) {
      debugPrint('❌ ChallengeState.load: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Joining a challenge
  // ---------------------------------------------------------------------------

  Future<UserChallenge?> joinChallenge(ChallengeTemplate template) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;

    // Prevent duplicates — check if an active/upcoming instance already exists.
    if (_challenges.any((c) =>
        c.templateId == template.id &&
        (c.status == ChallengeStatus.active ||
            c.status == ChallengeStatus.upcoming))) {
      return null;
    }

    final now = DateTime.now();
    final challenge = UserChallenge(
      id: _uuid.v4(),
      templateId: template.id,
      title: template.title,
      description: template.description,
      goalDescription: template.goalDescription,
      durationDays: template.durationDays,
      category: template.category,
      badge: template.badge,
      xpReward: template.xpReward,
      wellnessPointsReward: template.wellnessPointsReward,
      trophyEmoji: template.trophyEmoji,
      trophyTitle: template.trophyTitle,
      startDate: now,
      endDate: now.add(Duration(days: template.durationDays)),
      daysCompleted: 0,
      status: ChallengeStatus.active,
    );

    try {
      await _db
          .collection('users')
          .doc(uid)
          .collection('challenges')
          .doc(challenge.id)
          .set(challenge.toFirestore());
      _challenges = [challenge, ..._challenges];
      notifyListeners();
      // Persist total joined count for activityPoints / achievement checks.
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('challenge_total_joined', _challenges.length);
      } catch (_) {}
    } catch (e) {
      debugPrint('❌ ChallengeState.joinChallenge: $e');
      return null;
    }
    return challenge;
  }

  // ---------------------------------------------------------------------------
  // Logging a day's progress
  // ---------------------------------------------------------------------------

  /// Result of attempting to log a day's progress.
  ///
  /// - [alreadyLoggedToday]: the daily step was already logged today (rejected).
  /// - [completed]: this log finished the challenge.
  /// - [logged]: a normal successful log (not yet complete).
  /// - [failed]: a persistence error occurred.

  Future<LogDayResult> logDay(String challengeId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return LogDayResult.failed;

    final idx = _challenges.indexWhere((c) => c.id == challengeId);
    if (idx == -1) return LogDayResult.failed;

    final c = _challenges[idx];

    // Enforce one log per calendar day — the daily step can only be completed
    // once per day, so users can't tap "Continue" repeatedly to finish instantly.
    if (c.loggedToday) return LogDayResult.alreadyLoggedToday;

    final now = DateTime.now();
    final newDays = c.daysCompleted + 1;
    final isNowComplete = newDays >= c.durationDays;

    final updated = c.copyWith(
      daysCompleted: newDays,
      lastLoggedDate: now,
      status: isNowComplete ? ChallengeStatus.completed : c.status,
    );
    _challenges[idx] = updated;
    notifyListeners();

    try {
      await _db
          .collection('users')
          .doc(uid)
          .collection('challenges')
          .doc(challengeId)
          .update({
        'daysCompleted': newDays,
        'lastLoggedDate': Timestamp.fromDate(now),
        if (isNowComplete) 'status': ChallengeStatus.completed.name,
      });
    } catch (e) {
      // Revert on failure.
      _challenges[idx] = c;
      notifyListeners();
      debugPrint('❌ ChallengeState.logDay: $e');
      return LogDayResult.failed;
    }
    if (isNowComplete) {
      // Persist total completed count to prefs so activityPoints can read it.
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(
            _completedChallengesKey, completedChallenges.length);
      } catch (_) {}
    }
    return isNowComplete ? LogDayResult.completed : LogDayResult.logged;
  }

  static const String _completedChallengesKey = 'challenge_total_completed';

  // ---------------------------------------------------------------------------
  // Claim rewards
  // ---------------------------------------------------------------------------

  Future<void> claimRewards(String challengeId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final idx = _challenges.indexWhere((c) => c.id == challengeId);
    if (idx == -1) return;
    _challenges[idx] = _challenges[idx].copyWith(rewardsClaimed: true);
    notifyListeners();
    try {
      await _db
          .collection('users')
          .doc(uid)
          .collection('challenges')
          .doc(challengeId)
          .update({'rewardsClaimed': true});
    } catch (e) {
      debugPrint('❌ ChallengeState.claimRewards: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Auto-evaluate completion
  // ---------------------------------------------------------------------------

  Future<void> _evaluateCompletions(String uid) async {
    final toComplete = _challenges.where((c) =>
        c.status == ChallengeStatus.active &&
        DateTime.now().isAfter(c.endDate) &&
        c.daysCompleted >= c.durationDays);

    for (final c in toComplete) {
      final idx = _challenges.indexWhere((x) => x.id == c.id);
      if (idx == -1) continue;
      _challenges[idx] = c.copyWith(status: ChallengeStatus.completed);
      try {
        await _db
            .collection('users')
            .doc(uid)
            .collection('challenges')
            .doc(c.id)
            .update({'status': ChallengeStatus.completed.name});
      } catch (_) {}
    }
  }

  // ---------------------------------------------------------------------------
  // Achievement helpers
  // ---------------------------------------------------------------------------

  /// Checks and returns any newly-unlocked challenge-related achievements
  /// based on the current in-memory challenge list. Screens call this after
  /// joinChallenge() or logDay() to show the AchievementCompletionPage.
  Future<List<Achievement>> checkChallengeAchievements() async {
    return AchievementService().checkAchievements(
      totalChallengesJoined: _challenges.length,
      totalChallengesCompleted: completedChallenges.length,
    );
  }

  // ---------------------------------------------------------------------------
  // AI recommendation hint (heuristic — no API call)
  // ---------------------------------------------------------------------------

  /// Returns a short personalised recommendation string, or null.
  String? get aiRecommendation {
    if (_challenges.isEmpty) return null;

    final active = activeChallenges;

    // Streak-based nudge for active challenges.
    for (final c in active) {
      if (c.daysCompleted >= 5 && c.category == ChallengeCategory.meditation) {
        return 'You\'ve completed ${c.daysCompleted} days of your '
            '${c.title}. Keep the streak alive!';
      }
      if (c.daysCompleted >= 3 && c.category == ChallengeCategory.hydration) {
        return 'Great hydration consistency! You\'re on day '
            '${c.daysCompleted} — you\'re likely to finish this one.';
      }
    }

    // Suggest next challenge based on completed ones.
    final completedIds = completedChallenges.map((c) => c.templateId).toSet();
    if (completedIds.contains('hydration_7') &&
        !active.any((c) => c.templateId == 'meditation_14')) {
      return 'You completed the Hydration Challenge. Try the '
          '14-Day Meditation Challenge next — it pairs perfectly.';
    }

    // Default.
    if (active.isNotEmpty) {
      final c = active.first;
      return 'You\'re ${c.progressPercent}% through the ${c.title}. '
          '${c.daysRemaining} days to go — you\'ve got this!';
    }
    return 'Start a challenge to build lasting wellness habits.';
  }
}
