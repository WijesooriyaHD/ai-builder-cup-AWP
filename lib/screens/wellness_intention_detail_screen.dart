import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';

import '../models/wellness_intention.dart';
import '../models/wellness_enums.dart';
import '../models/challenge_step.dart';
import '../features/habit_builder/domain/habit_models.dart';
import '../providers/app_state.dart';
import '../services/ai_service.dart';
import '../services/auth_service.dart';
import '../utils/wellnesspal_snackbar.dart';
import '../widgets/frosted_container.dart';
import '../utils/icon_resolver.dart';
import 'habit_builder_screen.dart';

/// Detail screen for a single [WellnessIntention].
///
/// Displays: intention title, category badge, task list, step-based progress,
/// an intention-specific AI encouragement, and creation date.
///
/// Requirement 5.7
class WellnessIntentionDetailScreen extends StatefulWidget {
  final String intentionId;

  const WellnessIntentionDetailScreen({
    super.key,
    required this.intentionId,
  });

  @override
  State<WellnessIntentionDetailScreen> createState() =>
      _WellnessIntentionDetailScreenState();
}

class _WellnessIntentionDetailScreenState
    extends State<WellnessIntentionDetailScreen> {
  static const String _fallbackEncouragement =
      "You're making great progress on your wellness journey. "
      "Keep going at your own pace.";

  String _encouragementText = _fallbackEncouragement;
  bool _isLoadingEncouragement = true;

  /// Tracks the progress bucket the encouragement was generated for, so we can
  /// refresh the message as the user crosses meaningful milestones.
  int? _encouragementProgressBucket;

  /// When true, the task list shows up/down arrows for reordering and hides the
  /// "Add task" button.
  bool _isRearranging = false;

  @override
  void initState() {
    super.initState();
    // Defer so Provider is available; load intention-specific encouragement.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadEncouragement();
    });
  }

  /// Finds this screen's intention from AppState, or null if it was removed.
  WellnessIntention? _currentIntention() {
    final appState = Provider.of<AppState>(context, listen: false);
    return appState.intentions.cast<WellnessIntention?>().firstWhere(
          (i) => i!.id == widget.intentionId,
          orElse: () => null,
        );
  }

  /// Buckets progress into coarse milestones (0, 25, 50, 75, 100) so we only
  /// regenerate the AI message when the user meaningfully advances.
  int _progressBucket(double progress) {
    final pct = (progress * 100).round();
    if (pct >= 100) return 100;
    if (pct >= 75) return 75;
    if (pct >= 50) return 50;
    if (pct >= 25) return 25;
    return 0;
  }

  /// Generates an intention-specific encouragement message.
  ///
  /// Uses the intention title + task progress as the AI context so the message
  /// is about THIS intention (not today's plan). Always leaves a usable message
  /// in [_encouragementText] — the LLM result on success, or a tailored local
  /// fallback otherwise — so the section never renders empty.
  Future<void> _loadEncouragement() async {
    final intention = _currentIntention();
    if (intention == null) {
      if (mounted) setState(() => _isLoadingEncouragement = false);
      return;
    }

    final total = intention.steps.length;
    final done = intention.steps.where((s) => s.isCompleted).length;
    final progress = intention.stepProgress;
    _encouragementProgressBucket = _progressBucket(progress);

    // A tailored local fallback (used offline or if the AI call fails).
    final localFallback = _localEncouragement(intention.title, done, total);

    final uid = AuthService().currentUser?.uid;
    if (uid == null) {
      if (mounted) {
        setState(() {
          _encouragementText = localFallback;
          _isLoadingEncouragement = false;
        });
      }
      return;
    }

    try {
      final aiService = AIService();
      final summary = _buildIntentionSummary(intention, done, total);
      final insight = await aiService.generateWellnessInsight(
        userId: uid,
        summary: summary,
      );
      if (mounted) {
        setState(() {
          _encouragementText =
              (insight != null && insight.trim().isNotEmpty)
                  ? insight
                  : localFallback;
          _isLoadingEncouragement = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _encouragementText = localFallback;
          _isLoadingEncouragement = false;
        });
      }
    }
  }

  /// Builds a plain-text summary of the intention for the AI insight prompt.
  String _buildIntentionSummary(
      WellnessIntention intention, int done, int total) {
    final buffer = StringBuffer();
    buffer.writeln('Wellness intention: ${intention.title}');
    buffer.writeln('Category: ${_categoryLabel(intention.category)}');
    if (total > 0) {
      buffer.writeln('Progress: $done of $total tasks completed.');
      final remaining = intention.steps
          .where((s) => !s.isCompleted)
          .map((s) => s.title)
          .take(3)
          .toList();
      if (remaining.isNotEmpty) {
        buffer.writeln('Next up: ${remaining.join(", ")}.');
      }
    }
    return buffer.toString().trim();
  }

  /// A warm, progress-aware local message used when the AI is unavailable.
  String _localEncouragement(String title, int done, int total) {
    if (total == 0) {
      return "You've set your intention to \"$title.\" That first step of naming "
          "what matters is meaningful. Take it one gentle action at a time.";
    }
    if (done == 0) {
      return "\"$title\" is ready to begin. Start with just the first task today — "
          "small, steady steps carry you further than you'd expect.";
    }
    if (done >= total) {
      return "You've completed every task for \"$title.\" That's real dedication to "
          "your wellbeing. Take a moment to appreciate how far you've come.";
    }
    return "You're $done of $total tasks into \"$title.\" Each step you complete is "
        "an act of care for yourself. Keep going at your own pace.";
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

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        final intention =
            appState.intentions.cast<WellnessIntention?>().firstWhere(
                  (i) => i!.id == widget.intentionId,
                  orElse: () => null,
                );

        if (intention == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Intention not found')),
          );
        }

        final progress = intention.stepProgress;
        final progressPct = (progress * 100).toInt();

        final themeColor = intention.themeColor != null
            ? Color(intention.themeColor!)
            : Theme.of(context).colorScheme.primary;
        final themeIcon = intention.themeIcon != null
            ? resolveIconData(intention.themeIcon!)
            : _categoryIcon(intention.category);

        return Scaffold(
          body: CustomScrollView(
            slivers: [
              _buildAppBar(context, intention, themeColor, themeIcon),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildCategoryBadge(context, intention, themeColor),
                      const SizedBox(height: 20),
                      _buildTaskListCard(context, intention, themeColor),
                      const SizedBox(height: 16),
                      _buildProgressCard(
                          context, intention, progressPct, progress, themeColor),
                      const SizedBox(height: 16),
                      _buildEncouragementCard(context, themeColor),
                      const SizedBox(height: 16),
                      _buildCreationDateCard(context, intention),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAppBar(BuildContext context, WellnessIntention intention,
      Color themeColor, IconData themeIcon) {
    return SliverAppBar(
      expandedHeight: 200.0,
      floating: false,
      pinned: true,
      backgroundColor: themeColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      flexibleSpace: FlexibleSpaceBar(
        title: Text(
          intention.title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            shadows: [Shadow(color: Colors.black45, blurRadius: 10)],
          ),
        ),
        background: Container(
          decoration: BoxDecoration(
            color: themeColor,
            borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(32)),
          ),
          child: Center(
            child: Icon(themeIcon,
                size: 80, color: Colors.white.withOpacity(0.3)),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryBadge(
      BuildContext context, WellnessIntention intention, Color themeColor) {
    return FrostedContainer(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_categoryIcon(intention.category),
                color: themeColor, size: 20),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: themeColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _categoryLabel(intention.category),
                style: TextStyle(
                  color: themeColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 400.ms);
  }

  Widget _buildTaskListCard(
      BuildContext context, WellnessIntention intention, Color themeColor) {
    final steps = intention.steps;
    final completedCount = steps.where((s) => s.isCompleted).length;
    final hasSteps = steps.isNotEmpty;

    return FrostedContainer(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.checklist_rounded, color: themeColor, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Task List',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                // Rearrange toggle (only meaningful with 2+ tasks).
                if (steps.length > 1)
                  GestureDetector(
                    onTap: () =>
                        setState(() => _isRearranging = !_isRearranging),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: themeColor.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _isRearranging
                            ? Icons.check_rounded
                            : Icons.reorder_rounded,
                        size: 18,
                        color: themeColor,
                      ),
                    ),
                  ),
                const SizedBox(width: 10),
                Text(
                  '$completedCount/${steps.length}',
                  style: TextStyle(
                    color: themeColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (hasSteps)
              ...List.generate(steps.length, (index) {
                return _buildStepTile(
                    context, intention, steps[index], index, themeColor);
              })
            else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No tasks yet. Add one to start tracking progress.',
                  style: TextStyle(
                      color: Colors.grey.shade500, fontSize: 13),
                ),
              ),
            // Add-task button (hidden while rearranging).
            if (!_isRearranging) ...[
              const SizedBox(height: 8),
              InkWell(
                onTap: () =>
                    _showAddStepDialog(context, intention, themeColor),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: themeColor.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_rounded, color: themeColor, size: 20),
                      const SizedBox(width: 6),
                      Text('Add task',
                          style: TextStyle(
                              color: themeColor,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ).animate().fadeIn(duration: 400.ms, delay: 50.ms);
  }

  Widget _buildStepTile(BuildContext context, WellnessIntention intention,
      ChallengeStep step, int index, Color themeColor) {
    final appState = Provider.of<AppState>(context, listen: false);
    final total = intention.steps.length;

    return InkWell(
      // Tapping toggles completion (disabled while rearranging).
      onTap: _isRearranging
          ? null
          : () async {
              await appState.toggleStepCompletion(intention.id, step.id);
              // Refresh encouragement if progress crossed a milestone bucket.
              final updated = _currentIntention();
              if (updated != null) {
                final bucket = _progressBucket(updated.stepProgress);
                if (bucket != _encouragementProgressBucket) {
                  _loadEncouragement();
                }
              }
            },
      // Long-press opens the edit/delete sheet.
      onLongPress: _isRearranging
          ? null
          : () => _showEditStepDialog(context, intention, step, themeColor),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              step.isCompleted
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: step.isCompleted ? themeColor : Colors.grey.shade400,
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step.title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: step.isCompleted
                          ? Colors.grey.shade500
                          : Theme.of(context).colorScheme.onSurface,
                      decoration: step.isCompleted
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  if (step.durationMinutes > 0) ...[
                    const SizedBox(height: 2),
                    Text(
                      '${step.durationMinutes} min',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Reorder arrows (only while rearranging).
            if (_isRearranging)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (index > 0)
                    GestureDetector(
                      onTap: () =>
                          _reorderStep(intention, index, index - 1),
                      child: Icon(Icons.keyboard_arrow_up_rounded,
                          size: 24, color: themeColor.withOpacity(0.7)),
                    ),
                  if (index < total - 1)
                    GestureDetector(
                      onTap: () =>
                          _reorderStep(intention, index, index + 1),
                      child: Icon(Icons.keyboard_arrow_down_rounded,
                          size: 24, color: themeColor.withOpacity(0.7)),
                    ),
                ],
              )
            // Overflow menu (3 dots) when not rearranging — add-as-habit / edit.
            else
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert_rounded,
                    size: 20, color: Colors.grey.shade500),
                tooltip: 'Step options',
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                onSelected: (value) {
                  switch (value) {
                    case 'habit':
                      _addStepAsHabit(intention, step);
                      break;
                    case 'edit':
                      _showEditStepDialog(context, intention, step, themeColor);
                      break;
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem<String>(
                    value: 'habit',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.playlist_add_check_rounded),
                      title: Text('Add as a habit'),
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'edit',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.edit_rounded),
                      title: Text('Edit task'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// Maps an intention's wellness [category] to the closest Habit Builder tool,
  /// so the Custom habit form's "Related tool" is sensibly pre-filled.
  HabitTool _habitToolForCategory(WellnessCategory category) {
    switch (category) {
      case WellnessCategory.sleep:
        return HabitTool.sleep;
      case WellnessCategory.stress:
      case WellnessCategory.mindfulness:
      case WellnessCategory.mentalClarity:
        return HabitTool.meditation;
      case WellnessCategory.movement:
      case WellnessCategory.energy:
        return HabitTool.calorieBudget;
      case WellnessCategory.flexibility:
      case WellnessCategory.recovery:
      case WellnessCategory.general:
        return HabitTool.custom;
    }
  }

  /// Opens the Habit Builder "Add a Habit" sheet on the Custom tab, pre-filled
  /// from this intention [step] so the user only has to confirm.
  void _addStepAsHabit(WellnessIntention intention, ChallengeStep step) {
    final descriptionParts = <String>[
      'From intention: ${intention.title}',
      if (step.durationMinutes > 0) 'Suggested: ${step.durationMinutes} min',
    ];

    showAddHabitSheet(
      context,
      initialTabIndex: 1, // Custom tab
      initialTitle: step.title,
      initialTool: _habitToolForCategory(intention.category),
      initialDescription: descriptionParts.join(' • '),
    );

    WellnessPalSnackBar.show(
      context,
      message: 'Review and confirm your new habit',
      icon: Icons.playlist_add_check_rounded,
    );
  }

  // ---------------------------------------------------------------------------
  // Task editing / reordering / adding
  // ---------------------------------------------------------------------------

  void _reorderStep(WellnessIntention intention, int oldIndex, int newIndex) {
    if (newIndex < 0 || newIndex >= intention.steps.length) return;
    final appState = Provider.of<AppState>(context, listen: false);
    final step = intention.steps.removeAt(oldIndex);
    intention.steps.insert(newIndex, step);
    appState.updateDream(intention);
  }

  void _showEditStepDialog(BuildContext context, WellnessIntention intention,
      ChallengeStep step, Color themeColor) {
    final controller = TextEditingController(text: step.title);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          decoration: BoxDecoration(
            color: Theme.of(ctx).cardColor,
            borderRadius: BorderRadius.circular(32),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(10))),
              const SizedBox(height: 16),
              Text('Edit Task',
                  style: Theme.of(ctx)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              TextField(
                controller: controller,
                autofocus: true,
                minLines: 1,
                maxLines: 3,
                style: const TextStyle(fontSize: 16),
                decoration: InputDecoration(
                  hintText: "What's the task?",
                  filled: true,
                  fillColor: Theme.of(ctx).brightness == Brightness.dark
                      ? Theme.of(ctx).scaffoldBackgroundColor
                      : Colors.grey[50],
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 16),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () {
                        final appState =
                            Provider.of<AppState>(context, listen: false);
                        intention.steps.removeWhere((s) => s.id == step.id);
                        appState.updateDream(intention);
                        Navigator.pop(ctx);
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.red.withOpacity(0.1),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text('Delete',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        final newTitle = controller.text.trim();
                        if (newTitle.isNotEmpty) {
                          final appState =
                              Provider.of<AppState>(context, listen: false);
                          final i = intention.steps
                              .indexWhere((s) => s.id == step.id);
                          if (i != -1) {
                            intention.steps[i] =
                                step.copyWith(title: newTitle);
                            appState.updateDream(intention);
                          }
                        }
                        Navigator.pop(ctx);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: themeColor,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text('Save',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddStepDialog(BuildContext context, WellnessIntention intention,
      Color themeColor) {
    final controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          decoration: BoxDecoration(
            color: Theme.of(ctx).cardColor,
            borderRadius: BorderRadius.circular(32),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(10))),
              const SizedBox(height: 16),
              Text('Add Task',
                  style: Theme.of(ctx)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              TextField(
                controller: controller,
                autofocus: true,
                minLines: 1,
                maxLines: 3,
                style: const TextStyle(fontSize: 16),
                decoration: InputDecoration(
                  hintText: "What's the next task?",
                  filled: true,
                  fillColor: Theme.of(ctx).brightness == Brightness.dark
                      ? Theme.of(ctx).scaffoldBackgroundColor
                      : Colors.grey[50],
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 16),
                ),
                onSubmitted: (_) => _submitNewStep(ctx, intention, controller),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () =>
                      _submitNewStep(ctx, intention, controller),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: themeColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('Add task',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _submitNewStep(BuildContext sheetContext,
      WellnessIntention intention, TextEditingController controller) {
    final title = controller.text.trim();
    if (title.isNotEmpty) {
      final appState = Provider.of<AppState>(context, listen: false);
      intention.steps.add(ChallengeStep(
        title: title,
        durationMinutes: 0,
        scheduledDate: DateTime.now(),
      ));
      appState.updateDream(intention);
    }
    Navigator.pop(sheetContext);
  }

  Widget _buildProgressCard(BuildContext context, WellnessIntention intention,
      int progressPct, double progress, Color themeColor) {
    final total = intention.steps.length;
    final done = intention.steps.where((s) => s.isCompleted).length;
    final caption = total > 0
        ? '$done of $total tasks completed'
        : 'Add tasks to start tracking your progress';

    return FrostedContainer(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Progress',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: Colors.grey.shade200,
                      color: themeColor,
                      minHeight: 10,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  '$progressPct%',
                  style: TextStyle(
                    color: themeColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              caption,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 400.ms, delay: 100.ms);
  }

  Widget _buildEncouragementCard(BuildContext context, Color themeColor) {
    return FrostedContainer(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome_rounded,
                    color: themeColor, size: 20),
                const SizedBox(width: 8),
                Text(
                  'AI Encouragement',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                if (_isLoadingEncouragement) ...[
                  const Spacer(),
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: themeColor,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            // Always render a message. While loading we show the current
            // text (a tailored fallback) at reduced opacity rather than an
            // empty section, so there is never a blank card.
            AnimatedOpacity(
              opacity: _isLoadingEncouragement ? 0.5 : 1.0,
              duration: const Duration(milliseconds: 200),
              child: Text(
                _encouragementText,
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 400.ms, delay: 300.ms);
  }

  Widget _buildCreationDateCard(
      BuildContext context, WellnessIntention intention) {
    final creationDate = intention.startDate;
    final formattedDate = DateFormat.yMMMd().format(creationDate);

    return FrostedContainer(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(Icons.calendar_today_rounded,
                color: Colors.grey.shade600, size: 20),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Created',
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  formattedDate,
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 400.ms, delay: 400.ms);
  }
}
