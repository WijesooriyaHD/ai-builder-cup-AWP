import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../services/notification_category.dart';
import '../services/notification_preferences_store.dart';

/// Lets the user choose what they want to hear about.
///
/// One master switch plus one switch per [NotificationCategory]. The list is
/// generated from the enum, so a new category appears here automatically.
///
/// The master switch does two jobs at once: it stores the app-level preference
/// AND opts the device in/out of OneSignal delivery, so turning it off stops
/// dashboard campaigns too — not just the reminders the app schedules itself.
class NotificationPreferencesScreen extends StatelessWidget {
  const NotificationPreferencesScreen({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const NotificationPreferencesScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Notifications',
          style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Consumer2<NotificationPreferencesStore, AppState>(
        builder: (context, store, appState, _) {
          final prefs = store.preferences;

          // Cycle reminders stay hidden until there is cycle data to base them
          // on — offering them to someone who has never logged a period would
          // be both useless and a little presumptuous.
          final hasCycleData =
              appState.periodData.loggedPeriodStarts.isNotEmpty;
          final visible = NotificationCategory.values
              .where((c) => !c.requiresCycleData || hasCycleData)
              .toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              _MasterSwitch(
                enabled: prefs.masterEnabled,
                isDark: isDark,
                onChanged: (value) => _setMaster(context, store, value),
              ),
              const SizedBox(height: 8),
              const Divider(height: 32),

              Text(
                'WHAT YOU HEAR ABOUT',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                  color: theme.colorScheme.onSurface.withOpacity(0.45),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                prefs.masterEnabled
                    ? 'Choose the nudges that help. Everything else stays quiet.'
                    : 'Turn on Push Notifications above to choose categories.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.5),
                ),
              ),
              const SizedBox(height: 12),

              // Dimmed but still readable when the master is off, so the user
              // can see what they'd get rather than facing an empty screen.
              Opacity(
                opacity: prefs.masterEnabled ? 1 : 0.45,
                child: IgnorePointer(
                  ignoring: !prefs.masterEnabled,
                  child: Column(
                    children: [
                      for (final category in visible)
                        _CategorySwitch(
                          category: category,
                          // Shows the raw per-category value, not the effective
                          // one — otherwise every row would read "off" while
                          // the master is off and the user would lose their
                          // settings visually.
                          value: prefs.categories[category.id] ?? false,
                          isDark: isDark,
                          onChanged: (value) =>
                              store.setCategoryEnabled(category, value),
                        ),
                    ],
                  ),
                ),
              ),

              if (!hasCycleData) ...[
                const SizedBox(height: 16),
                Text(
                  'Cycle reminders appear here once you log period data in the '
                  'Period Tracker.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.4),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  /// Master switch: store the preference AND opt the device in/out of
  /// OneSignal, so campaigns stop too.
  Future<void> _setMaster(
    BuildContext context,
    NotificationPreferencesStore store,
    bool enabled,
  ) async {
    // Both master switches (here and in Settings) go through these shared
    // store methods, so the OneSignal subscription and the stored preference
    // always move together.
    if (!enabled) {
      await store.disableMaster();
      return;
    }
    final granted = await store.enableMaster();
    if (!granted && context.mounted) _showBlockedDialog(context);
  }

  void _showBlockedDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enable notifications'),
        content: const Text(
          'Notifications are blocked for this app. To re-enable them, open '
          'iPhone Settings → AI Wellness Pal → Notifications, and turn on '
          'Allow Notifications.',
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
}

class _MasterSwitch extends StatelessWidget {
  const _MasterSwitch({
    required this.enabled,
    required this.isDark,
    required this.onChanged,
  });

  final bool enabled;
  final bool isDark;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Push Notifications',
                style: theme.textTheme.bodyLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                enabled
                    ? 'Wellness nudges, streak reminders, and plan updates.'
                    : 'Everything is muted while this is off.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isDark ? Colors.white54 : Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Switch.adaptive(value: enabled, onChanged: onChanged),
      ],
    );
  }
}

class _CategorySwitch extends StatelessWidget {
  const _CategorySwitch({
    required this.category,
    required this.value,
    required this.isDark,
    required this.onChanged,
  });

  final NotificationCategory category;
  final bool value;
  final bool isDark;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  category.label,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  category.description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isDark ? Colors.white54 : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch.adaptive(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
