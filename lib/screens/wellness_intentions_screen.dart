import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lottie/lottie.dart';

import '../models/wellness_intention.dart';
import '../models/wellness_enums.dart';
import '../providers/app_state.dart';
import '../services/auth_service.dart';
import '../utils/icon_resolver.dart';
import '../utils/wellnesspal_snackbar.dart';
import '../widgets/custom_tab_switcher.dart';
import '../widgets/frosted_container.dart';
import 'add_dream_screen.dart';
import 'wellness_intention_detail_screen.dart';

class WellnessIntentionsScreen extends StatefulWidget {
  const WellnessIntentionsScreen({super.key});

  @override
  State<WellnessIntentionsScreen> createState() =>
      _WellnessIntentionsScreenState();
}

class _WellnessIntentionsScreenState extends State<WellnessIntentionsScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Tracks inline error messages per intention id.
  final Map<String, String?> _intentionErrors = {};

  /// Tracks which intentions are being deactivated (for optimistic UI revert).
  final Set<String> _deactivating = {};

  /// Step ids that were just checked — shown with a green tick briefly before
  /// the card advances to the next step, so the user sees their tap register.
  final Set<String> _justCompletedSteps = {};

  /// Error message shown when adding a new intention fails.
  String? _addError;

  // --- Helpers ---

  List<WellnessIntention> _activeIntentions(AppState appState) {
    return appState.intentions.where((i) => i.isActive).toList();
  }

  /// Marks the current active step complete from the card. The screen rebuilds
  /// via [Consumer<AppState>], so the next incomplete step becomes the active
  /// one automatically.
  Future<void> _completeActiveStep(
      WellnessIntention intention, String stepId) async {
    if (_justCompletedSteps.contains(stepId)) return; // Guard double-taps.

    // 1. Immediately show the tick on the step the user just tapped.
    setState(() => _justCompletedSteps.add(stepId));

    // 2. Brief pause so the checked state is visible before the card advances.
    await Future.delayed(const Duration(milliseconds: 450));

    // 3. Persist completion — the Consumer rebuild then reveals the next step.
    if (!mounted) return;
    final appState = Provider.of<AppState>(context, listen: false);
    await appState.toggleStepCompletion(intention.id, stepId);

    if (mounted) {
      setState(() => _justCompletedSteps.remove(stepId));
    }
  }

  /// Shows the current active step for an intention — the first incomplete
  /// step (or the first step if none are complete). Renders nothing when the
  /// intention has no steps; shows a completion note when all are done.
  Widget _buildActiveStep(
      BuildContext context, WellnessIntention intention, Color themeColor) {
    final steps = intention.steps;
    if (steps.isEmpty) return const SizedBox(height: 12);

    final activeStep = steps.firstWhere(
      (s) => !s.isCompleted,
      orElse: () => steps.last,
    );
    final allDone = steps.every((s) => s.isCompleted);
    // The active step is mid-confirmation (just tapped): show it as checked
    // before the card advances to the next step.
    final justChecked = _justCompletedSteps.contains(activeStep.id);
    final showChecked = allDone || justChecked;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            allDone ? 'Completed' : 'Current step',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.5),
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 6),
          // Step shown as-is with a tappable checkbox — full text, wraps over
          // multiple lines/sentences (matches the intention detail's step row).
          // Checking the box completes the step; the card then rebuilds and
          // shows the next active step.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Tappable checkbox. Its own gesture handler consumes the tap so
              // it doesn't also trigger the card's navigation.
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: showChecked
                    ? null
                    : () => _completeActiveStep(intention, activeStep.id),
                child: Padding(
                  // Enlarged hit target around the icon.
                  padding: const EdgeInsets.only(right: 10, bottom: 4),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder: (child, anim) =>
                        ScaleTransition(scale: anim, child: child),
                    child: Icon(
                      // Show the filled green tick once checked (or all done).
                      showChecked
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      key: ValueKey(showChecked),
                      size: 22,
                      color: showChecked ? Colors.green : themeColor,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  allDone ? 'All steps complete 🎉' : activeStep.title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                    color: theme.colorScheme.onSurface.withOpacity(0.85),
                    // Strike through the moment it's checked.
                    decoration: justChecked ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Shortens a wellness intention title for compact display on cards.
  /// Truncates to [maxChars] on a word boundary and appends an ellipsis.
  String _shortTitle(String title, {int maxChars = 28}) {
    final t = title.trim();
    if (t.length <= maxChars) return t;
    var cut = t.substring(0, maxChars);
    final lastSpace = cut.lastIndexOf(' ');
    if (lastSpace > maxChars * 0.6) {
      cut = cut.substring(0, lastSpace);
    }
    return '${cut.trimRight()}…';
  }

  String _categoryLabel(WellnessCategory category) {
    switch (category) {
      case WellnessCategory.flexibility:
        return 'Flexibility';
      case WellnessCategory.stress:
        return 'Stress';
      case WellnessCategory.sleep:
        return 'Sleep';
      case WellnessCategory.movement:
        return 'Movement';
      case WellnessCategory.recovery:
        return 'Recovery';
      case WellnessCategory.energy:
        return 'Energy';
      case WellnessCategory.mentalClarity:
        return 'Mental Clarity';
      case WellnessCategory.mindfulness:
        return 'Mindfulness';
      case WellnessCategory.general:
        return 'General';
    }
  }

  IconData _categoryIcon(WellnessCategory category) {
    switch (category) {
      case WellnessCategory.flexibility:
        return Icons.self_improvement_rounded;
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
        return Icons.filter_vintage_rounded;
      case WellnessCategory.general:
        return Icons.star_rounded;
    }
  }

  // --- Actions ---

  /// Shows a modal asking the user to deactivate one intention before adding.
  void _showMaxActiveModal(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Maximum Reached',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'You can have up to 3 active wellness intentions. '
          'Please deactivate one before adding a new one.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Handles the "Add Intention" action. Enforces max 5 active.
  void _handleAddIntention(BuildContext context, AppState appState) {
    final active = _activeIntentions(appState);
    if (active.length >= 5) {
      _showMaxActiveModal(context);
      return;
    }

    // Navigate to the existing AddDreamScreen for adding
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddDreamScreen()),
    );
  }

  /// Deactivates an intention: sets isActive = false in Firestore.
  /// On failure, reverts the UI and shows an inline error.
  Future<void> _deactivateIntention(
      BuildContext context, WellnessIntention intention) async {
    final uid = AuthService().currentUser?.uid;
    if (uid == null) return;

    final appState = Provider.of<AppState>(context, listen: false);

    setState(() {
      _deactivating.add(intention.id);
      _intentionErrors[intention.id] = null;
    });

    try {
      // Use set(merge:true) rather than update(): the intention may not yet
      // have a Firestore document (e.g. it was created locally and only lives
      // in the SharedPreferences-backed dreams list). update() throws
      // 'not-found' on a missing doc, which is what produced the generic
      // "Failed to deactivate" error. set(merge:true) creates-or-updates.
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('wellness_intentions')
          .doc(intention.id)
          .set({'isActive': false}, SetOptions(merge: true));

      // Remove from local dreams list so UI updates immediately
      if (mounted) {
        await appState.deleteDream(intention.id);
      }
    } catch (e) {
      // Surface the real error for debugging, keep a friendly UI message.
      debugPrint('❌ Failed to deactivate intention ${intention.id}: $e');
      // Revert — show inline error, do NOT remove from active list
      if (mounted) {
        setState(() {
          _intentionErrors[intention.id] =
              'Failed to deactivate. Please try again.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _deactivating.remove(intention.id);
        });
      }
    }
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        final active = _activeIntentions(appState);
        // Split active intentions by completion state (all steps done).
        final todo = active.where((i) => !i.isCompleted).toList();
        final completed = active.where((i) => i.isCompleted).toList();

        return Scaffold(
          appBar: AppBar(
            centerTitle: false,
            titleSpacing: 29,
            title: const Text(
              'Wellness Intentions',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.add_circle_outline_rounded),
                onPressed: () => _handleAddIntention(context, appState),
                tooltip: 'Add Intention',
              ),
            ],
          ),
          body: Column(
            children: [
              const SizedBox(height: 5),
              CustomTabSwitcher(
                tabController: _tabController,
                tabs: const ['To Do', 'Completed'],
                icons: const [
                  Icons.radio_button_unchecked_rounded,
                  Icons.check_circle_rounded,
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    todo.isEmpty
                        ? _buildEmptyState(
                            context,
                            title: 'No active intentions yet.',
                            subtitle:
                                'Tap + to set your first wellness intention.',
                          )
                        : _buildIntentionsList(context, todo),
                    completed.isEmpty
                        ? _buildEmptyState(
                            context,
                            title: 'No completed intentions yet.',
                            subtitle:
                                'Finish all steps of an intention to see it here.',
                          )
                        : _buildIntentionsList(context, completed),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(
    BuildContext context, {
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Lottie.asset(
            'assets/images/wellness-rhythm.json',
            height: 280,
            repeat: true,
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildIntentionsList(
      BuildContext context, List<WellnessIntention> intentions) {
    // Progress per intention is derived from its own task-step completion
    // (see intention.stepProgress in _buildIntentionCard).
    return ListView.builder(
      // Extra bottom padding so the last card clears the FAB / bottom nav and
      // stays fully visible when scrolled to the end.
      padding: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 100),
      itemCount: intentions.length + (_addError != null ? 1 : 0),
      itemBuilder: (context, index) {
        if (_addError != null && index == 0) {
          return _buildAddErrorBanner();
        }
        final i = _addError != null ? index - 1 : index;
        final intention = intentions[i];
        return _buildIntentionCard(context, intention);
      },
    );
  }

  Widget _buildAddErrorBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: Colors.red.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _addError!,
              style: TextStyle(color: Colors.red.shade700, fontSize: 13),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => setState(() => _addError = null),
          ),
        ],
      ),
    );
  }

  Widget _buildIntentionCard(BuildContext context, WellnessIntention intention) {
    final themeColor = intention.themeColor != null
        ? Color(intention.themeColor!)
        : Theme.of(context).colorScheme.primary;
    final themeIcon = intention.themeIcon != null
        ? resolveIconData(intention.themeIcon!)
        : _categoryIcon(intention.category);
    // Progress reflects the intention's own task-step completion.
    final progress = intention.stepProgress;
    final progressPct = (progress * 100).toInt();
    final errorMsg = _intentionErrors[intention.id];
    final isDeactivating = _deactivating.contains(intention.id);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => WellnessIntentionDetailScreen(
              intentionId: intention.id,
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: FrostedContainer(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Theme icon
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: themeColor.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(themeIcon, color: themeColor, size: 24),
                    ),
                    const SizedBox(width: 16),
                    // Title + Category label
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _shortTitle(intention.title),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: themeColor.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _categoryLabel(intention.category),
                              style: TextStyle(
                                color: themeColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Pin-to-home-widget button. Only one intention can be on
                    // the home screen at a time, so only the pinned card shows
                    // active; tapping another card repins to it.
                    Consumer<AppState>(
                      builder: (context, appState, _) {
                        final pinned =
                            appState.isIntentionOnWidget(intention.id);
                        return IconButton(
                          icon: Icon(
                            pinned
                                ? Icons.widgets_rounded
                                : Icons.widgets_outlined,
                            color: pinned ? themeColor : Colors.grey.shade400,
                          ),
                          tooltip: pinned
                              ? 'Pinned to home screen'
                              : 'Pin to home screen',
                          onPressed: () {
                            appState
                                .togglePinIntentionToWidget(intention.id);
                            WellnessPalSnackBar.show(
                              context,
                              message: appState.isIntentionOnWidget(
                                      intention.id)
                                  ? 'Pinned to home screen widget'
                                  : 'Removed from home screen widget',
                              icon: Icons.widgets_rounded,
                            );
                          },
                        );
                      },
                    ),
                    // Deactivate button
                    IconButton(
                      icon: isDeactivating
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.grey.shade400,
                              ),
                            )
                          : Icon(Icons.remove_circle_outline_rounded,
                              color: Colors.grey.shade400),
                      tooltip: 'Deactivate',
                      onPressed: isDeactivating
                          ? null
                          : () => _deactivateIntention(context, intention),
                    ),
                  ],
                ),
                // Current active step (shown before the progress indicator).
                _buildActiveStep(context, intention, themeColor),
                const SizedBox(height: 16),
                // Progress bar + percentage text
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: progress,
                          backgroundColor: Colors.grey.shade200,
                          color: themeColor,
                          minHeight: 8,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '$progressPct%',
                      style: TextStyle(
                        color: themeColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                // Inline error
                if (errorMsg != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          color: Colors.red.shade600, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          errorMsg,
                          style: TextStyle(
                            color: Colors.red.shade600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0);
  }
}
