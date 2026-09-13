import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../features/habit_builder/domain/habit_models.dart';
import '../features/habit_builder/domain/habit_templates.dart';
import '../features/habit_builder/presentation/challenge_engine_section.dart';
import '../features/habit_builder/presentation/habit_builder_state.dart';
import '../services/notification_service.dart';

// Tool screens
import '../features/calorie_budget/presentation/calorie_budget_screen.dart';
import '../features/hydration/presentation/hydration_coach_screen.dart';
import '../features/meal_planner/presentation/meal_planner_screen.dart';
import '../features/meditation/presentation/meditation_home_screen.dart';
import '../features/nutrition/presentation/nutrition_coach_screen.dart';
import '../features/sleep/presentation/sleep_coach_screen.dart';
import 'period_tracker_screen.dart';
import 'travel_screen.dart';
import 'weight_tracker_screen.dart';
import '../widgets/toolkit_customize_sheet.dart';

/// Habit Builder — bottom-nav level screen (index 2).
///
/// Matches the Wellness Intentions AppBar pattern: plain AppBar,
/// centerTitle: false, bold title, + in actions row.
///
/// Shows today's habit checklist, streak / completion summary, tool shortcuts,
/// and the ability to add habits from curated suggestions or from scratch.
class HabitBuilderScreen extends StatefulWidget {
  const HabitBuilderScreen({super.key});

  @override
  State<HabitBuilderScreen> createState() => _HabitBuilderScreenState();
}

class _HabitBuilderScreenState extends State<HabitBuilderScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => context.read<HabitBuilderState>().load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A habit toggled from the home-screen widget writes to SharedPreferences
    // from a background isolate; reload on resume so the in-app list reflects it.
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<HabitBuilderState>().load();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tab.dispose();
    super.dispose();
  }

  void _openAddSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AddHabitSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0F1115) : const Color(0xFFF8F9FB),
      appBar: _buildAppBar(context),
      body: TabBarView(
        controller: _tab,
        children: const [
          _TodayTab(),
          _AllHabitsTab(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return PreferredSize(
      // kToolbarHeight (56) + progress bar row (~7) + TabBar (~44)
      preferredSize: const Size.fromHeight(kToolbarHeight + 7 + 44),
      child: Consumer<HabitBuilderState>(
        builder: (ctx, state, _) {
          final total = state.todaysHabits.length;
          final done = state.completedTodayCount;
          final pct = total == 0 ? 0.0 : done / total;
          final primary = Theme.of(context).colorScheme.primary;

          return AppBar(
            centerTitle: false,
            titleSpacing: 29,
            title: Row(
              children: [
                const Text(
                  'Habit Builder',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                if (total > 0) ...[
                  const SizedBox(width: 8),
                  Text(
                    '$done / $total',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: primary.withOpacity(0.8),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.add_circle_outline_rounded),
                onPressed: _openAddSheet,
                tooltip: 'Add Habit',
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(7 + 44),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Progress bar — only shown when habits exist.
                  if (total > 0)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: pct,
                          minHeight: 4,
                          backgroundColor: primary.withOpacity(0.12),
                          valueColor: AlwaysStoppedAnimation(primary),
                        ),
                      ),
                    ),
                  TabBar(
                    controller: _tab,
                    tabs: const [
                      Tab(text: 'Today'),
                      Tab(text: 'All Habits'),
                    ],
                    labelStyle: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700),
                    indicatorSize: TabBarIndicatorSize.label,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// =============================================================================
// Today Tab
// =============================================================================

class _TodayTab extends StatelessWidget {
  const _TodayTab();

  @override
  Widget build(BuildContext context) {
    return Consumer<HabitBuilderState>(builder: (ctx, state, _) {
      final habits = state.todaysHabits;

      if (habits.isEmpty) {
        return _emptyToday(context);
      }

      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        children: [
          _sectionLabel(context, "Today's habits"),
          const SizedBox(height: 10),
          ...habits.map((h) => _HabitCheckTile(habit: h)),
          const _SectionDivider(),
          const ChallengeEngineSection(),
          const _SectionDivider(),
          Center(child: _sectionLabel(context, 'Jump to tool')),
          const SizedBox(height: 10),
          const _ToolGrid(),
        ],
      );
    });
  }

  Widget _emptyToday(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 120),
      child: Column(
        children: [
          Icon(Icons.checklist_rounded,
              size: 72,
              color: theme.colorScheme.primary.withOpacity(0.2)),
          const SizedBox(height: 20),
          Text('No habits for today',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            'Tap + to add your first habit.\nSmall daily actions compound into big changes.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
                height: 1.5,
                color: theme.colorScheme.onSurface.withOpacity(0.5)),
          ),
          const _SectionDivider(),
          const ChallengeEngineSection(),
          const _SectionDivider(),
          Center(child: _sectionLabel(context, 'Jump to tool')),
          const SizedBox(height: 10),
          const _ToolGrid(),
        ],
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String label) {
    final theme = Theme.of(context);
    return Text(label.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          color: theme.colorScheme.onSurface.withOpacity(0.45),
        ));
  }
}

// =============================================================================
// All Habits Tab
// =============================================================================

class _AllHabitsTab extends StatelessWidget {
  const _AllHabitsTab();

  @override
  Widget build(BuildContext context) {
    return Consumer<HabitBuilderState>(builder: (ctx, state, _) {
      if (state.habits.isEmpty) {
        return _emptyAll(context);
      }

      final active = state.habits.where((h) => h.isActive).toList();
      final paused = state.habits.where((h) => !h.isActive).toList();

      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        children: [
          if (active.isNotEmpty) ...[
            _label(context, 'Active'),
            const SizedBox(height: 10),
            ...active.map((h) => _HabitManageTile(habit: h)),
            const SizedBox(height: 20),
          ],
          if (paused.isNotEmpty) ...[
            _label(context, 'Paused'),
            const SizedBox(height: 10),
            ...paused.map((h) => _HabitManageTile(habit: h)),
            const SizedBox(height: 20),
          ],
          const _SectionDivider(),
          const ChallengeEngineSection(),
          const _SectionDivider(),
          Center(child: _label(context, 'Jump to tool')),
          const SizedBox(height: 10),
          const _ToolGrid(),
        ],
      );
    });
  }

  Widget _emptyAll(BuildContext context) {
    final theme = Theme.of(context);
    // Keep the Challenges section visible even when there are no habits yet.
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 40, 16, 120),
      children: [
        Column(
          children: [
            Icon(Icons.track_changes_rounded,
                size: 64,
                color: theme.colorScheme.primary.withOpacity(0.2)),
            const SizedBox(height: 20),
            Text('No habits yet',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'Tap + to add habits from suggestions or create your own.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                  height: 1.5,
                  color: theme.colorScheme.onSurface.withOpacity(0.5)),
            ),
          ],
        ),
        const _SectionDivider(),
        const ChallengeEngineSection(),
        const _SectionDivider(),
        Center(child: _label(context, 'Jump to tool')),
        const SizedBox(height: 10),
        const _ToolGrid(),
      ],
    );
  }

  Widget _label(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Text(text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          color: theme.colorScheme.onSurface.withOpacity(0.45),
        ));
  }
}

// =============================================================================
// Section divider — visually separates major sections (habits / challenges /
// tools) with padding and a soft line.
// =============================================================================

class _SectionDivider extends StatelessWidget {
  const _SectionDivider();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).dividerColor.withOpacity(0.5);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Divider(height: 1, thickness: 1, color: color),
    );
  }
}

// =============================================================================
// Habit check tile (Today tab)
// =============================================================================

class _HabitCheckTile extends StatelessWidget {
  final Habit habit;
  const _HabitCheckTile({required this.habit});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final done = habit.isCompletedToday;
    final streak = habit.currentStreak;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        context.read<HabitBuilderState>().toggleToday(habit.id);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: done
              ? theme.colorScheme.primary.withOpacity(0.08)
              : (isDark ? const Color(0xFF1E2124) : Colors.white),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: done
                ? theme.colorScheme.primary.withOpacity(0.35)
                : theme.colorScheme.onSurface.withOpacity(0.08),
            width: done ? 1.5 : 1,
          ),
          boxShadow: done
              ? null
              : [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2))
                ],
        ),
        child: Row(
          children: [
            // Checkbox circle.
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? theme.colorScheme.primary : Colors.transparent,
                border: Border.all(
                  color: done
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface.withOpacity(0.3),
                  width: 2,
                ),
              ),
              child: done
                  ? const Icon(Icons.check_rounded,
                      color: Colors.white, size: 16)
                  : null,
            ),
            const SizedBox(width: 14),
            // Text.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(habit.title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        decoration:
                            done ? TextDecoration.lineThrough : null,
                        color: done
                            ? theme.colorScheme.onSurface.withOpacity(0.45)
                            : null,
                      )),
                  if (habit.targetValue != null && habit.targetUnit != null)
                    Text(
                      '${habit.targetValue!.toStringAsFixed(habit.targetValue! % 1 == 0 ? 0 : 1)} ${habit.targetUnit}',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color:
                              theme.colorScheme.onSurface.withOpacity(0.5)),
                    ),
                ],
              ),
            ),
            // Tool emoji + streak.
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(habit.tool.emoji,
                    style: const TextStyle(fontSize: 18)),
                if (streak > 1)
                  Text('$streak 🔥',
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.orange,
                          fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Habit manage tile (All Habits tab)
// =============================================================================

class _HabitManageTile extends StatelessWidget {
  final Habit habit;
  const _HabitManageTile({required this.habit});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2124) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Text(habit.tool.emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(habit.title,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  '${habit.tool.label} · ${habit.frequency.label}',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color:
                          theme.colorScheme.onSurface.withOpacity(0.5)),
                ),
                if (habit.currentStreak > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '${habit.currentStreak} day streak 🔥',
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.orange,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              habit.isActive
                  ? Icons.pause_circle_outline_rounded
                  : Icons.play_circle_outline_rounded,
              color: habit.isActive
                  ? theme.colorScheme.onSurface.withOpacity(0.4)
                  : theme.colorScheme.primary,
            ),
            onPressed: () =>
                context.read<HabitBuilderState>().toggleActive(habit.id),
          ),
          // Reminder (clock) — set/edit/clear a daily reminder time.
          IconButton(
            tooltip: habit.hasReminder
                ? 'Reminder ${habit.reminderLabel}'
                : 'Set reminder',
            icon: Icon(
              habit.hasReminder
                  ? Icons.alarm_on_rounded
                  : Icons.alarm_add_rounded,
              color: habit.hasReminder
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface.withOpacity(0.4),
            ),
            onPressed: () => _openReminderPicker(context),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline_rounded,
                color: Colors.red.withOpacity(0.7)),
            onPressed: () => _confirmDelete(context),
          ),
        ],
      ),
    );
  }

  Future<void> _openReminderPicker(BuildContext context) async {
    final state = context.read<HabitBuilderState>();

    // If a reminder already exists, let the user edit or remove it.
    if (habit.hasReminder) {
      final action = await showModalBottomSheet<String>(
        context: context,
        builder: (sheetContext) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.alarm_on_rounded),
                title: Text('Reminder at ${habit.reminderLabel}'),
                subtitle: const Text('Daily on this habit\'s schedule'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.edit_rounded),
                title: const Text('Change time'),
                onTap: () => Navigator.pop(sheetContext, 'edit'),
              ),
              ListTile(
                leading: const Icon(Icons.alarm_off_rounded,
                    color: Colors.red),
                title: const Text('Remove reminder',
                    style: TextStyle(color: Colors.red)),
                onTap: () => Navigator.pop(sheetContext, 'remove'),
              ),
            ],
          ),
        ),
      );
      if (action == 'remove') {
        await state.clearReminder(habit.id);
        return;
      }
      if (action != 'edit') return; // dismissed
    }

    if (!context.mounted) return;
    await _pickTimeAndSchedule(context, state);
  }

  Future<void> _pickTimeAndSchedule(
      BuildContext context, HabitBuilderState state) async {
    final initial = habit.hasReminder
        ? TimeOfDay(hour: habit.reminderHour!, minute: habit.reminderMinute!)
        : const TimeOfDay(hour: 9, minute: 0);

    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: 'Set reminder time',
    );
    if (picked == null) return;

    // Make sure we have notification permission before scheduling.
    final notifier = NotificationService();
    final granted = await notifier.hasNotificationPermission()
        ? true
        : await notifier.requestPermission();

    await state.setReminder(habit.id, picked.hour, picked.minute);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(granted
              ? 'Reminder set for ${habit.title} at ${picked.format(context)}'
              : 'Reminder saved, but notifications are disabled. Enable them in Settings to be reminded.'),
        ),
      );
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            title: const Text('Remove habit?'),
            content: Text(
                'This will delete "${habit.title}" and all its history.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel')),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Remove'),
              ),
            ],
          ),
        ) ??
        false;
    if (ok && context.mounted) {
      context.read<HabitBuilderState>().deleteHabit(habit.id);
    }
  }
}

// =============================================================================
// Tool Grid (shortcuts to each wellness tool)
// =============================================================================

class _ToolGrid extends StatefulWidget {
  const _ToolGrid();

  @override
  State<_ToolGrid> createState() => _ToolGridState();
}

class _ToolGridState extends State<_ToolGrid> {
  // Ids match ToolkitCustomize.tools so the grid filters on the same
  // visibility state the Customize Toolkit sheet writes.
  static final List<_ToolShortcut> _tools = [
    _ToolShortcut('nutrition', 'Nutrition\nCoach', '🥗', const Color(0xFF57B894),
        const NutritionCoachScreen()),
    _ToolShortcut('meal_planner', 'Meal\nPlanner', '🍽️', const Color(0xFFEF8354),
        const MealPlannerScreen()),
    _ToolShortcut('calorie_budget', 'Calorie\nBudget', '🔥',
        const Color(0xFFF5A623), const CalorieBudgetScreen()),
    _ToolShortcut('hydration', 'Hydration\nCoach', '💧', const Color(0xFF3FA9F5),
        const HydrationCoachScreen()),
    _ToolShortcut('sleep', 'Sleep\nCoach', '🌙', const Color(0xFF6C63FF),
        const SleepCoachEntry()),
    _ToolShortcut('meditation', 'Meditation\nPal', '🧘', const Color(0xFF9B59B6),
        const MeditationHomeScreen()),
    _ToolShortcut('period', 'Period\nTracker', '🌸', const Color(0xFFE9506E),
        const PeriodTrackerScreen()),
    _ToolShortcut('weight', 'Body\nWeight', '⚖️', const Color(0xFF2ECC71),
        const WeightTrackerScreen()),
    _ToolShortcut('travel', 'Mindful\nTravel', '✈️', const Color(0xFF3A7BD5),
        const TravelScreen()),
  ];

  Set<String> _hidden = {};

  @override
  void initState() {
    super.initState();
    _loadHidden();
  }

  Future<void> _loadHidden() async {
    final hidden = await ToolkitCustomize.loadHiddenTools();
    if (mounted) setState(() => _hidden = hidden);
  }

  Future<void> _openCustomize() async {
    await showToolkitCustomizeSheet(context);
    // Refresh the grid so newly hidden/shown tools are reflected immediately.
    await _loadHidden();
  }

  @override
  Widget build(BuildContext context) {
    final visible =
        _tools.where((t) => !_hidden.contains(t.id)).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.05,
          ),
          itemCount: visible.length,
          itemBuilder: (_, i) => _ToolTile(shortcut: visible[i]),
        ),
        const SizedBox(height: 10),
        _CustomizeToolkitButton(onPressed: _openCustomize),
      ],
    );
  }
}

/// A "Customize Toolkit" button matching the Life Toolkit section's customize
/// affordance. Opens the shared Customize Toolkit sheet where the user can
/// toggle which tools appear — kept in sync with the Life Toolkit screen.
class _CustomizeToolkitButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _CustomizeToolkitButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.tune_rounded, size: 18),
      label: const Text('Customize Toolkit'),
      style: OutlinedButton.styleFrom(
        foregroundColor: primary,
        side: BorderSide(color: primary.withOpacity(0.4)),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ToolShortcut {
  final String id;
  final String label;
  final String emoji;
  final Color color;
  final Widget screen;
  const _ToolShortcut(this.id, this.label, this.emoji, this.color, this.screen);
}

class _ToolTile extends StatelessWidget {
  final _ToolShortcut shortcut;
  const _ToolTile({required this.shortcut});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => shortcut.screen)),
      child: Container(
        decoration: BoxDecoration(
          color: isDark
              ? shortcut.color.withOpacity(0.15)
              : shortcut.color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border:
              Border.all(color: shortcut.color.withOpacity(0.25), width: 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(shortcut.emoji, style: const TextStyle(fontSize: 26)),
            const SizedBox(height: 6),
            Text(
              shortcut.label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                height: 1.25,
                color: shortcut.color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Add Habit Bottom Sheet
// =============================================================================

class _AddHabitSheet extends StatefulWidget {
  const _AddHabitSheet();

  @override
  State<_AddHabitSheet> createState() => _AddHabitSheetState();
}

class _AddHabitSheetState extends State<_AddHabitSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(28)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 10),
            Text('Add a Habit',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            TabBar(
              controller: _tab,
              tabs: const [
                Tab(text: 'Suggestions'),
                Tab(text: 'Custom'),
              ],
              labelStyle:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              indicatorSize: TabBarIndicatorSize.label,
            ),
            SizedBox(
              height: 380,
              child: TabBarView(
                controller: _tab,
                children: const [
                  _SuggestionsTab(),
                  _CustomHabitForm(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Suggestions tab
// =============================================================================

class _SuggestionsTab extends StatefulWidget {
  const _SuggestionsTab();

  @override
  State<_SuggestionsTab> createState() => _SuggestionsTabState();
}

class _SuggestionsTabState extends State<_SuggestionsTab> {
  HabitTool? _filter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final templates = _filter == null
        ? HabitTemplateCatalog.all
        : HabitTemplateCatalog.forTool(_filter!);

    return Column(
      children: [
        // Tool filter chips.
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            children: [
              _chip(context, 'All', _filter == null,
                  () => setState(() => _filter = null)),
              ...HabitTool.values.map((t) => _chip(
                    context,
                    t.emoji,
                    _filter == t,
                    () => setState(() => _filter = t),
                    tooltip: t.label,
                  )),
            ],
          ),
        ),
        // Template list.
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: templates.length,
            itemBuilder: (_, i) {
              final t = templates[i];
              return ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                leading: Text(t.tool.emoji,
                    style: const TextStyle(fontSize: 22)),
                title: Text(t.title,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                subtitle: Text(t.description,
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withOpacity(0.5))),
                trailing: IconButton(
                  icon: Icon(Icons.add_circle_rounded,
                      color: theme.colorScheme.primary),
                  onPressed: () async {
                    await context.read<HabitBuilderState>().createHabit(
                          title: t.title,
                          description: t.description,
                          tool: t.tool,
                          frequency: t.frequency,
                          targetValue: t.targetValue,
                          targetUnit: t.targetUnit,
                        );
                    if (context.mounted) Navigator.pop(context);
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _chip(BuildContext ctx, String label, bool selected,
      VoidCallback onTap, {String? tooltip}) {
    final theme = Theme.of(ctx);
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: tooltip ?? '',
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(right: 8),
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : theme.colorScheme.primary)),
        ),
      ),
    );
  }
}

// =============================================================================
// Custom habit form
// =============================================================================

class _CustomHabitForm extends StatefulWidget {
  const _CustomHabitForm();

  @override
  State<_CustomHabitForm> createState() => _CustomHabitFormState();
}

class _CustomHabitFormState extends State<_CustomHabitForm> {
  final _titleCtrl = TextEditingController();
  final _targetCtrl = TextEditingController();
  final _unitCtrl = TextEditingController();
  HabitTool _tool = HabitTool.custom;
  HabitFrequency _freq = HabitFrequency.daily;
  bool _saving = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _targetCtrl.dispose();
    _unitCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    final target = double.tryParse(_targetCtrl.text.trim());
    final unit =
        _unitCtrl.text.trim().isEmpty ? null : _unitCtrl.text.trim();
    await context.read<HabitBuilderState>().createHabit(
          title: _titleCtrl.text.trim(),
          tool: _tool,
          frequency: _freq,
          targetValue: target,
          targetUnit: unit,
        );
    if (mounted) {
      setState(() => _saving = false);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _titleCtrl,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'Habit name',
              hintText: 'e.g. Walk 8,000 steps',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14)),
              filled: true,
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<HabitTool>(
            value: _tool,
            decoration: InputDecoration(
              labelText: 'Related tool',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14)),
              filled: true,
            ),
            items: HabitTool.values
                .map((t) => DropdownMenuItem(
                    value: t,
                    child: Text('${t.emoji} ${t.label}')))
                .toList(),
            onChanged: (v) => setState(() => _tool = v!),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<HabitFrequency>(
            value: _freq,
            decoration: InputDecoration(
              labelText: 'Frequency',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14)),
              filled: true,
            ),
            items: HabitFrequency.values
                .map((f) =>
                    DropdownMenuItem(value: f, child: Text(f.label)))
                .toList(),
            onChanged: (v) => setState(() => _freq = v!),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _targetCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'Target (optional)',
                    hintText: '8000',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14)),
                    filled: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _unitCtrl,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: 'Unit (optional)',
                    hintText: 'steps',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14)),
                    filled: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14))),
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Add habit',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}
