import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../nutrition/presentation/widgets/nutrition_cards.dart'
    show NutritionCard;
import '../domain/meditation_models.dart';
import 'meditation_state.dart';
import 'widgets/meditation_widgets.dart';

/// Configure local mindfulness reminders: toggle on/off, pick a time, and
/// choose which days each reminder is active. Persisted locally.
class MeditationRemindersScreen extends StatelessWidget {
  const MeditationRemindersScreen({super.key});

  static const _dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = context.watch<MeditationState>();
    final reminders = state.reminders;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reminders'),
        backgroundColor: kMeditationDeep,
        foregroundColor: Colors.white,
      ),
      body: reminders.isEmpty
          ? const MeditationEmptyState(
              emoji: '⏰',
              title: 'No reminders',
              message: 'Reminders help you keep a steady practice.',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                _buildInfoBanner(theme),
                const SizedBox(height: 16),
                for (final r in reminders) ...[
                  _buildReminder(context, theme, state, r),
                  const SizedBox(height: 12),
                ],
              ],
            ),
    );
  }

  Widget _buildInfoBanner(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kMeditationAccent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kMeditationAccent.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.notifications_active_rounded,
              color: kMeditationAccent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Turning a reminder on schedules a gentle notification at the '
              'chosen time and days. Allow notifications when prompted.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReminder(BuildContext context, ThemeData theme,
      MeditationState state, MindfulnessReminder r) {
    return NutritionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.label,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    GestureDetector(
                      onTap: () => _pickTime(context, state, r),
                      child: Text(
                        r.timeLabel,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: kMeditationAccent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: r.enabled,
                activeColor: kMeditationAccent,
                onChanged: (v) => _onToggle(context, state, r, v),
              ),
            ],
          ),
          if (r.enabled) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(7, (idx) {
                final weekday = idx + 1; // 1=Mon … 7=Sun
                final active = r.days.contains(weekday);
                return GestureDetector(
                  onTap: () => _toggleDay(state, r, weekday),
                  child: Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: active
                          ? kMeditationAccent
                          : kMeditationAccent.withOpacity(0.1),
                    ),
                    child: Text(
                      _dayLabels[idx],
                      style: TextStyle(
                        color: active
                            ? Colors.white
                            : theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickTime(
      BuildContext context, MeditationState state, MindfulnessReminder r) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: r.hour, minute: r.minute),
    );
    if (picked != null) {
      await state.updateReminder(
        r.copyWith(hour: picked.hour, minute: picked.minute),
      );
    }
  }

  Future<void> _onToggle(BuildContext context, MeditationState state,
      MindfulnessReminder r, bool value) async {
    final messenger = ScaffoldMessenger.of(context);
    await state.updateReminder(r.copyWith(enabled: value));
    if (!context.mounted) return;

    // If they turned it on but the OS didn't grant permission, tell them how
    // to fix it — otherwise the reminder would silently never fire.
    if (value && !state.notificationsAuthorized) {
      messenger.showSnackBar(
        SnackBar(
          content: const Text(
              'Enable notifications in Settings for reminders to alert you.'),
          action: SnackBarAction(
            label: 'Open Settings',
            onPressed: openAppSettings,
          ),
        ),
      );
    }
  }

  void _toggleDay(
      MeditationState state, MindfulnessReminder r, int weekday) {
    final days = [...r.days];
    if (days.contains(weekday)) {
      days.remove(weekday);
    } else {
      days.add(weekday);
    }
    days.sort();
    state.updateReminder(r.copyWith(days: days));
  }
}
