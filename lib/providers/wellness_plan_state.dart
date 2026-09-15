import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/check_in.dart';
import '../models/daily_plan.dart';
import '../models/sync_operation.dart';
import '../models/wellness_enums.dart';
import '../models/wellness_intention.dart';
import '../models/wellness_milestone.dart';
import '../services/ai_service.dart';
import '../services/wellness_plan_service.dart';
import 'app_state.dart';

/// State provider for the daily wellness plan lifecycle.
///
/// Manages loading, generating, completing, and falling back on daily plans.
/// Integrates with [AIService] for AI generation and [WellnessPlanService]
/// for Firestore persistence and fallback selection.
///
/// Requirements: 3.1, 3.6, 3.7, 3.8, 3.10, 3.13
class WellnessPlanState extends ChangeNotifier {
  final AIService _aiService;
  final WellnessPlanService _planService;

  static const String _dailyPlanCacheKey = 'wellness_daily_plan';
  static const String _syncQueueKey = 'wellness_sync_queue';

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  DailyPlan? _todaysPlan;
  bool _isGenerating = false;
  String? _generationError;
  List<DailyPlan> _recentPlans = [];
  bool _isFallbackBannerVisible = false;

  // ---------------------------------------------------------------------------
  // Getters
  // ---------------------------------------------------------------------------

  DailyPlan? get todaysPlan => _todaysPlan;
  bool get isGenerating => _isGenerating;
  String? get generationError => _generationError;
  List<DailyPlan> get recentPlans => _recentPlans;
  bool get isFallbackBannerVisible => _isFallbackBannerVisible;

  // ---------------------------------------------------------------------------
  // Constructor
  // ---------------------------------------------------------------------------

  WellnessPlanState({
    AIService? aiService,
    WellnessPlanService? planService,
  })  : _aiService = aiService ?? AIService(),
        _planService = planService ?? WellnessPlanService();

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Loads today's plan for the given [userId].
  ///
  /// Strategy: check local SharedPreferences cache first, then Firestore.
  /// If a plan already exists for today, it is returned without triggering
  /// a new generation request (Requirement 3.13).
  Future<void> loadTodaysPlan(String userId) async {
    _generationError = null;

    // Check local cache first
    final cachedPlan = await _loadCachedPlan();
    if (cachedPlan != null && _isToday(cachedPlan.date)) {
      _todaysPlan = cachedPlan;
      notifyListeners();
      // Ensure the home-screen widget reflects the loaded plan (it otherwise
      // stays on the placeholder until a plan is generated/toggled).
      await _pushToWidget(cachedPlan, force: true);
      // Also load recent plans in background
      _loadRecentPlans(userId);
      return;
    }

    // Check Firestore
    try {
      final firestorePlan =
          await _planService.loadPlanForDate(userId, DateTime.now());
      if (firestorePlan != null) {
        _todaysPlan = firestorePlan;
        await _cachePlan(firestorePlan);
        notifyListeners();
        await _pushToWidget(firestorePlan, force: true);
        _loadRecentPlans(userId);
        return;
      }
    } catch (e) {
      debugPrint('❌ WellnessPlanState.loadTodaysPlan Firestore error: $e');
    }

    // No plan exists for today — UI can prompt check-in. Show the widget
    // placeholder so it doesn't display stale data.
    _todaysPlan = null;
    notifyListeners();
    await AppState.pushWidgetPlaceholder();
    _loadRecentPlans(userId);
  }

  /// Reconciles today's plan from the local cache.
  ///
  /// The home-screen widget writes action toggles into the same cache key
  /// (`wellness_daily_plan`) from a background isolate. Call this on app
  /// foreground-resume so a checkbox toggled on the widget is reflected in the
  /// in-app plan card immediately. Only updates when the cached plan is for
  /// today and actually differs from the in-memory plan.
  Future<void> reloadFromCache() async {
    final cached = await _loadCachedPlan();
    if (cached == null || !_isToday(cached.date)) return;
    if (_todaysPlan == null || _todaysPlan!.id != cached.id) {
      _todaysPlan = cached;
      notifyListeners();
      await _pushToWidget(cached, force: true);
      return;
    }
    // Compare action completion so we only rebuild when something changed.
    final current = _todaysPlan!.actions;
    final incoming = cached.actions;
    final changed = current.length != incoming.length ||
        List.generate(current.length, (i) => i).any((i) =>
            current[i].id != incoming[i].id ||
            current[i].isCompleted != incoming[i].isCompleted);
    if (changed) {
      _todaysPlan = cached;
      notifyListeners();
    }
  }

  /// Generates a new daily plan using the AI service.
  ///
  /// If the AI returns null (timeout/error), falls back to a curated
  /// pre-built plan selected by energy tier and time range, and shows
  /// a fallback banner. (Requirements 3.1, 3.10)
  Future<void> generatePlan(
    String userId,
    CheckIn checkIn, {
    List<WellnessIntention> intentions = const [],
    String? cycleContext,
    String? travelContext,
    List<String> preferredMethods = const [],
    String? premiumToolkitContext,
  }) async {
    _isGenerating = true;
    _generationError = null;
    _isFallbackBannerVisible = false;
    notifyListeners();

    try {
      // Load recent plans for AI context
      if (_recentPlans.isEmpty) {
        _recentPlans = await _planService.loadRecentPlans(userId);
      }

      // Call AI service
      final plan = await _aiService.generatePlan(
        userId: userId,
        checkIn: checkIn,
        intentions: intentions,
        recentPlans: _recentPlans,
        cycleContext: cycleContext,
        travelContext: travelContext,
        preferredMethods: preferredMethods,
        premiumToolkitContext: premiumToolkitContext,
      );

      if (plan != null) {
        // AI generation succeeded
        _todaysPlan = plan;
        await _planService.savePlan(userId, plan);
        await _cachePlan(plan);
        // Push to widget within 2 minutes of generation (Requirement 10.4)
        await _pushToWidget(plan);
      } else {
        // AI returned null (timeout or error) — use fallback
        await _applyFallbackPlan(
          checkIn.energyTier,
          checkIn.availableTime?.name ?? AvailableTimeRange.range20_40.name,
          userId,
          preferredMethods: preferredMethods,
        );
      }
    } catch (e) {
      debugPrint('❌ WellnessPlanState.generatePlan error: $e');
      _generationError = 'Failed to generate your wellness plan. '
          'A default plan has been provided.';

      // Fall back on any error
      await _applyFallbackPlan(
        checkIn.energyTier,
        checkIn.availableTime?.name ?? AvailableTimeRange.range20_40.name,
        userId,
        preferredMethods: preferredMethods,
      );
    } finally {
      _isGenerating = false;
      notifyListeners();
    }
  }

  /// Regenerates today's plan using a different fallback selection.
  ///
  /// Unlike [generatePlan], this skips the AI service entirely and
  /// selects a different curated plan from the fallback pool, guaranteeing
  /// a visibly different plan each time the user taps refresh.
  Future<void> regeneratePlan(
    String userId,
    CheckIn checkIn, {
    List<String> preferredMethods = const [],
  }) async {
    _isGenerating = true;
    _generationError = null;
    _isFallbackBannerVisible = false;
    notifyListeners();

    try {
      await _applyFallbackPlan(
        checkIn.energyTier,
        checkIn.availableTime?.name ?? AvailableTimeRange.range20_40.name,
        userId,
        preferredMethods: preferredMethods,
      );
    } catch (e) {
      debugPrint('❌ WellnessPlanState.regeneratePlan error: $e');
      _generationError = 'Unable to regenerate plan. Please try again.';
    } finally {
      _isGenerating = false;
      notifyListeners();
    }
  }

  /// Marks a single wellness action as complete with optimistic local update.
  ///
  /// Flow:
  /// 1. Optimistic local update → notifyListeners immediately.
  /// 2. Attempt Firestore update within 2 seconds (Requirement 3.6).
  /// 3. On failure → enqueue to sync queue for later retry.
  Future<void> markActionComplete(
    String planId,
    String actionId, {
    required String userId,
    bool completed = true,
  }) async {
    if (_todaysPlan == null || _todaysPlan!.id != planId) return;

    // Optimistic local update — set the action to [completed] (allows both
    // checking and unchecking).
    final updatedActions = _todaysPlan!.actions.map((action) {
      if (action.id == actionId) {
        return action.copyWith(isCompleted: completed);
      }
      return action;
    }).toList();

    _todaysPlan = _todaysPlan!.copyWith(actions: updatedActions);
    await _cachePlan(_todaysPlan!);
    notifyListeners();

    // Push the updated plan to the home-screen widget immediately so the
    // checkbox state stays in sync (bypasses the 30-minute refresh cap).
    await _pushToWidget(_todaysPlan!, force: true);

    // Attempt Firestore update with 2s timeout
    try {
      await _planService
          .updateActionCompletion(userId, planId, actionId, completed)
          .timeout(const Duration(seconds: 2));
    } catch (e) {
      debugPrint(
          '❌ WellnessPlanState.markActionComplete Firestore failed: $e');
      // Enqueue to sync queue for retry when online
      await _enqueueSyncOperation(SyncOperation(
        type: SyncOperationType.toggleAction,
        payload: {
          'planId': planId,
          'actionId': actionId,
          'completed': completed,
        },
      ));
    }
  }

  /// Marks the entire plan as complete.
  ///
  /// Writes the completion record to Firestore and triggers a milestone
  /// check via [WellnessMilestoneHelper]. (Requirement 3.8)
  Future<void> markPlanComplete(
    String planId, {
    required String userId,
  }) async {
    if (_todaysPlan == null || _todaysPlan!.id != planId) return;

    // Update local state
    _todaysPlan = _todaysPlan!.copyWith(isCompleted: true);
    await _cachePlan(_todaysPlan!);
    notifyListeners();

    // Reflect completion on the home-screen widget immediately.
    await _pushToWidget(_todaysPlan!, force: true);

    // Write completion to Firestore
    try {
      await _planService.markPlanComplete(userId, planId);
    } catch (e) {
      debugPrint(
          '❌ WellnessPlanState.markPlanComplete Firestore failed: $e');
    }

    // Trigger milestone check
    await _checkAndCreateMilestone(userId);
  }

  /// Selects and sets a fallback plan based on energy tier and time range.
  ///
  /// Used when the user manually requests a fallback or when the system
  /// needs to provide a plan without AI generation. (Requirement 3.10)
  Future<void> useFallbackPlan(
    int energyTier,
    String timeRange, {
    required String userId,
  }) async {
    await _applyFallbackPlan(energyTier, timeRange, userId);
    notifyListeners();
  }

  /// Dismisses the fallback banner.
  void dismissFallbackBanner() {
    _isFallbackBannerVisible = false;
    notifyListeners();
  }

  /// Resets all state — useful on sign-out or account deletion.
  void reset() {
    _todaysPlan = null;
    _isGenerating = false;
    _generationError = null;
    _recentPlans = [];
    _isFallbackBannerVisible = false;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Applies a fallback plan: selects from curated set, saves, caches,
  /// and shows the fallback banner.
  Future<void> _applyFallbackPlan(
    int energyTier,
    String timeRange,
    String userId, {
    List<String> preferredMethods = const [],
  }) async {
    try {
      final currentPlanId = _todaysPlan?.id;
      final fallback = await _planService.selectFallbackPlan(
        energyTier,
        timeRange,
        excludeId: currentPlanId,
        preferredMethods: preferredMethods,
      );
      _todaysPlan = fallback;
      _isFallbackBannerVisible = true;

      await _planService.savePlan(userId, fallback);
      await _cachePlan(fallback);
      // Push fallback to widget (Requirement 10.4)
      await _pushToWidget(fallback);
    } catch (e) {
      debugPrint('❌ WellnessPlanState._applyFallbackPlan error: $e');
      _generationError = 'Unable to load a wellness plan. Please try again.';
    }
  }

  /// Loads the cached plan from SharedPreferences.
  Future<DailyPlan?> _loadCachedPlan() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // The home-screen widget's background isolate writes toggles into this
      // same key. Reload so the UI isolate sees the latest value instead of a
      // stale in-memory copy.
      await prefs.reload();
      final raw = prefs.getString(_dailyPlanCacheKey);
      if (raw == null || raw.isEmpty) return null;
      return DailyPlan.fromMap(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (e) {
      debugPrint('❌ WellnessPlanState._loadCachedPlan error: $e');
      return null;
    }
  }

  /// Caches the given plan to SharedPreferences.
  Future<void> _cachePlan(DailyPlan plan) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_dailyPlanCacheKey, jsonEncode(plan.toMap()));
    } catch (e) {
      debugPrint('❌ WellnessPlanState._cachePlan error: $e');
    }
  }

  /// Loads recent plans (last 30 days) in the background.
  Future<void> _loadRecentPlans(String userId) async {
    try {
      _recentPlans = await _planService.loadRecentPlans(userId);
    } catch (e) {
      debugPrint('❌ WellnessPlanState._loadRecentPlans error: $e');
    }
  }

  /// Checks if a [DateTime] represents today in the user's local timezone.
  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  /// Enqueues a [SyncOperation] to the local sync queue for later processing
  /// when connectivity is restored.
  Future<void> _enqueueSyncOperation(SyncOperation operation) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_syncQueueKey);
      final List<Map<String, dynamic>> queue = raw != null
          ? List<Map<String, dynamic>>.from(
              (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e as Map)),
            )
          : [];

      queue.add(operation.toMap());
      await prefs.setString(_syncQueueKey, jsonEncode(queue));
    } catch (e) {
      debugPrint('❌ WellnessPlanState._enqueueSyncOperation error: $e');
    }
  }

  /// Checks if the user has hit a milestone threshold and creates the
  /// corresponding [WellnessMilestone] entry.
  ///
  /// Milestone thresholds: 1, 5, 10, 25, 50 completed plans.
  Future<void> _checkAndCreateMilestone(String userId) async {
    try {
      // Count completed plans from recent plans + current plan
      final completedCount =
          _recentPlans.where((p) => p.isCompleted).length +
              (_todaysPlan?.isCompleted == true ? 1 : 0);

      final milestoneType =
          WellnessMilestoneHelper.getMilestoneForCount(completedCount);
      if (milestoneType == null) return;

      // Create milestone
      final milestoneName = _milestoneNameFor(milestoneType);
      final supportingMessage =
          WellnessMilestoneHelper.supportingMessageFor(milestoneType);

      final milestone = WellnessMilestoneHelper.create(
        milestoneName: milestoneName,
        type: milestoneType,
        completedPlanCount: completedCount,
        achievementDate: DateTime.now(),
        supportingMessage: supportingMessage,
      );

      // Save milestone to Firestore via StorageService travel_memories path
      // (WellnessMilestone is typedef for TravelMemory)
      debugPrint(
          '🏆 Milestone created: $milestoneName (count: $completedCount)');

      // The milestone is a TravelMemory — it is created and logged here.
      // Persistence to Firestore happens via StorageService.saveTravelMemories
      // which the UI layer triggers when displaying the journey map.
      debugPrint('  → milestone id: ${milestone.id}');
    } catch (e) {
      debugPrint('❌ WellnessPlanState._checkAndCreateMilestone error: $e');
    }
  }

  /// Returns a human-readable milestone name for the given type.
  String _milestoneNameFor(MilestoneType type) {
    switch (type) {
      case MilestoneType.firstPlan:
        return 'First Plan Completed';
      case MilestoneType.fivePlans:
        return '5 Plans Completed';
      case MilestoneType.tenPlans:
        return '10 Plans Completed';
      case MilestoneType.twentyFivePlans:
        return '25 Plans Completed';
      case MilestoneType.fiftyPlans:
        return '50 Plans Completed';
    }
  }

  /// Pushes the given plan to the AI Wellness Widget via [AppState.pushPlanToWidget].
  ///
  /// This ensures the widget is updated within 2 minutes of new plan generation
  /// (Requirement 10.4). On failure, the previously displayed data is retained.
  Future<void> _pushToWidget(DailyPlan plan, {bool force = false}) async {
    try {
      await AppState.pushPlanToWidget(plan, force: force);
    } catch (e) {
      debugPrint('❌ WellnessPlanState._pushToWidget error: $e');
      // On failure, retain previous widget data (Requirement 10.4)
    }
  }
}
