import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/achievement_service.dart';
import '../services/engagement_service.dart';
import '../services/notification_category.dart';
import '../services/notification_preferences_store.dart';
import '../services/notification_router.dart';
import '../services/app_navigation_service.dart';

/// Hidden panel for exercising the engagement system without waiting days for
/// real conditions to occur.
///
/// Everything here goes through the SAME production code paths — the buttons
/// call [EngagementService], not the notification plugin directly. That is the
/// point: a test that bypasses the real path proves nothing. In particular the
/// preference checks still apply, so if a category is switched off the test
/// button correctly does nothing and says so.
///
/// Reached from Settings by long-pressing the app version (debug builds only).
class DeveloperTestPanelScreen extends StatelessWidget {
  const DeveloperTestPanelScreen({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const DeveloperTestPanelScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final engagement = context.read<EngagementService>();
    final achievements = context.read<AchievementService>();
    final navigation = context.read<AppNavigationService>();
    final prefs = context.watch<NotificationPreferencesStore>();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Developer · Notifications',
          style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          _Note(
            'These use the real production paths, so preference checks apply. '
            'If a category is off, its test will report "suppressed" rather '
            'than sending — that is correct behaviour, not a failure.',
          ),
          const SizedBox(height: 8),
          _Note(
            'Notifications sent while the app is in the FOREGROUND may not '
            'appear as banners on iOS. Background the app first, or watch for '
            'the confirmation snackbar.',
          ),

          _Section('Contextual reminders'),
          for (final category in NotificationCategory.values)
            _Button(
              'Test ${category.label}',
              () => _reminder(context, engagement, category),
            ),

          _Section('Streak milestones'),
          for (final days in const [1, 3, 7, 14, 30, 50, 100])
            _Button(
              'Simulate $days-day streak',
              () async {
                await engagement.celebrateStreak(days);
                if (!context.mounted) return;
                _toast(context, 'Streak $days sent (in-app if app is open)');
              },
            ),

          _Section('Achievements'),
          for (final id in const [
            'first_step',
            'week_warrior',
            'month_master',
            'legendary',
          ])
            _Button(
              'Simulate ${_achievementName(achievements, id)}',
              () => _achievement(context, engagement, achievements, id),
            ),

          _Section('In-app messages'),
          _Button('Test achievement in-app message', () async {
            await engagement.showInAppMoment('achievement_unlocked');
            if (!context.mounted) return;
            _toast(context, 'Trigger set — needs a matching dashboard message');
          }),
          _Button("Test \"Plan is ready\" in-app message", () async {
            await engagement.showInAppMoment('plan_ready');
            if (!context.mounted) return;
            _toast(context, 'Trigger set — needs a matching dashboard message');
          }),
          _Button('Clear in-app trigger', () async {
            await engagement.clearInAppMoment();
            if (!context.mounted) return;
            _toast(context, 'Trigger cleared');
          }),

          _Section('Journey events'),
          for (final event in EngagementEvent.values)
            _Button('Track "${event.name}"', () async {
              await engagement.trackEvent(event);
              if (!context.mounted) return;
              _toast(context, 'Event ${event.name} sent to OneSignal');
            }),

          _Section('Deep links'),
          for (final category in NotificationCategory.values)
            _Button('Route to ${category.deepLink}', () {
              Navigator.of(context).pop();
              NotificationRouter.route(category, navigation);
            }),

          _Section('Current state'),
          _Note('Master: ${prefs.preferences.masterEnabled ? "on" : "off"}'),
          for (final category in NotificationCategory.values)
            _Note(
              '${category.id}: '
              '${prefs.isCategoryEnabled(category) ? "enabled" : "disabled"}',
            ),
        ],
      ),
    );
  }

  static String _achievementName(AchievementService service, String id) {
    for (final a in service.achievements) {
      if (a.id == id) return a.name;
    }
    return id;
  }

  Future<void> _reminder(
    BuildContext context,
    EngagementService engagement,
    NotificationCategory category,
  ) async {
    final sent = await engagement.sendReminder(
      category: category,
      title: _titleFor(category),
      body: _bodyFor(category),
    );
    if (context.mounted) {
      _toast(
        context,
        sent ? '${category.label} sent' : '${category.label} suppressed (off)',
      );
    }
  }

  Future<void> _achievement(
    BuildContext context,
    EngagementService engagement,
    AchievementService service,
    String id,
  ) async {
    Achievement? match;
    for (final a in service.achievements) {
      if (a.id == id) {
        match = a;
        break;
      }
    }
    if (match == null) {
      _toast(context, 'Unknown achievement "$id"');
      return;
    }
    final inApp = await engagement.celebrateAchievement(match);
    if (context.mounted) {
      _toast(context, inApp ? 'In-app trigger set' : 'Notification sent');
    }
  }

  /// Production copy for each reminder, kept here so the test panel sends the
  /// exact strings a user would receive.
  static String _titleFor(NotificationCategory c) => switch (c) {
        NotificationCategory.checkIn => 'How are you feeling today?',
        NotificationCategory.wellnessPlan => 'Your plan is ready 🌿',
        NotificationCategory.meal => "Today's meals",
        NotificationCategory.hydration => 'Stay energized 💧',
        NotificationCategory.habit => 'Your challenge is waiting',
        NotificationCategory.meditation => 'A mindful minute 🧘',
        NotificationCategory.achievement => '🎉 Achievement Unlocked',
        NotificationCategory.cycle => 'Cycle check-in 🌸',
      };

  static String _bodyFor(NotificationCategory c) => switch (c) {
        NotificationCategory.checkIn =>
          'Take a moment to check in with yourself.',
        NotificationCategory.wellnessPlan =>
          'Your personalized wellness plan is ready.',
        NotificationCategory.meal => "Take a moment to log today's meals.",
        NotificationCategory.hydration => 'Log your water intake.',
        NotificationCategory.habit => 'Keep your streak going.',
        NotificationCategory.meditation => 'Take a mindful minute for yourself.',
        NotificationCategory.achievement => 'You unlocked something new.',
        NotificationCategory.cycle => 'A gentle reminder based on your cycle.',
      };

  static void _toast(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}

class _Button extends StatelessWidget {
  const _Button(this.label, this.onPressed);
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          child: Text(label, textAlign: TextAlign.left),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.55),
            ),
      ),
    );
  }
}
