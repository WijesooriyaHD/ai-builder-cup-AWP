import 'package:aiwellnesspal/services/storage_service.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:convert';

class AchievementService extends ChangeNotifier {
  static final AchievementService _instance = AchievementService._internal();
  factory AchievementService() => _instance;
  AchievementService._internal();

  final List<Achievement> _achievements = [];
  final List<String> _unlockedAchievementIds = [];

  List<Achievement> get achievements => _achievements;
  List<Achievement> get unlockedAchievements =>
      _achievements.where((a) => _unlockedAchievementIds.contains(a.id)).toList();

  int get totalUnlocked => _unlockedAchievementIds.length;

  Future<void> initialize() async {
    _initializeAchievements();
    await _loadUnlockedAchievements();
  }

  void _initializeAchievements() {
    // NOTE: every emoji below is unique across the whole set (no repeats).
    _achievements.addAll([
      // ── Streak (5) ───────────────────────────────────────────────────────────
      Achievement('first_step',    '🌅', 'First Sunrise',     'Complete your first daily check-in',    AchievementType.streak, 1),
      Achievement('week_warrior',  '🧘', 'Mindful Week',      'Complete a full week of check-ins',      AchievementType.streak, 7),
      Achievement('month_master',  '🌳', 'Rooted in Routine', 'Complete 30 days in a row',             AchievementType.streak, 30),
      Achievement('half_century',  '🏔️', 'Inner Strength',    'Maintain a 50-day streak',              AchievementType.streak, 50),
      Achievement('century_club',  '🧗', 'Zen Master',        'Reach a 100-day streak',                AchievementType.streak, 100),

      // ── Points (4) ───────────────────────────────────────────────────────────
      Achievement('point_starter',  '🌾', 'Seeds of Growth', 'Earn your first 100 points',  AchievementType.points, 100),
      Achievement('shining_bright', '☀️', 'Radiant Energy',  'Reach 1,000 points',          AchievementType.points, 1000),
      Achievement('diamond_status', '💎', 'Vibrant Vitality', 'Earn 5,000 points',           AchievementType.points, 5000),
      Achievement('legendary',      '🕉️', 'Enlightened',      'Reach 10,000 points',         AchievementType.points, 10000),

      // ── Intentions / Dreams (5) ──────────────────────────────────────────────
      Achievement('dreamer',          '💭', 'First Intention',    'Set your first wellness intention',       AchievementType.dreams, 1),
      Achievement('goal_setter',      '🎯', 'Intentional Living', 'Set 3 wellness intentions',               AchievementType.dreams, 3),
      Achievement('ambitious',        '🌻', 'Growth Mindset',     'Track 5 wellness intentions',             AchievementType.dreams, 5),
      Achievement('dream_achiever',   '🎊', 'Intention Realized', 'Complete your first wellness intention',  AchievementType.completedDreams, 1),
      Achievement('visionary_master', '🌈', 'Path to Purpose',    'Fully realize 5 wellness intentions',    AchievementType.completedDreams, 5),

      // ── Actions / Micro-actions (4) ──────────────────────────────────────────
      Achievement('first_action',      '👣', 'First Mindful Step', 'Complete your first micro-action',  AchievementType.actions, 1),
      Achievement('action_taker',      '🌼', 'Nurturing Habits',   'Complete 10 micro-actions',         AchievementType.actions, 10),
      Achievement('momentum_builder',  '🌊', 'Flowing Forward',    'Finish 50 micro-actions',           AchievementType.actions, 50),
      Achievement('unstoppable',       '🔆', 'Thriving',           'Complete 100 micro-actions',        AchievementType.actions, 100),

      // ── Journal (4) ──────────────────────────────────────────────────────────
      Achievement('journal_starter', '📓', 'First Reflection',  'Write your first journal entry',  AchievementType.journalEntries, 1),
      Achievement('journal_regular', '🖋️', 'Mindful Journaler', 'Write 10 journal entries',        AchievementType.journalEntries, 10),
      Achievement('journal_legend',  '📚', 'Inner Chronicle',   'Write 100 journal entries',       AchievementType.journalEntries, 100),
      Achievement('todo_master',     '✅', 'Self-Care Champion','Complete 25 todo items',           AchievementType.todoItems, 25),

      // ── Wellness Studio (3) ──────────────────────────────────────────────────
      Achievement('studio_first',   '🎧', 'Studio Debut',    'Complete your first Wellness Studio activity', AchievementType.studioActivities, 1),
      Achievement('studio_regular', '💆', 'Self-Care Ritual', 'Complete 10 Wellness Studio activities',      AchievementType.studioActivities, 10),
      Achievement('studio_devotee', '🏆', 'Wellness Devotee', 'Complete 30 Wellness Studio activities',      AchievementType.studioActivities, 30),

      // ── Special (2) ──────────────────────────────────────────────────────────
      // 'customizer' is unlocked by AppState.setWellnessTheme / setThemeColor.
      Achievement('customizer', '🎨', 'Made It Yours',    'Change your app theme',    AchievementType.special, 1),
      Achievement('pro_access', '🌟', 'Premium Wellbeing','Upgrade to Premium',       AchievementType.special, 1),

      // ── Level (2) ────────────────────────────────────────────────────────────
      Achievement('level_5',  '🌿', 'Growing Strong', 'Reach level 5',  AchievementType.level, 5),
      Achievement('level_20', '🦋', 'Wellness Sage',  'Reach level 20', AchievementType.level, 20),

      // ── Habits (4) ───────────────────────────────────────────────────────────
      Achievement('habit_first',    '🔔', 'Habit Formed',     'Create your first wellness habit',         AchievementType.habits, 1),
      Achievement('habit_builder',  '🏗️', 'Habit Builder',    'Set up 5 active wellness habits',          AchievementType.habits, 5),
      Achievement('habit_week',     '🗓️', 'Seven-Day Streak', 'Complete 7 habit check-offs in total',     AchievementType.habitCompletions, 7),
      Achievement('habit_champion', '🥇', 'Habit Champion',   'Complete 30 habit check-offs in total',    AchievementType.habitCompletions, 30),

      // ── Challenges (3) ───────────────────────────────────────────────────────
      Achievement('challenge_first',    '⚡', 'Challenge Accepted', 'Join your first wellness challenge',       AchievementType.challengesJoined, 1),
      Achievement('challenge_finisher', '🎖️', 'Challenge Finisher', 'Complete your first wellness challenge',  AchievementType.challengesCompleted, 1),
      Achievement('challenge_master',   '🏅', 'Challenge Master',   'Complete 3 wellness challenges',           AchievementType.challengesCompleted, 3),

      // ── Reflection (1) ───────────────────────────────────────────────────────
      // Unlocked when the user generates their first Live Pal reflection.
      Achievement('first_reflection', '💬', 'Inner Voice', 'Generate your first Live Pal reflection', AchievementType.special, 1),

      // ── Meditation & Mindfulness (7) ─────────────────────────────────────────
      // These are unlocked externally by MeditationState via
      // unlockSpecialAchievement(); the service mirrors and persists them so
      // they appear in the global Achievements screen.
      Achievement('med_first_session',    '🌱', 'First Breath',        'Complete your very first meditation session',          AchievementType.meditation, 1),
      Achievement('med_streak_7',         '🕯️', '7-Day Practice',      'Sit in stillness 7 days in a row',                    AchievementType.meditation, 7),
      Achievement('med_streak_30',        '🌲', 'Deep Roots',          'Sustain a daily meditation practice for 30 days',     AchievementType.meditation, 30),
      Achievement('med_minutes_100',      '⏳', '100 Mindful Minutes', 'Accumulate 100 minutes of meditation practice',       AchievementType.meditation, 100),
      Achievement('med_breathing_master', '🌬️', 'Breath Master',       'Complete 10 dedicated breathing sessions',            AchievementType.meditation, 10),
      Achievement('med_explorer',         '🔭', 'Meditation Explorer', 'Experience 4 different types of meditation',          AchievementType.meditation, 4),
      Achievement('med_champion',         '👑', 'Meditation Champion', 'Complete 50 meditation sessions',                     AchievementType.meditation, 50),
    ]);
  }

  Future<void> _loadUnlockedAchievements() async {
    final prefs = await SharedPreferences.getInstance();
    final unlockedJson = prefs.getString('unlocked_achievements');
    if (unlockedJson != null) {
      _unlockedAchievementIds.clear();
      _unlockedAchievementIds
          .addAll(List<String>.from(json.decode(unlockedJson)));
    }
  }

  Future<void> _saveUnlockedAchievements() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'unlocked_achievements', json.encode(_unlockedAchievementIds));
  }

  /// Check and unlock achievements based on current user stats.
  ///
  /// Returns the list of achievements that are *newly* unlocked by this call.
  Future<List<Achievement>> checkAchievements({
    int? currentStreak,
    int? totalPoints,
    int? totalDreams,
    int? completedActions,
    int? completedDreams,
    int? totalCheckIns,
    int? currentLevel,
    int? journalEntries,
    int? todoItems,
    int? studioActivitiesCompleted,
    bool? isPro,
    // ── Habits ──────────────────────────────────────────────────────────────
    /// Total number of habits the user has ever created (active + inactive).
    int? totalHabits,
    /// Total all-time habit check-offs across all habits and all days.
    int? totalHabitCompletions,
    // ── Challenges ──────────────────────────────────────────────────────────
    /// Total challenges the user has ever joined.
    int? totalChallengesJoined,
    /// Total challenges the user has completed.
    int? totalChallengesCompleted,
  }) async {
    final newlyUnlocked = <Achievement>[];
    bool hasChanges = false;

    for (final achievement in _achievements) {
      bool shouldBeUnlocked = false;

      switch (achievement.type) {
        case AchievementType.streak:
          shouldBeUnlocked = (currentStreak ?? 0) >= achievement.requirement;
          break;
        case AchievementType.points:
          shouldBeUnlocked = (totalPoints ?? 0) >= achievement.requirement;
          break;
        case AchievementType.dreams:
          shouldBeUnlocked = (totalDreams ?? 0) >= achievement.requirement;
          break;
        case AchievementType.actions:
          shouldBeUnlocked = (completedActions ?? 0) >= achievement.requirement;
          break;
        case AchievementType.completedDreams:
          shouldBeUnlocked = (completedDreams ?? 0) >= achievement.requirement;
          break;
        case AchievementType.level:
          shouldBeUnlocked = (currentLevel ?? 0) >= achievement.requirement;
          break;
        case AchievementType.journalEntries:
          shouldBeUnlocked = (journalEntries ?? 0) >= achievement.requirement;
          break;
        case AchievementType.todoItems:
          shouldBeUnlocked = (todoItems ?? 0) >= achievement.requirement;
          break;
        case AchievementType.studioActivities:
          shouldBeUnlocked =
              (studioActivitiesCompleted ?? 0) >= achievement.requirement;
          break;
        case AchievementType.special:
          if (achievement.id == 'pro_access') {
            shouldBeUnlocked = isPro ?? false;
          } else {
            // Other special badges (e.g. 'customizer') are unlocked externally
            // via unlockSpecialAchievement(). Preserve any already-stored
            // unlock so a re-check doesn't accidentally revoke them.
            shouldBeUnlocked =
                _unlockedAchievementIds.contains(achievement.id);
          }
          break;
        case AchievementType.meditation:
          // Unlocked externally by MeditationState — preserve stored state.
          shouldBeUnlocked =
              _unlockedAchievementIds.contains(achievement.id);
          break;
        case AchievementType.habits:
          shouldBeUnlocked = (totalHabits ?? 0) >= achievement.requirement;
          break;
        case AchievementType.habitCompletions:
          shouldBeUnlocked =
              (totalHabitCompletions ?? 0) >= achievement.requirement;
          break;
        case AchievementType.challengesJoined:
          shouldBeUnlocked =
              (totalChallengesJoined ?? 0) >= achievement.requirement;
          break;
        case AchievementType.challengesCompleted:
          shouldBeUnlocked =
              (totalChallengesCompleted ?? 0) >= achievement.requirement;
          break;
      }

      final isCurrentlyUnlocked =
          _unlockedAchievementIds.contains(achievement.id);

      if (shouldBeUnlocked && !isCurrentlyUnlocked) {
        _unlockedAchievementIds.add(achievement.id);
        newlyUnlocked.add(achievement);
        hasChanges = true;
      }
    }

    if (hasChanges) {
      await _saveUnlockedAchievements();
      await StorageService()
          .saveUnlockedAchievementsToCloud(_unlockedAchievementIds);
      notifyListeners();
    }

    // Hooked here rather than at the ~19 call sites: this is the single place
    // an achievement can transition to unlocked, so celebrating here means no
    // caller can forget to, and none can double-celebrate.
    for (final achievement in newlyUnlocked) {
      onAchievementUnlocked?.call(achievement);
    }

    return newlyUnlocked;
  }

  /// Invoked once per newly-unlocked achievement.
  ///
  /// Wired in `main.dart` to the engagement system, which decides whether that
  /// becomes an in-app celebration or a notification. A callback rather than a
  /// direct import so this service keeps no dependency on notifications.
  void Function(Achievement achievement)? onAchievementUnlocked;

  /// Manually unlock a special achievement (e.g. 'customizer', meditation
  /// badges). No-op if already unlocked.
  Future<void> unlockSpecialAchievement(String achievementId) async {
    if (!_unlockedAchievementIds.contains(achievementId)) {
      _unlockedAchievementIds.add(achievementId);
      await _saveUnlockedAchievements();
      await StorageService()
          .saveUnlockedAchievementsToCloud(_unlockedAchievementIds);
      notifyListeners();
    }
  }

  bool isUnlocked(String achievementId) =>
      _unlockedAchievementIds.contains(achievementId);
}

// ────────────────────────────────────────────────────────────────────────────
// Achievement model
// ────────────────────────────────────────────────────────────────────────────

class Achievement {
  final String id;
  final String emoji;
  final String name;
  final String description;
  final AchievementType type;
  final int requirement;

  const Achievement(this.id, this.emoji, this.name, this.description,
      this.type, this.requirement);

  String get requirementText {
    switch (type) {
      case AchievementType.streak:
        return '$requirement-day streak';
      case AchievementType.points:
        return '$requirement points';
      case AchievementType.dreams:
        return '$requirement ${requirement == 1 ? 'intention' : 'intentions'}';
      case AchievementType.actions:
        return '$requirement ${requirement == 1 ? 'action' : 'actions'}';
      case AchievementType.completedDreams:
        return 'Complete $requirement '
            '${requirement == 1 ? 'intention' : 'intentions'}';
      case AchievementType.level:
        return 'Level $requirement';
      case AchievementType.journalEntries:
        return 'Write $requirement ${requirement == 1 ? 'entry' : 'entries'}';
      case AchievementType.todoItems:
        return 'Complete $requirement todo '
            '${requirement == 1 ? 'item' : 'items'}';
      case AchievementType.studioActivities:
        return 'Complete $requirement studio '
            '${requirement == 1 ? 'activity' : 'activities'}';
      case AchievementType.special:
        return 'Special action';
      case AchievementType.meditation:
        return 'Meditation practice';
      case AchievementType.habits:
        return '$requirement ${requirement == 1 ? 'habit' : 'habits'}';
      case AchievementType.habitCompletions:
        return '$requirement habit '
            '${requirement == 1 ? 'check-off' : 'check-offs'}';
      case AchievementType.challengesJoined:
        return '$requirement ${requirement == 1 ? 'challenge' : 'challenges'} joined';
      case AchievementType.challengesCompleted:
        return 'Complete $requirement '
            '${requirement == 1 ? 'challenge' : 'challenges'}';
    }
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Achievement type enum
// ────────────────────────────────────────────────────────────────────────────

enum AchievementType {
  streak,
  points,
  dreams,
  actions,
  completedDreams,
  level,
  journalEntries,
  todoItems,
  studioActivities,
  special,
  /// Meditation & Mindfulness badges — unlocked externally by MeditationState
  /// via [AchievementService.unlockSpecialAchievement].
  meditation,
  /// Habit badges — based on how many habits the user has created/active.
  habits,
  /// Habit-completion badges — based on total all-time habit check-offs.
  habitCompletions,
  /// Challenge-join badges.
  challengesJoined,
  /// Challenge-completion badges.
  challengesCompleted,
}
