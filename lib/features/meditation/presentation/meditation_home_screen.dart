import 'package:flutter/material.dart';
import '../../../services/pro_access.dart';
import 'package:provider/provider.dart';

import '../../../providers/app_state.dart';
import '../../../utils/pro_modal_utils.dart';
import '../../hydration/presentation/hydration_state.dart';
import '../domain/meditation_catalog.dart';
import '../domain/meditation_models.dart';
import 'breathing_screen.dart';
import 'body_scan_screen.dart';
import 'guided_meditation_screen.dart';
import 'meditation_achievements_screen.dart';
import 'meditation_player_screen.dart';
import 'meditation_progress_screen.dart';
import 'meditation_reminders_screen.dart';
import 'meditation_state.dart';
import 'sleep_meditation_screen.dart';
import 'stress_relief_screen.dart';
import 'widgets/meditation_widgets.dart';

/// The Meditation & Mindfulness dashboard — the home of the tool.
///
/// Presents a calming greeting, an AI recommendation, quick actions into each
/// sub-module, a practice-streak summary, and shortcuts to progress and
/// achievements. Matches the app's provider + SharedPreferences architecture.
class MeditationHomeScreen extends StatefulWidget {
  const MeditationHomeScreen({super.key});

  @override
  State<MeditationHomeScreen> createState() => _MeditationHomeScreenState();
}

class _MeditationHomeScreenState extends State<MeditationHomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    final state = context.read<MeditationState>();
    await state.load();
    if (!mounted) return;

    // AI recommendation is a Pro feature — skip the Gemini call for free users.
    final isPro = context.read<AppState>().isPro;
    if (!isPro) return;

    // Pull loosely-coupled wellness context where cheaply available.
    int? hydrationPercent;
    try {
      hydrationPercent =
          context.read<HydrationState>().completionPercentage;
    } catch (_) {
      hydrationPercent = null;
    }

    // Premium-only AI recommendation. Runs on load, so gate before calling
    // rather than at a button — there isn't one.
    if (!ProAccess.isPro) return;
    await state.refreshRecommendation(hydrationPercent: hydrationPercent);
  }

  void _open(Widget screen) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final state = context.watch<MeditationState>();

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0F1115) : const Color(0xFFF4F3FB),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Meditation Pal'),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        color: kMeditationAccent,
        onRefresh: _bootstrap,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            _buildHeroBanner(context, state),
            const SizedBox(height: 16),
            MindfulnessStreakCard(stats: state.stats),
            const SizedBox(height: 20),
            _sectionTitle(theme, 'Explore'),
            const SizedBox(height: 12),
            _buildQuickActions(),
            const SizedBox(height: 20),
            _sectionTitle(theme, 'Insights'),
            const SizedBox(height: 12),
            _buildInsightRow(context, state),
          ],
        ),
      ),
    );
  }

  /// Hero banner — shows the AI recommendation for Pro users, or a premium
  /// upsell card for free users.
  Widget _buildHeroBanner(BuildContext context, MeditationState state) {
    final isPro = context.watch<AppState>().isPro;

    return GestureDetector(
      onTap: isPro
          ? null
          : () => ProModalUtils.showFeatureUpsellModal(
                context,
                title: 'AI Mindfulness Coach',
                message:
                    'Upgrade to Premium to unlock personalised AI recommendations'
                    ' tailored to your sleep, hydration, and practice habits.',
                icon: Icons.self_improvement_rounded,
              ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [kMeditationDeep, kMeditationAccent],
          ),
          borderRadius: BorderRadius.circular(22),
        ),
        child: isPro ? _proRecommendation(state) : _lockedRecommendation(),
      ),
    );
  }

  /// Pro content: live AI recommendation with loading indicator.
  Widget _proRecommendation(MeditationState state) {
    return Row(
      children: [
        const Icon(Icons.self_improvement_rounded,
            color: Colors.white54, size: 38),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'AI Recommendation',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (state.loadingRecommendation)
                    const SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                          strokeWidth: 1.5, color: Colors.white54),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                state.recommendation,
                style: const TextStyle(
                    color: Colors.white, fontSize: 13, height: 1.4),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Free-tier locked state: blurred-out content + lock + upgrade hint.
  Widget _lockedRecommendation() {
    return Row(
      children: [
        const Icon(Icons.self_improvement_rounded,
            color: Colors.white54, size: 38),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Text(
                    'AI Recommendation',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                    ),
                  ),
                  SizedBox(width: 6),
                  Icon(Icons.lock_rounded, color: Colors.white54, size: 13),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Unlock personalised mindfulness guidance with Premium.',
                style: TextStyle(
                    color: Colors.white70, fontSize: 13, height: 1.4),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.18),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text(
            'Upgrade',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(ThemeData theme, String title) => Text(
        title,
        style: theme.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      );

  Widget _buildQuickActions() {
    final actions = <_QuickAction>[
      _QuickAction('🌬️', 'Breathing', const Color(0xFF4AB6C9),
          () => _open(const BreathingScreen())),
      _QuickAction('🧘', 'Guided', kMeditationAccent,
          () => _open(const GuidedMeditationScreen())),
      _QuickAction('💆', 'Body Scan', const Color(0xFF7C6FF0),
          () => _open(const BodyScanScreen())),
      _QuickAction('😌', 'Stress Relief', const Color(0xFFEC7CA0),
          () => _open(const StressReliefScreen())),
      _QuickAction('😴', 'Sleep', const Color(0xFF3F51B5),
          () => _open(const SleepMeditationScreen())),
      _QuickAction('🎯', 'Focus', const Color(0xFF2E9E7B),
          () => _openFocus()),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: actions.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 1.55,
      ),
      itemBuilder: (_, i) {
        final a = actions[i];
        return QuickActionCard(
          emoji: a.emoji,
          title: a.title,
          color: a.color,
          onTap: a.onTap,
        );
      },
    );
  }

  /// Focus jumps straight into a short concentration-focused guided timer.
  void _openFocus() {
    final focus = MeditationCatalog.guided.firstWhere(
      (g) => g.category == 'Focus & Productivity',
      orElse: () => MeditationCatalog.guided.first,
    );
    _open(MeditationPlayerScreen(
      title: focus.title,
      emoji: focus.emoji,
      minutes: focus.durationMinutes,
      type: SessionType.focus,
    ));
  }

  Widget _buildInsightRow(BuildContext context, MeditationState state) {
    return Row(
      children: [
        Expanded(
          child: _InsightTile(
            emoji: '📈',
            title: 'Progress',
            subtitle: '${state.stats.totalSessions} sessions',
            onTap: () => _open(const MeditationProgressScreen()),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _InsightTile(
            emoji: '🏅',
            title: 'Achievements',
            subtitle: '${state.achievementCount}/'
                '${MeditationCatalog.achievements.length}',
            onTap: () => _open(const MeditationAchievementsScreen()),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _InsightTile(
            emoji: '⏰',
            title: 'Reminders',
            subtitle: '${state.reminders.where((r) => r.enabled).length} on',
            onTap: () => _open(const MeditationRemindersScreen()),
          ),
        ),
      ],
    );
  }
}

class _QuickAction {
  final String emoji;
  final String title;
  final Color color;
  final VoidCallback onTap;
  _QuickAction(this.emoji, this.title, this.color, this.onTap);
}

class _InsightTile extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _InsightTile({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: theme.colorScheme.onSurface.withOpacity(0.06),
          ),
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 6),
            Text(
              title,
              style: theme.textTheme.labelLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
