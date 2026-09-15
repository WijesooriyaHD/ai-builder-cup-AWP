import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';

import '../models/check_in.dart';
import '../models/daily_plan.dart';
import '../models/wellness_action.dart';
import '../models/wellness_enums.dart';
import '../providers/app_state.dart';
import '../providers/check_in_state.dart';
import '../providers/wellness_plan_state.dart';
import '../screens/action_detail_screen.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import '../utils/pro_modal_utils.dart';
import 'frosted_container.dart';

/// Displays the user's Daily Plan with interactive action checkboxes.
///
/// Shows:
/// - [DailyPlan.todaysFocus] as header
/// - List of [WellnessAction] cards with checkboxes
/// - Total Time footer
/// - Calm completion animation when an action is marked done (Req 3.7)
/// - Lottie completion animation when all actions are done (Req 3.8)
///
/// Requirements: 3.6, 3.7, 3.8, 4.4
class DailyPlanCard extends StatefulWidget {
  const DailyPlanCard({super.key, required this.plan});

  final DailyPlan plan;

  @override
  State<DailyPlanCard> createState() => _DailyPlanCardState();
}

class _DailyPlanCardState extends State<DailyPlanCard>
    with TickerProviderStateMixin {
  /// Tracks which action IDs were just completed (for per-action animation).
  final Set<String> _recentlyCompleted = {};

  late AnimationController _lottieController;

  /// Full-screen celebration overlay entry (removed when the animation ends).
  OverlayEntry? _celebrationOverlay;
  Timer? _celebrationTimer;

  final StorageService _storage = StorageService();

  /// The one-time reminder set for today's plan, if any (`[hour, minute]`).
  /// Null when no reminder is set. Persisted so the alarm icon reflects the
  /// correct state after switching tabs or restarting the app.
  List<int>? _reminder;

  /// Date key ("yyyy-MM-dd") the reminder is scoped to, so it clears each day.
  String get _planDateKey => widget.plan.date.toIso8601String().split('T').first;

  @override
  void initState() {
    super.initState();
    _lottieController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    _loadReminder();
  }

  Future<void> _loadReminder() async {
    try {
      final stored = await _storage.loadPlanReminder(_planDateKey);
      if (!mounted || stored == null) return;
      setState(() => _reminder = stored);
    } catch (_) {
      // Non-fatal: absence just shows the reminder as off.
    }
  }

  @override
  void dispose() {
    _celebrationTimer?.cancel();
    _celebrationOverlay?.remove();
    _celebrationOverlay = null;
    _lottieController.dispose();
    super.dispose();
  }

  /// Removes the celebration overlay if it's showing.
  void _dismissCelebration() {
    _celebrationTimer?.cancel();
    _celebrationTimer = null;
    _celebrationOverlay?.remove();
    _celebrationOverlay = null;
  }

  /// Plays the achievement Lottie as a full-screen overlay above the entire
  /// app, then removes it when the animation finishes.
  ///
  /// Triggered only from an explicit user completion (see
  /// [_onActionCheckboxTapped]), never from widget rebuilds/navigation.
  void _triggerPlanCompleteAnimation() {
    // Clear any previous (possibly stuck) overlay first.
    _dismissCelebration();

    final overlay = Overlay.of(context, rootOverlay: true);

    final entry = OverlayEntry(
      builder: (context) => IgnorePointer(
        child: Container(
          color: Colors.black.withOpacity(0.15),
          alignment: Alignment.center,
          child: Lottie.asset(
            'assets/images/achievement.json',
            controller: _lottieController,
            width: MediaQuery.of(context).size.width * 0.8,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );

    _celebrationOverlay = entry;
    overlay.insert(entry);

    _lottieController.forward(from: 0).whenComplete(_dismissCelebration);

    // Safety net: guarantee removal even if the controller callback doesn't
    // fire (e.g. interrupted by a rebuild), so the overlay can never get stuck.
    _celebrationTimer =
        Timer(const Duration(seconds: 4), _dismissCelebration);
  }

  Future<void> _onActionCheckboxTapped(WellnessAction action) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    final planState = Provider.of<WellnessPlanState>(context, listen: false);

    // Toggle: if already completed, uncheck it; otherwise complete it.
    final newCompleted = !action.isCompleted;

    // Only play the calm completion animation when checking (not unchecking).
    if (newCompleted) {
      setState(() {
        _recentlyCompleted.add(action.id);
      });
    }

    // Call state to set the action's completion (optimistic update + Firestore)
    await planState.markActionComplete(
      widget.plan.id,
      action.id,
      userId: userId,
      completed: newCompleted,
    );

    // If all actions are now completed → mark plan complete and celebrate.
    final updatedPlan = planState.todaysPlan;
    if (newCompleted &&
        updatedPlan != null &&
        updatedPlan.allActionsCompleted) {
      await planState.markPlanComplete(
        updatedPlan.id,
        userId: userId,
      );
      // Full-screen celebration — only on a genuine just-now completion.
      if (mounted) _triggerPlanCompleteAnimation();
    }

    // Remove from recently-completed set after animation plays
    if (newCompleted) {
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) {
        setState(() {
          _recentlyCompleted.remove(action.id);
        });
      }
    }
  }

  /// Whether the plan is currently being regenerated.
  bool _isRegenerating = false;

  Future<void> _onRegeneratePlan() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    // Regenerating today's plan is a Premium feature.
    final appState = Provider.of<AppState>(context, listen: false);
    if (!appState.isPro) {
      ProModalUtils.showFeatureUpsellModal(
        context,
        title: 'Premium Feature',
        message:
            'Regenerating your daily plan is a Premium feature. Upgrade to '
            'Premium to refresh your plan anytime and get a fresh set of '
            'wellness actions.',
        icon: Icons.refresh_rounded,
      );
      return;
    }

    final checkInState = Provider.of<CheckInState>(context, listen: false);
    final planState = Provider.of<WellnessPlanState>(context, listen: false);

    // Ensure today's check-in is loaded (may be null after silent sign-in
    // if the SharedPreferences cache was cleared).
    if (checkInState.todaysCheckIn == null) {
      await checkInState.loadTodaysCheckIn(userId);
    }

    CheckIn checkIn;

    if (checkInState.todaysCheckIn != null) {
      checkIn = checkInState.todaysCheckIn!;
    } else {
      // Construct a minimal check-in so regeneration always works.
      // Use the existing plan's energy tier if available, otherwise default.
      final tier = widget.plan.energyTier ?? 2;
      final int score;
      switch (tier) {
        case 1:
          score = 2;
          break;
        case 3:
          score = 4;
          break;
        default:
          score = 3;
      }
      checkIn = CheckIn(
        id: 'regenerate_${DateTime.now().millisecondsSinceEpoch}',
        date: DateTime.now(),
        energyScore: score,
        availableTime: AvailableTimeRange.range20_40,
      );
    }

    setState(() => _isRegenerating = true);

    await planState.regeneratePlan(userId, checkIn,
        preferredMethods: appState.preferredMethods);

    if (mounted) {
      setState(() => _isRegenerating = false);
    }
  }

  bool get _hasReminder => _reminder != null;

  String _reminderLabel(BuildContext context) {
    if (_reminder == null) return '';
    return TimeOfDay(hour: _reminder![0], minute: _reminder![1]).format(context);
  }

  /// Opens the reminder flow. If a reminder already exists, offers to edit or
  /// remove it; otherwise goes straight to the time picker. Mirrors the habit
  /// builder UX, but schedules a ONE-TIME (non-repeating) reminder for today.
  Future<void> _onReminderPressed() async {
    if (_hasReminder) {
      final action = await showModalBottomSheet<String>(
        context: context,
        builder: (sheetContext) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.alarm_on_rounded),
                title: Text('Reminder at ${_reminderLabel(sheetContext)}'),
                subtitle: const Text('One-time, today only'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.edit_rounded),
                title: const Text('Change time'),
                onTap: () => Navigator.pop(sheetContext, 'edit'),
              ),
              ListTile(
                leading: const Icon(Icons.alarm_off_rounded, color: Colors.red),
                title: const Text('Remove reminder',
                    style: TextStyle(color: Colors.red)),
                onTap: () => Navigator.pop(sheetContext, 'remove'),
              ),
            ],
          ),
        ),
      );

      if (action == 'remove') {
        await NotificationService().cancelPlanReminder();
        await _storage.clearPlanReminder(_planDateKey);
        if (mounted) setState(() => _reminder = null);
        return;
      }
      if (action != 'edit') return; // dismissed
    }

    if (!mounted) return;
    await _pickTimeAndSchedule();
  }

  Future<void> _pickTimeAndSchedule() async {
    final initial = _reminder != null
        ? TimeOfDay(hour: _reminder![0], minute: _reminder![1])
        : const TimeOfDay(hour: 9, minute: 0);

    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: 'Remind me to do this today',
    );
    if (picked == null || !mounted) return;

    // A one-time reminder can only be for a time still ahead today.
    final now = TimeOfDay.now();
    final pickedMinutes = picked.hour * 60 + picked.minute;
    final nowMinutes = now.hour * 60 + now.minute;
    if (pickedMinutes <= nowMinutes) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Please choose a time later today so the reminder can still fire.'),
        ),
      );
      return;
    }

    // Ensure notification permission before scheduling.
    final notifier = NotificationService();
    final granted = await notifier.hasNotificationPermission()
        ? true
        : await notifier.requestPermission();

    final scheduled = await notifier.schedulePlanReminderOnce(
      hour: picked.hour,
      minute: picked.minute,
      focusLabel: widget.plan.todaysFocus,
      assumeAuthorized: granted,
    );

    // Persist + reflect in the UI only when it actually scheduled.
    if (scheduled != null) {
      await _storage.savePlanReminder(_planDateKey, picked.hour, picked.minute);
      if (mounted) setState(() => _reminder = [picked.hour, picked.minute]);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          !granted
              ? 'Reminder saved, but notifications are disabled. Enable them in Settings to be reminded.'
              : (scheduled == null
                  ? 'Couldn\'t set that reminder. Please pick a time later today.'
                  : 'Reminder set for ${picked.format(context)} today.'),
        ),
      ),
    );
  }

  void _onActionCardTapped(WellnessAction action) {
    // Navigate to action detail; back returns to Home in one step (Req 4.4)
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ActionDetailScreen(action: action),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plan = widget.plan;

    return Stack(
      children: [
        FrostedContainer(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header: Today's Focus
                _buildHeader(theme, plan),
                const SizedBox(height: 16),

                // Action list
                ...plan.actions.map((action) => _buildActionCard(
                      theme,
                      action,
                    )),

                const SizedBox(height: 12),

                // Footer: Total Time
                _buildFooter(theme, plan),
              ],
            ),
          ),
        ),

      ],
    );
  }

  Widget _buildHeader(ThemeData theme, DailyPlan plan) {
    return Row(
      children: [
        Icon(
          Icons.checklist_rounded,
          color: theme.colorScheme.primary,
          size: 22,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            "Today's Plan",
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
        ),
        // One-time reminder (alarm) — off by default, mirrors habit builder.
        if (!plan.allActionsCompleted)
          IconButton(
            onPressed: _onReminderPressed,
            icon: Icon(
              _hasReminder ? Icons.alarm_on_rounded : Icons.alarm_add_rounded,
              color: _hasReminder
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface.withOpacity(0.4),
              size: 22,
            ),
            tooltip: _hasReminder
                ? 'Reminder at ${_reminderLabel(context)} (tap to change)'
                : 'Set a one-time reminder',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            splashRadius: 20,
          ),
        if (!plan.allActionsCompleted) const SizedBox(width: 12),
        if (!plan.allActionsCompleted)
          _isRegenerating
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Consumer<AppState>(
                  builder: (context, appState, _) {
                    return IconButton(
                      onPressed: _onRegeneratePlan,
                      icon: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Icon(
                            Icons.refresh_rounded,
                            color: theme.colorScheme.primary,
                            size: 22,
                          ),
                          // Lock badge for free users — regenerating is Premium.
                          if (!appState.isPro)
                            Positioned(
                              right: -4,
                              top: -4,
                              child: Container(
                                padding: const EdgeInsets.all(1),
                                decoration: BoxDecoration(
                                  color: theme.scaffoldBackgroundColor,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.lock_rounded,
                                  size: 12,
                                  color: Color(0xFFFF6B9D),
                                ),
                              ),
                            ),
                        ],
                      ),
                      tooltip: appState.isPro
                          ? 'Regenerate plan'
                          : 'Regenerate plan (Premium)',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      splashRadius: 20,
                    );
                  },
                ),
        if (plan.allActionsCompleted)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Complete',
              style: theme.textTheme.labelSmall?.copyWith(
                color: Colors.green.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildActionCard(ThemeData theme, WellnessAction action) {
    final isRecentlyCompleted = _recentlyCompleted.contains(action.id);
    final categoryColor = _categoryColor(action.category);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: action.isCompleted
              ? categoryColor.withOpacity(0.06)
              : theme.colorScheme.surface.withOpacity(0.5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: action.isCompleted
                ? categoryColor.withOpacity(0.3)
                : theme.colorScheme.outline.withOpacity(0.12),
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _onActionCardTapped(action),
            child: Semantics(
              label: '${action.title}, ${action.durationMinutes} minutes, ${action.isCompleted ? "completed" : "not completed"}',
              child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  // Checkbox
                  _ActionCheckbox(
                    isCompleted: action.isCompleted,
                    isAnimating: isRecentlyCompleted,
                    categoryColor: categoryColor,
                    onTap: () => _onActionCheckboxTapped(action),
                  ),
                  const SizedBox(width: 12),

                  // Category icon
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: categoryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _categoryIcon(action.category),
                      size: 18,
                      color: categoryColor,
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Title and duration
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          action.title,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                            decoration: action.isCompleted
                                ? TextDecoration.lineThrough
                                : null,
                            decorationColor:
                                theme.colorScheme.onSurface.withOpacity(0.4),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${action.durationMinutes} min',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color:
                                theme.colorScheme.onSurface.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Navigate arrow
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: theme.colorScheme.onSurface.withOpacity(0.3),
                  ),
                ],
              ),
            ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(ThemeData theme, DailyPlan plan) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          '${plan.completedActionsCount}/${plan.actions.length} completed',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withOpacity(0.5),
            fontWeight: FontWeight.w500,
          ),
        ),
        Row(
          children: [
            Icon(
              Icons.schedule_rounded,
              size: 16,
              color: theme.colorScheme.primary.withOpacity(0.7),
            ),
            const SizedBox(width: 4),
            Text(
              'Total: ${plan.totalTime} min',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }

  IconData _categoryIcon(WellnessCategory category) {
    switch (category) {
      case WellnessCategory.flexibility:
        return Icons.accessibility_new_rounded;
      case WellnessCategory.stress:
        return Icons.spa_rounded;
      case WellnessCategory.sleep:
        return Icons.bedtime_rounded;
      case WellnessCategory.movement:
        return Icons.directions_run_rounded;
      case WellnessCategory.recovery:
        return Icons.healing_rounded;
      case WellnessCategory.energy:
        return Icons.bolt_rounded;
      case WellnessCategory.mentalClarity:
        return Icons.psychology_rounded;
      case WellnessCategory.mindfulness:
        return Icons.self_improvement_rounded;
      case WellnessCategory.general:
        return Icons.favorite_rounded;
    }
  }

  Color _categoryColor(WellnessCategory category) {
    switch (category) {
      case WellnessCategory.flexibility:
        return Colors.purple.shade400;
      case WellnessCategory.stress:
        return Colors.teal.shade400;
      case WellnessCategory.sleep:
        return Colors.indigo.shade400;
      case WellnessCategory.movement:
        return Colors.orange.shade400;
      case WellnessCategory.recovery:
        return Colors.green.shade400;
      case WellnessCategory.energy:
        return Colors.amber.shade600;
      case WellnessCategory.mentalClarity:
        return Colors.blue.shade400;
      case WellnessCategory.mindfulness:
        return Colors.deepPurple.shade300;
      case WellnessCategory.general:
        return Colors.pink.shade300;
    }
  }
}

/// A custom animated checkbox for wellness actions.
///
/// Shows a calm scale/fade animation on completion (non-celebratory,
/// per Requirement 3.7). The animation completes within 2 seconds.
class _ActionCheckbox extends StatelessWidget {
  const _ActionCheckbox({
    required this.isCompleted,
    required this.isAnimating,
    required this.categoryColor,
    required this.onTap,
  });

  final bool isCompleted;
  final bool isAnimating;
  final Color categoryColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: true,
      label: isCompleted
          ? 'Completed. Tap to mark as not done'
          : 'Mark action as complete',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
        scale: isAnimating ? 1.2 : 1.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutBack,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: isCompleted
                ? categoryColor.withOpacity(0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isCompleted
                  ? categoryColor
                  : Theme.of(context).colorScheme.outline.withOpacity(0.4),
              width: isCompleted ? 2 : 1.5,
            ),
          ),
          child: AnimatedOpacity(
            opacity: isCompleted ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: Icon(
              Icons.check_rounded,
              size: 18,
              color: categoryColor,
            ),
          ),
        ),
      ),
      ),
    );
  }
}
