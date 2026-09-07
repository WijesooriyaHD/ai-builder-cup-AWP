import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/app_state.dart';
import '../providers/check_in_state.dart';
import '../providers/wellness_plan_state.dart';
import '../services/ai_service.dart';
import '../utils/pro_modal_utils.dart';
import '../widgets/frosted_container.dart';
import 'breathing_exercise_screen.dart';
import 'wellness_quiz_screen.dart';

/// A single activity available in the Wellness Studio.
class WellnessStudioActivity {
  final String id;
  final String title;
  final String category;
  final int durationMinutes;
  final bool isFree;
  bool isCompleted;

  WellnessStudioActivity({
    required this.id,
    required this.title,
    required this.category,
    required this.durationMinutes,
    required this.isFree,
    this.isCompleted = false,
  });
}

/// Wellness Studio screen replacing She Stacks Arcade.
///
/// Provides 6 category tabs with activity cards. Free tier has ≥3 activities
/// per category; locked activities show an upgrade prompt on tap.
///
/// Requirements: 6.1, 6.2, 6.3, 6.4, 6.7, 6.8
class WellnessStudioScreen extends StatefulWidget {
  /// Optional initial category to open directly on (e.g. 'Breathing Exercises').
  /// If null or not found, defaults to the first tab.
  final String? initialCategory;

  const WellnessStudioScreen({super.key, this.initialCategory});

  @override
  State<WellnessStudioScreen> createState() => _WellnessStudioScreenState();
}

class _WellnessStudioScreenState extends State<WellnessStudioScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const List<String> _categories = [
    'Breathing Exercises',
    'Recovery Challenges',
    'Mindfulness Sessions',
    'Wellness Quizzes',
    'Pilates Knowledge Cards',
    'Stress Recovery Activities',
  ];

  static const Map<String, IconData> _categoryIcons = {
    'Breathing Exercises': Icons.air_rounded,
    'Recovery Challenges': Icons.fitness_center_rounded,
    'Mindfulness Sessions': Icons.self_improvement_rounded,
    'Wellness Quizzes': Icons.quiz_rounded,
    'Pilates Knowledge Cards': Icons.style_rounded,
    'Stress Recovery Activities': Icons.spa_rounded,
  };

  /// Maps studio categories to DailyPlan focus keywords for "Recommended" badge.
  static const Map<String, List<String>> _categoryFocusKeywords = {
    'Breathing Exercises': ['breathing', 'breath', 'stress', 'calm'],
    'Recovery Challenges': ['recovery', 'restore', 'gentle'],
    'Mindfulness Sessions': ['mindfulness', 'mindful', 'mental clarity'],
    'Wellness Quizzes': ['knowledge', 'wellness', 'general'],
    'Pilates Knowledge Cards': ['pilates', 'flexibility', 'movement'],
    'Stress Recovery Activities': ['stress', 'recovery', 'calm', 'restore'],
  };

  late Map<String, List<WellnessStudioActivity>> _activitiesByCategory;
  Set<String> _completedActivityIds = {};

  // --- Personalized (AI) recommendations state ---
  static const String _recsCacheKey = 'wellness_studio_ai_recs';
  static const String _recsCacheDateKey = 'wellness_studio_ai_recs_date';
  // Daily cap on how many AI picks can earn engagement points, to prevent
  // gaming via repeated refreshes.
  static const int _aiPointsDailyCap = 3;
  static const String _aiPointsCountKey = 'wellness_studio_ai_points_count';
  static const String _aiPointsDateKey = 'wellness_studio_ai_points_date';
  final AIService _aiService = AIService();
  List<Map<String, dynamic>> _aiRecommendations = [];
  bool _isLoadingRecs = false;
  bool _recsLoaded = false;

  /// Deterministic id for an AI pick so completion state is stable across
  /// refreshes and the same suggestion is never counted twice.
  String _aiActivityId(String title, String category) {
    final key = '${title.trim().toLowerCase()}|${category.trim().toLowerCase()}';
    return 'ai_${key.hashCode.toUnsigned(32).toRadixString(16)}';
  }

  @override
  void initState() {
    super.initState();
    // Open on the requested category if provided, else the first tab.
    final initialIndex = widget.initialCategory != null
        ? _categories.indexOf(widget.initialCategory!)
        : -1;
    _tabController = TabController(
      length: _categories.length,
      vsync: this,
      initialIndex: initialIndex >= 0 ? initialIndex : 0,
    );
    _activitiesByCategory = _buildActivities();
    _loadCompletionState();
    // Defer so providers are available.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadRecommendations();
    });
  }

  String _todayKey() => DateTime.now().toIso8601String().split('T').first;

  /// Loads personalized recommendations for Pro users: uses today's cache if
  /// present, otherwise generates a fresh set from the user's recent journey.
  Future<void> _loadRecommendations() async {
    if (!mounted) return;
    final appState = context.read<AppState>();
    if (!appState.isPro) return; // Free users see a locked teaser instead.

    final prefs = await SharedPreferences.getInstance();
    final cachedDate = prefs.getString(_recsCacheDateKey);
    final cachedRaw = prefs.getString(_recsCacheKey);

    // Use today's cache if available.
    if (cachedDate == _todayKey() && cachedRaw != null) {
      try {
        final decoded = jsonDecode(cachedRaw) as List<dynamic>;
        setState(() {
          _aiRecommendations =
              decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _recsLoaded = true;
        });
        return;
      } catch (_) {
        // Fall through to regenerate on cache corruption.
      }
    }

    if (!mounted) return;
    setState(() => _isLoadingRecs = true);

    final planState = context.read<WellnessPlanState>();
    final checkInState = context.read<CheckInState>();

    final recs = await _aiService.generateStudioRecommendations(
      checkIn: checkInState.todaysCheckIn,
      recentPlans: [
        if (planState.todaysPlan != null) planState.todaysPlan!,
        ...planState.recentPlans,
      ],
      intentions: appState.intentions,
    );

    // Cache today's result (even if empty, to avoid repeated calls today).
    try {
      await prefs.setString(_recsCacheKey, jsonEncode(recs));
      await prefs.setString(_recsCacheDateKey, _todayKey());
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _aiRecommendations = recs;
      _isLoadingRecs = false;
      _recsLoaded = true;
    });
  }

  /// Forces a fresh regeneration (bypasses today's cache).
  Future<void> _refreshRecommendations() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_recsCacheDateKey);
    await prefs.remove(_recsCacheKey);
    setState(() => _recsLoaded = false);
    await _loadRecommendations();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Loads completion state from SharedPreferences.
  Future<void> _loadCompletionState() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('wellness_studio_completions');
    if (raw != null) {
      final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
      setState(() {
        _completedActivityIds = decoded.cast<String>().toSet();
        for (final category in _activitiesByCategory.values) {
          for (final activity in category) {
            if (_completedActivityIds.contains(activity.id)) {
              activity.isCompleted = true;
            }
          }
        }
      });
    }
  }

  /// Persists completion state to SharedPreferences.
  Future<void> _saveCompletionState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'wellness_studio_completions',
      jsonEncode(_completedActivityIds.toList()),
    );
  }

  /// Builds the curated activity catalog. ≥3 free activities per category.
  Map<String, List<WellnessStudioActivity>> _buildActivities() {
    return {
      'Breathing Exercises': [
        WellnessStudioActivity(id: 'breath_1', title: 'Box Breathing', category: 'Breathing Exercises', durationMinutes: 5, isFree: true),
        WellnessStudioActivity(id: 'breath_2', title: '4-7-8 Calm Breath', category: 'Breathing Exercises', durationMinutes: 4, isFree: true),
        WellnessStudioActivity(id: 'breath_3', title: 'Morning Energize Breathwork', category: 'Breathing Exercises', durationMinutes: 6, isFree: true),
        WellnessStudioActivity(id: 'breath_4', title: 'Deep Belly Breathing', category: 'Breathing Exercises', durationMinutes: 5, isFree: false),
        WellnessStudioActivity(id: 'breath_5', title: 'Alternate Nostril Breathing', category: 'Breathing Exercises', durationMinutes: 7, isFree: false),
      ],
      'Recovery Challenges': [
        WellnessStudioActivity(id: 'recov_1', title: '5-Minute Stretch Reset', category: 'Recovery Challenges', durationMinutes: 5, isFree: true),
        WellnessStudioActivity(id: 'recov_2', title: 'Gentle Foam Roll', category: 'Recovery Challenges', durationMinutes: 8, isFree: true),
        WellnessStudioActivity(id: 'recov_3', title: 'Active Recovery Walk', category: 'Recovery Challenges', durationMinutes: 10, isFree: true),
        WellnessStudioActivity(id: 'recov_4', title: 'Joint Mobility Flow', category: 'Recovery Challenges', durationMinutes: 12, isFree: false),
        WellnessStudioActivity(id: 'recov_5', title: 'Post-Workout Cool Down', category: 'Recovery Challenges', durationMinutes: 7, isFree: false),
      ],
      'Mindfulness Sessions': [
        WellnessStudioActivity(id: 'mind_1', title: 'Body Scan Meditation', category: 'Mindfulness Sessions', durationMinutes: 8, isFree: true),
        WellnessStudioActivity(id: 'mind_2', title: 'Gratitude Check-In', category: 'Mindfulness Sessions', durationMinutes: 5, isFree: true),
        WellnessStudioActivity(id: 'mind_3', title: 'Mindful Observation', category: 'Mindfulness Sessions', durationMinutes: 4, isFree: true),
        WellnessStudioActivity(id: 'mind_4', title: 'Loving-Kindness Meditation', category: 'Mindfulness Sessions', durationMinutes: 10, isFree: false),
        WellnessStudioActivity(id: 'mind_5', title: 'Evening Wind-Down', category: 'Mindfulness Sessions', durationMinutes: 12, isFree: false),
      ],
      'Wellness Quizzes': [
        WellnessStudioActivity(id: 'quiz_1', title: 'Stress Awareness Quiz', category: 'Wellness Quizzes', durationMinutes: 3, isFree: true),
        WellnessStudioActivity(id: 'quiz_2', title: 'Sleep Hygiene Check', category: 'Wellness Quizzes', durationMinutes: 4, isFree: true),
        WellnessStudioActivity(id: 'quiz_3', title: 'Recovery Knowledge Test', category: 'Wellness Quizzes', durationMinutes: 3, isFree: true),
        WellnessStudioActivity(id: 'quiz_4', title: 'Nutrition & Hydration Quiz', category: 'Wellness Quizzes', durationMinutes: 5, isFree: false),
        WellnessStudioActivity(id: 'quiz_5', title: 'Mindfulness Mastery Quiz', category: 'Wellness Quizzes', durationMinutes: 4, isFree: false),
      ],
      'Pilates Knowledge Cards': [
        WellnessStudioActivity(id: 'pilates_1', title: 'Core Principles', category: 'Pilates Knowledge Cards', durationMinutes: 3, isFree: true),
        WellnessStudioActivity(id: 'pilates_2', title: 'Breath & Movement', category: 'Pilates Knowledge Cards', durationMinutes: 4, isFree: true),
        WellnessStudioActivity(id: 'pilates_3', title: 'Alignment Basics', category: 'Pilates Knowledge Cards', durationMinutes: 3, isFree: true),
        WellnessStudioActivity(id: 'pilates_4', title: 'Advanced Techniques', category: 'Pilates Knowledge Cards', durationMinutes: 5, isFree: false),
        WellnessStudioActivity(id: 'pilates_5', title: 'Reformer Foundations', category: 'Pilates Knowledge Cards', durationMinutes: 6, isFree: false),
      ],
      'Stress Recovery Activities': [
        WellnessStudioActivity(id: 'stress_1', title: 'Progressive Muscle Relaxation', category: 'Stress Recovery Activities', durationMinutes: 7, isFree: true),
        WellnessStudioActivity(id: 'stress_2', title: 'Guided Visualization', category: 'Stress Recovery Activities', durationMinutes: 6, isFree: true),
        WellnessStudioActivity(id: 'stress_3', title: 'Tension Release Tapping', category: 'Stress Recovery Activities', durationMinutes: 5, isFree: true),
        WellnessStudioActivity(id: 'stress_4', title: 'Nature Sound Immersion', category: 'Stress Recovery Activities', durationMinutes: 10, isFree: false),
        WellnessStudioActivity(id: 'stress_5', title: 'Journaling for Calm', category: 'Stress Recovery Activities', durationMinutes: 8, isFree: false),
      ],
    };
  }

  /// Checks if a category matches the current DailyPlan focus (Req 6.8).
  bool _isRecommendedForToday(String category) {
    final planState = context.read<WellnessPlanState>();
    final todaysFocus = planState.todaysPlan?.todaysFocus;
    if (todaysFocus == null) return false;

    final keywords = _categoryFocusKeywords[category] ?? [];
    final focusLower = todaysFocus.toLowerCase();
    return keywords.any((keyword) => focusLower.contains(keyword));
  }

  /// Attempts to write a start record to Firestore (Req 6.2).
  /// Continues session even if the write fails.
  Future<void> _recordActivityStart(WellnessStudioActivity activity) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('wellness_studio_sessions')
          .doc(activity.id)
          .set({
        'activityId': activity.id,
        'startTimestamp': FieldValue.serverTimestamp(),
        'duration': activity.durationMinutes,
        'category': activity.category,
      }, SetOptions(merge: true));
    } catch (e) {
      // Non-blocking: continue session on failure (Req 6.2)
      debugPrint('⚠️ WellnessStudio: start record write failed: $e');
    }
  }

  /// Awards 1 engagement point and checks milestones on completion (Req 6.3).
  /// Retries Firestore on next app open if write fails.
  Future<void> _recordActivityCompletion(WellnessStudioActivity activity) async {
    setState(() {
      activity.isCompleted = true;
      _completedActivityIds.add(activity.id);
    });
    await _saveCompletionState();

    // Show locally earned point immediately
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('🌟 +1 engagement point earned!'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }

    // Attempt Firestore write for point + milestone
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final userRef = FirebaseFirestore.instance.collection('users').doc(uid);

      await userRef.update({
        'activity_score': FieldValue.increment(1),
      });

      // Check milestone unlocks
      final snapshot = await userRef.get();
      final activityScore = snapshot.data()?['activity_score'] ?? 0;
      _checkMilestoneUnlocks(activityScore as int);
    } catch (e) {
      debugPrint('⚠️ WellnessStudio: completion write failed, will retry on next open: $e');
      // Enqueue retry via SharedPreferences pending sync flag
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('wellness_pending_sync', true);
    }
  }

  /// Records completion of an AI-recommended pick.
  ///
  /// Marks it complete (persisted like catalog activities), and awards an
  /// engagement point + increments activity_score ONLY if the per-day AI cap
  /// hasn't been reached and this pick wasn't already completed. This keeps
  /// AI picks first-class in the progress system while preventing gaming via
  /// repeated refreshes.
  Future<void> _recordAiActivityCompletion(Map<String, dynamic> rec) async {
    final title = rec['title'] as String? ?? 'Wellness Activity';
    final category = rec['category'] as String? ?? 'Mindfulness Sessions';
    final id = _aiActivityId(title, category);

    final alreadyDone = _completedActivityIds.contains(id);
    setState(() => _completedActivityIds.add(id));
    await _saveCompletionState();

    if (alreadyDone) {
      // Already completed before — no additional points.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Already completed. Nice consistency!'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
      return;
    }

    // --- Per-day cap check ---
    final prefs = await SharedPreferences.getInstance();
    final today = _todayKey();
    if (prefs.getString(_aiPointsDateKey) != today) {
      await prefs.setString(_aiPointsDateKey, today);
      await prefs.setInt(_aiPointsCountKey, 0);
    }
    final awardedToday = prefs.getInt(_aiPointsCountKey) ?? 0;
    final canAward = awardedToday < _aiPointsDailyCap;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(canAward
              ? '🌟 +1 engagement point earned!'
              : 'Completed! Daily AI bonus limit reached — no extra points.'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }

    if (!canAward) return;

    // Award the point (locally count toward the cap + Firestore score).
    await prefs.setInt(_aiPointsCountKey, awardedToday + 1);

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
      await userRef.update({
        'activity_score': FieldValue.increment(1),
      });

      final snapshot = await userRef.get();
      final activityScore = snapshot.data()?['activity_score'] ?? 0;
      _checkMilestoneUnlocks(activityScore as int);
    } catch (e) {
      debugPrint('⚠️ WellnessStudio: AI completion write failed: $e');
      await prefs.setBool('wellness_pending_sync', true);
    }
  }

  /// Check if milestones should be unlocked based on activity score.
  void _checkMilestoneUnlocks(int score) {
    // Milestone thresholds for studio activities
    const milestones = [5, 10, 25, 50, 100];
    for (final threshold in milestones) {
      if (score == threshold) {
        debugPrint('🏆 Studio milestone unlocked at $threshold activities!');
      }
    }
  }

  /// Shows a bottom sheet upgrade prompt for locked activities (Req 6.7).
  /// Does not navigate away from the screen.
  void _showUpgradePrompt(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: false,
      builder: (ctx) => Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        decoration: BoxDecoration(
          color: Theme.of(ctx).brightness == Brightness.dark
              ? Theme.of(ctx).cardColor
              : Colors.white,
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.workspace_premium_rounded,
                size: 48,
                color: Theme.of(ctx).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Unlock Full Wellness Studio',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              'Upgrade to Premium to access all activities, including advanced breathing techniques, deeper recovery challenges, and more.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: Theme.of(ctx).textTheme.bodyMedium?.color?.withOpacity(0.7),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: const Text(
                  'Upgrade to Premium',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Maybe Later', style: TextStyle(color: Colors.grey[400])),
            ),
          ],
        ),
      ),
    );
  }

  /// Handles activity card tap — starts session or shows upgrade prompt.
  void _onActivityTap(WellnessStudioActivity activity) {
    final appState = context.read<AppState>();
    final isPro = appState.isPro;

    if (!activity.isFree && !isPro) {
      _showUpgradePrompt(context);
      return;
    }

    // Record activity start (non-blocking on failure)
    _recordActivityStart(activity);

    // Route breathing exercises to the dedicated screen (Req 6.5)
    if (activity.category == 'Breathing Exercises') {
      _startBreathingExercise(activity);
      return;
    }

    // Route wellness quizzes to the dedicated quiz screen (Req 6.6)
    if (activity.category == 'Wellness Quizzes') {
      _startWellnessQuiz(activity);
      return;
    }

    // Show activity session dialog
    _showActivitySession(activity);
  }

  /// Navigates to the dedicated Breathing Exercise screen.
  /// On completion (pop with true), records the activity as complete.
  Future<void> _startBreathingExercise(WellnessStudioActivity activity) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const BreathingExerciseScreen(),
      ),
    );

    if (result == true) {
      _recordActivityCompletion(activity);
    }
  }

  /// Navigates to the dedicated Wellness Quiz screen.
  /// On completion (pop with true), records the activity as complete.
  Future<void> _startWellnessQuiz(WellnessStudioActivity activity) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => WellnessQuizScreen(quizId: activity.id),
      ),
    );

    if (result == true) {
      _recordActivityCompletion(activity);
    }
  }

  /// Displays a simple activity session with a completion action.
  void _showActivitySession(WellnessStudioActivity activity) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(activity.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _categoryIcons[activity.category] ?? Icons.self_improvement_rounded,
              size: 64,
              color: Theme.of(ctx).colorScheme.primary.withOpacity(0.7),
            ),
            const SizedBox(height: 16),
            Text(
              '${activity.durationMinutes} min • ${activity.category}',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(ctx).textTheme.bodyMedium?.color?.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Complete this activity at your own pace. Tap "Done" when finished.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _recordActivityCompletion(activity);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Consumer<WellnessPlanState>(
      builder: (context, planState, _) {
        return Scaffold(
          backgroundColor: isDark ? const Color(0xFF0F1115) : const Color(0xFFF8F9FB),
          body: NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              _buildSliverAppBar(context),
              SliverToBoxAdapter(
                child: _buildRecommendedSection(context),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _TabBarDelegate(
                  tabBar: TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    labelColor: Theme.of(context).colorScheme.primary,
                    unselectedLabelColor: isDark ? Colors.grey[400] : Colors.grey[600],
                    indicatorColor: Theme.of(context).colorScheme.primary,
                    indicatorWeight: 3,
                    labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                    tabAlignment: TabAlignment.start,
                    tabs: _categories.map((cat) => Tab(text: cat)).toList(),
                  ),
                  backgroundColor: isDark ? const Color(0xFF0F1115) : const Color(0xFFF8F9FB),
                ),
              ),
            ],
            body: TabBarView(
              controller: _tabController,
              children: _categories.map((category) {
                return _buildCategoryTab(context, category);
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSliverAppBar(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 110.0,
      floating: false,
      pinned: true,
      elevation: 0,
      backgroundColor: Colors.transparent,
      flexibleSpace: FlexibleSpaceBar(
        centerTitle: true,
        titlePadding: const EdgeInsets.only(bottom: 16),
        title: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              "WELLNESS STUDIO",
              style: TextStyle(
                fontWeight: FontWeight.w900,
                letterSpacing: 2.0,
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              "Short challenges for daily wellness",
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Personalized "Recommended for You" section (additive, Premium)
  // ---------------------------------------------------------------------------

  Widget _buildRecommendedSection(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    return Consumer<AppState>(
      builder: (context, appState, _) {
        // Free users: locked teaser that opens the upsell.
        if (!appState.isPro) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: GestureDetector(
              onTap: () => ProModalUtils.showFeatureUpsellModal(
                context,
                title: 'Personalized Picks',
                message:
                    'Get wellness studio activities hand-picked for you by AI, '
                    'based on your recent check-ins, focus, and intentions. '
                    'Upgrade to Premium to unlock your personalized picks.',
                icon: Icons.auto_awesome_rounded,
              ),
              child: FrostedContainer(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.auto_awesome_rounded,
                            color: primary, size: 22),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Recommended for You',
                                style: TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w700)),
                            SizedBox(height: 2),
                            Text('AI picks tailored to your journey',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                      ),
                      const Icon(Icons.lock_rounded,
                          size: 18, color: Color(0xFFFF6B9D)),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        // Pro users: loading, empty, or the recommendation list.
        if (_isLoadingRecs) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: FrostedContainer(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: primary),
                    ),
                    const SizedBox(width: 16),
                    Text('Personalizing your picks…',
                        style: TextStyle(
                            color: isDark
                                ? Colors.grey[300]
                                : Colors.grey[700])),
                  ],
                ),
              ),
            ),
          );
        }

        if (_recsLoaded && _aiRecommendations.isEmpty) {
          return const SizedBox.shrink(); // Nothing to show; keep it clean.
        }

        if (_aiRecommendations.isEmpty) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome_rounded, color: primary, size: 18),
                  const SizedBox(width: 8),
                  const Text('Recommended for You',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                  const Spacer(),
                  IconButton(
                    onPressed: _isLoadingRecs ? null : _refreshRecommendations,
                    icon: Icon(Icons.refresh_rounded, size: 18, color: primary),
                    tooltip: 'Refresh picks',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ..._aiRecommendations.map((rec) => _buildRecCard(context, rec)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRecCard(BuildContext context, Map<String, dynamic> rec) {
    final primary = Theme.of(context).colorScheme.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final title = rec['title'] as String? ?? 'Wellness Activity';
    final category = rec['category'] as String? ?? 'Mindfulness Sessions';
    final duration = rec['durationMinutes'] as int? ?? 5;
    final reason = rec['reason'] as String? ?? '';
    final icon = _categoryIcons[category] ?? Icons.self_improvement_rounded;
    final isDone = _completedActivityIds.contains(_aiActivityId(title, category));

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => _showAiActivityGuidance(rec),
        child: FrostedContainer(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: primary, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                        reason.isNotEmpty ? reason : '$category • $duration min',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (isDone)
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_circle_rounded,
                        color: Colors.green, size: 20),
                  )
                else
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white10 : Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('$duration min',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color:
                                isDark ? Colors.grey[300] : Colors.grey[600])),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Shows a bottom sheet with AI-generated guidance for the tapped activity.
  Future<void> _showAiActivityGuidance(Map<String, dynamic> rec) async {
    final title = rec['title'] as String? ?? 'Wellness Activity';
    final category = rec['category'] as String? ?? 'Mindfulness Sessions';
    final duration = rec['durationMinutes'] as int? ?? 5;

    // Open the sheet immediately with a loading state, then fill in guidance.
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return FutureBuilder<String?>(
          future: _aiService.generateActivityGuidance(
            title: title,
            category: category,
            durationMinutes: duration,
          ),
          builder: (ctx, snapshot) {
            final isDark = Theme.of(ctx).brightness == Brightness.dark;
            final loading =
                snapshot.connectionState == ConnectionState.waiting;
            final guidance = snapshot.data ??
                'Take about $duration minutes for this activity. Find a '
                    'comfortable spot, move at your own pace, and focus on how '
                    'it makes you feel.';
            return Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(24),
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.7,
              ),
              decoration: BoxDecoration(
                color: isDark ? Theme.of(ctx).cardColor : Colors.white,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Theme.of(ctx)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Icon(
                          _categoryIcons[category] ??
                              Icons.self_improvement_rounded,
                          color: Theme.of(ctx).colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(title,
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('$category • $duration min',
                      style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(ctx)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.5))),
                  const SizedBox(height: 16),
                  if (loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else
                    Flexible(
                      child: SingleChildScrollView(
                        child: Text(
                          guidance,
                          style: const TextStyle(fontSize: 15, height: 1.55),
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  Builder(builder: (btnCtx) {
                    final id = _aiActivityId(title, category);
                    final done = _completedActivityIds.contains(id);
                    return SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: done
                            ? () => Navigator.pop(ctx)
                            : () {
                                Navigator.pop(ctx);
                                _recordAiActivityCompletion(rec);
                              },
                        icon: Icon(
                            done
                                ? Icons.check_circle_rounded
                                : Icons.check_rounded,
                            size: 20),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              done ? Colors.green : Theme.of(ctx).colorScheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                        ),
                        label: Text(done ? 'Completed' : 'Mark as done'),
                      ),
                    );
                  }),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCategoryTab(BuildContext context, String category) {
    final activities = _activitiesByCategory[category] ?? [];
    final isRecommended = _isRecommendedForToday(category);

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      itemCount: activities.length,
      itemBuilder: (context, index) {
        final activity = activities[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _buildActivityCard(context, activity, isRecommended),
        );
      },
    );
  }

  Widget _buildActivityCard(
    BuildContext context,
    WellnessStudioActivity activity,
    bool isRecommended,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final appState = context.read<AppState>();
    final isLocked = !activity.isFree && !appState.isPro;
    final icon = _categoryIcons[activity.category] ?? Icons.self_improvement_rounded;

    return GestureDetector(
      onTap: () => _onActivityTap(activity),
      child: FrostedContainer(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Category icon
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: (isLocked
                          ? Colors.grey
                          : Theme.of(context).colorScheme.primary)
                      .withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isLocked ? Icons.lock_rounded : icon,
                  size: 24,
                  color: isLocked
                      ? Colors.grey
                      : Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 14),

              // Title and metadata
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      activity.title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: isLocked
                            ? (isDark ? Colors.grey[500] : Colors.grey[400])
                            : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        // Duration badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white10 : Colors.grey[100],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${activity.durationMinutes} min',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.grey[300] : Colors.grey[600],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Recommended badge
                        if (isRecommended && !isLocked)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.amber.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              '⭐ Recommended',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.amber,
                              ),
                            ),
                          ),
                        if (isLocked)
                          Text(
                            'Premium',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[400],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              // Completion checkmark
              if (activity.isCompleted)
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_circle_rounded, color: Colors.green, size: 22),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Persistent header delegate for the tab bar to keep it pinned during scroll.
class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  final Color backgroundColor;

  _TabBarDelegate({required this.tabBar, required this.backgroundColor});

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: backgroundColor,
      child: tabBar,
    );
  }

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  bool shouldRebuild(_TabBarDelegate oldDelegate) => false;
}
