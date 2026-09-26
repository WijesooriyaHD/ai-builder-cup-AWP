import 'dart:math' as math;

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import 'challenge_state.dart';
import '../domain/challenge_models.dart';
import '../../../services/achievement_service.dart';
import '../../../screens/achievement_completion_page.dart';

// ---------------------------------------------------------------------------
// Accent palette — consistent across all challenge cards
// ---------------------------------------------------------------------------

const _kBlue = Color(0xFF3A7BD5);
const _kTeal = Color(0xFF00B4D8);
const _kViolet = Color(0xFF7B2FBE);
const _kGreen = Color(0xFF22C55E);
const _kRose = Color(0xFFEC4899);
const _kAmber = Color(0xFFF59E0B);
const _kIndigo = Color(0xFF4F46E5);

/// No-op tap handler for disabled CTA buttons.
void _noop() {}

final _categoryGradients = <ChallengeCategory, List<Color>>{
  ChallengeCategory.hydration: [_kBlue, _kTeal],
  ChallengeCategory.movement: [_kGreen, const Color(0xFF059669)],
  ChallengeCategory.meditation: [_kViolet, _kIndigo],
  ChallengeCategory.nutrition: [_kRose, _kAmber],
  ChallengeCategory.sleep: [const Color(0xFF1E1B4B), _kIndigo],
  ChallengeCategory.detox: [_kGreen, _kTeal],
  ChallengeCategory.general: [_kBlue, _kViolet],
};

final _categoryIcons = <ChallengeCategory, IconData>{
  ChallengeCategory.hydration: Icons.water_drop_rounded,
  ChallengeCategory.movement: Icons.directions_walk_rounded,
  ChallengeCategory.meditation: Icons.self_improvement_rounded,
  ChallengeCategory.nutrition: Icons.restaurant_rounded,
  ChallengeCategory.sleep: Icons.nightlight_round,
  ChallengeCategory.detox: Icons.eco_rounded,
  ChallengeCategory.general: Icons.emoji_events_rounded,
};

final _badgeColors = <ChallengeBadge, Color>{
  ChallengeBadge.beginner: _kGreen,
  ChallengeBadge.popular: _kBlue,
  ChallengeBadge.trending: _kRose,
  ChallengeBadge.recommended: _kViolet,
  ChallengeBadge.new_: _kAmber,
};

// =============================================================================
// Public entry point — drop into any ListView
// =============================================================================

/// The full Challenge Engine section. Place this inside a ListView as a
/// non-scrollable block; the internal carousel handles horizontal scrolling.
class ChallengeEngineSection extends StatefulWidget {
  const ChallengeEngineSection({super.key});

  @override
  State<ChallengeEngineSection> createState() =>
      _ChallengeEngineSectionState();
}

class _ChallengeEngineSectionState extends State<ChallengeEngineSection> {
  late final ConfettiController _confetti;

  @override
  void initState() {
    super.initState();
    _confetti = ConfettiController(duration: const Duration(seconds: 2));
    WidgetsBinding.instance
        .addPostFrameCallback((_) => context.read<ChallengeState>().load());
  }

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  void _celebrate() {
    _confetti.play();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Consumer<ChallengeState>(builder: (ctx, state, _) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Section header ───────────────────────────────────────────
              _SectionHeader(
                onSeeAll: () => _showAllChallenges(context, state),
              ),
              const SizedBox(height: 10),

              // ── AI recommendation card ───────────────────────────────────
              if (state.aiRecommendation != null) ...[
                _AiRecommendationCard(text: state.aiRecommendation!),
                const SizedBox(height: 12),
              ],

              // ── Carousel ────────────────────────────────────────────────
              if (state.isLoading)
                const _CarouselSkeleton()
              else if (state.activeChallenges.isEmpty)
                _EmptyState(
                    onBrowse: () => _showAllChallenges(context, state))
              else
                _ChallengeCarousel(
                  challenges: state.activeChallenges,
                  catalog: ChallengeCatalog.all,
                  onLogDay: (id) async {
                    final messenger = ScaffoldMessenger.of(context);
                    final challengeState = context.read<ChallengeState>();
                    final result = await challengeState.logDay(id);
                    switch (result) {
                      case LogDayResult.completed:
                        _celebrate();
                        // Check and show challenge achievements on completion.
                        if (context.mounted) {
                          final newAchievements =
                              await challengeState.checkChallengeAchievements();
                          if (context.mounted) {
                            for (final achievement in newAchievements) {
                              await Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => AchievementCompletionPage(
                                    achievement: achievement),
                                fullscreenDialog: true,
                              ));
                            }
                          }
                        }
                        break;
                      case LogDayResult.alreadyLoggedToday:
                        messenger.showSnackBar(const SnackBar(
                          content: Text(
                              "Today's step is done. Come back tomorrow to keep your streak going!"),
                        ));
                        break;
                      case LogDayResult.logged:
                        messenger.showSnackBar(const SnackBar(
                          content: Text('Nice work — day logged! ✅'),
                        ));
                        break;
                      case LogDayResult.failed:
                        break;
                    }
                  },
                  onJoin: (template) async {
                    final challengeState = context.read<ChallengeState>();
                    final joined =
                        await challengeState.joinChallenge(template);
                    if (joined != null && context.mounted) {
                      // Check for "Challenge Accepted" badge on first join.
                      final newAchievements =
                          await challengeState.checkChallengeAchievements();
                      if (context.mounted) {
                        for (final achievement in newAchievements) {
                          await Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => AchievementCompletionPage(
                                achievement: achievement),
                            fullscreenDialog: true,
                          ));
                        }
                      }
                    }
                  },
                ),
            ],
          );
        }),

        // ── Confetti overlay ───────────────────────────────────────────────
        Align(
          alignment: Alignment.topCenter,
          child: ConfettiWidget(
            confettiController: _confetti,
            blastDirection: math.pi / 2,
            numberOfParticles: 30,
            gravity: 0.3,
            colors: const [
              _kBlue, _kRose, _kGreen, _kAmber, _kViolet
            ],
          ),
        ),
      ],
    );
  }

  void _showAllChallenges(BuildContext context, ChallengeState state) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AllChallengesSheet(
        catalog: ChallengeCatalog.all,
        userChallenges: state.challenges,
        onJoin: (template) async {
            final challengeState = context.read<ChallengeState>();
            final joined = await challengeState.joinChallenge(template);
            if (joined != null && context.mounted) {
              final newAchievements =
                  await challengeState.checkChallengeAchievements();
              if (context.mounted) {
                for (final achievement in newAchievements) {
                  await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) =>
                        AchievementCompletionPage(achievement: achievement),
                    fullscreenDialog: true,
                  ));
                }
              }
            }
          },
      ),
    );
  }
}

// =============================================================================
// Section header
// =============================================================================

class _SectionHeader extends StatelessWidget {
  final VoidCallback onSeeAll;
  const _SectionHeader({required this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Challenges',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(
                'Join guided wellness challenges and build healthy habits with consistency.',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.5),
                    height: 1.3),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        GestureDetector(
          onTap: onSeeAll,
          child: Text(
            'See All',
            style: TextStyle(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// AI recommendation card
// =============================================================================

class _AiRecommendationCard extends StatelessWidget {
  final String text;
  const _AiRecommendationCard({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? _kViolet.withOpacity(0.15)
            : _kViolet.withOpacity(0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kViolet.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: _kViolet.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.auto_awesome_rounded,
                color: _kViolet, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Recommended for You',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _kViolet,
                      letterSpacing: 0.3),
                ),
                const SizedBox(height: 2),
                Text(text,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.05, end: 0);
  }
}

// =============================================================================
// Challenge carousel
// =============================================================================

class _ChallengeCarousel extends StatelessWidget {
  final List<UserChallenge> challenges;
  final List<ChallengeTemplate> catalog;
  final Future<void> Function(String id) onLogDay;
  final Future<UserChallenge?> Function(ChallengeTemplate) onJoin;

  const _ChallengeCarousel({
    required this.challenges,
    required this.catalog,
    required this.onLogDay,
    required this.onJoin,
  });

  @override
  Widget build(BuildContext context) {
    // Active user challenges + catalog suggestions not yet joined.
    final joinedIds = challenges.map((c) => c.templateId).toSet();
    final suggestions = catalog.where((t) => !joinedIds.contains(t.id)).toList();

    return SizedBox(
      height: 220,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(right: 8),
        children: [
          // Active challenges first.
          ...challenges.map((c) => _ActiveChallengeCard(
                challenge: c,
                onLogDay: () => onLogDay(c.id),
              )),
          // Catalog suggestions.
          ...suggestions.map((t) => _CatalogChallengeCard(
                template: t,
                onJoin: () => onJoin(t),
              )),
        ],
      ),
    );
  }
}

// =============================================================================
// Active challenge card
// =============================================================================

class _ActiveChallengeCard extends StatefulWidget {
  final UserChallenge challenge;
  final Future<void> Function() onLogDay;
  const _ActiveChallengeCard(
      {required this.challenge, required this.onLogDay});

  @override
  State<_ActiveChallengeCard> createState() => _ActiveChallengeCardState();
}

class _ActiveChallengeCardState extends State<_ActiveChallengeCard> {
  bool _logging = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.challenge;
    final gradients =
        _categoryGradients[c.category] ?? [_kBlue, _kViolet];
    final icon = _categoryIcons[c.category] ?? Icons.emoji_events_rounded;

    return GestureDetector(
      onTap: () => _showChallengeDetail(context, c, gradients, icon),
      child: Container(
      width: 200,
      margin: const EdgeInsets.only(right: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradients,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: gradients.first.withOpacity(0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Glassmorphic background circle.
          Positioned(
            right: -24,
            top: -24,
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.08),
              ),
            ),
          ),
          Positioned(
            left: -16,
            bottom: -20,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.05),
              ),
            ),
          ),
          // Content.
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Badge + icon row.
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _BadgePill(badge: c.badge),
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.18),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: Colors.white, size: 17),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Title.
                Text(
                  c.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                // Today's step — what the user must actually do today.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.wb_sunny_rounded,
                        color: Colors.white70, size: 13),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        c.loggedToday
                            ? 'Today done — back tomorrow'
                            : (ChallengeCatalog.findById(c.templateId)
                                    ?.stepForDay(c.currentDayNumber) ??
                                c.goalDescription),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          height: 1.25,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                // Progress bar.
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: c.progressFraction,
                    minHeight: 5,
                    backgroundColor: Colors.white.withOpacity(0.2),
                    valueColor:
                        const AlwaysStoppedAnimation(Colors.white),
                  ),
                ),
                const SizedBox(height: 5),
                // Day counter + percent.
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Day ${c.daysCompleted} of ${c.durationDays}',
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                          fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '${c.progressPercent}%',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // CTA.
                c.isCompleted
                    ? _CompletedBadge(
                        trophyEmoji: c.trophyEmoji,
                        trophyTitle: c.trophyTitle)
                    : c.loggedToday
                        // Daily step already done — locked until tomorrow so the
                        // user can't tap through the whole challenge at once.
                        ? const _CtaButton(
                            label: 'Done for today ✓',
                            muted: true,
                            disabled: true,
                            onTap: _noop,
                          )
                        : _CtaButton(
                            label: 'Complete today\'s step',
                            loading: _logging,
                            onTap: () async {
                              setState(() => _logging = true);
                              await widget.onLogDay();
                              if (mounted) setState(() => _logging = false);
                            },
                          ),
              ],
            ),
          ),
        ],
      ),
      ),
    )
        .animate()
        .fadeIn(duration: 350.ms)
        .slideX(begin: 0.05, end: 0, duration: 350.ms);
  }

  /// Shows a bottom sheet with the full challenge detail and today's step.
  void _showChallengeDetail(
    BuildContext context,
    UserChallenge c,
    List<Color> gradients,
    IconData icon,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: theme.cardColor,
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
                  decoration: BoxDecoration(
                    color: theme.dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Header: icon + title
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: gradients),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      c.title,
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(c.description,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.hintColor)),
              const SizedBox(height: 20),
              // Today's step card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: gradients.first.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.wb_sunny_rounded,
                            size: 16, color: gradients.first),
                        const SizedBox(width: 6),
                        Text(
                          'Day ${c.daysCompleted + (c.loggedToday ? 0 : 1)} of ${c.durationDays}',
                          style: TextStyle(
                            color: gradients.first,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      c.isCompleted
                          ? 'Challenge complete! 🎉'
                          : c.loggedToday
                              ? "Today's step is done. Come back tomorrow to continue your streak."
                              : (ChallengeCatalog.findById(c.templateId)
                                      ?.stepForDay(c.currentDayNumber) ??
                                  c.goalDescription),
                      style: theme.textTheme.bodyLarge
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Progress
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: c.progressFraction,
                  minHeight: 8,
                  backgroundColor: theme.dividerColor.withOpacity(0.3),
                  valueColor: AlwaysStoppedAnimation(gradients.first),
                ),
              ),
              const SizedBox(height: 6),
              Text('${c.progressPercent}% · ${c.daysRemaining} days remaining',
                  style: theme.textTheme.bodySmall),
              const SizedBox(height: 20),
              // Action
              if (!c.isCompleted)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: c.loggedToday
                        ? null
                        : () async {
                            Navigator.pop(sheetContext);
                            await widget.onLogDay();
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: gradients.first,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(c.loggedToday
                        ? 'Done for today ✓'
                        : "Complete today's step"),
                  ),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

// =============================================================================
// Catalog / browse challenge card (not yet joined)
// =============================================================================

class _CatalogChallengeCard extends StatefulWidget {
  final ChallengeTemplate template;
  final Future<UserChallenge?> Function() onJoin;
  const _CatalogChallengeCard(
      {required this.template, required this.onJoin});

  @override
  State<_CatalogChallengeCard> createState() => _CatalogChallengeCardState();
}

class _CatalogChallengeCardState extends State<_CatalogChallengeCard> {
  bool _joining = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.template;
    final gradients =
        _categoryGradients[t.category] ?? [_kBlue, _kViolet];
    final icon = _categoryIcons[t.category] ?? Icons.emoji_events_rounded;

    return Container(
      width: 200,
      margin: const EdgeInsets.only(right: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            gradients.first.withOpacity(0.65),
            gradients.last.withOpacity(0.45),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -20,
            top: -20,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.07),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _BadgePill(badge: t.badge),
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: Colors.white70, size: 17),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  t.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${t.durationDays} days',
                  style: const TextStyle(
                      color: Colors.white60, fontSize: 11),
                ),
                const Spacer(),
                // Rewards row.
                Row(
                  children: [
                    const Text('⚡', style: TextStyle(fontSize: 11)),
                    const SizedBox(width: 3),
                    Text(
                      '+${t.xpReward} XP',
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                          fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 8),
                    const Text('✨', style: TextStyle(fontSize: 11)),
                    const SizedBox(width: 3),
                    Text(
                      '+${t.wellnessPointsReward} pts',
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                          fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _CtaButton(
                  label: 'Join Challenge',
                  loading: _joining,
                  muted: true,
                  onTap: () async {
                    setState(() => _joining = true);
                    await widget.onJoin();
                    if (mounted) setState(() => _joining = false);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 350.ms)
        .slideX(begin: 0.05, end: 0, duration: 350.ms);
  }
}

// =============================================================================
// Shared small widgets
// =============================================================================

class _BadgePill extends StatelessWidget {
  final ChallengeBadge badge;
  const _BadgePill({required this.badge});

  @override
  Widget build(BuildContext context) {
    final color = _badgeColors[badge] ?? _kBlue;
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.22),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        badge.label,
        style: TextStyle(
          color: color == _kAmber ? Colors.white : Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _CtaButton extends StatelessWidget {
  final String label;
  final bool loading;
  final bool muted;
  final bool disabled;
  final VoidCallback onTap;
  const _CtaButton({
    required this.label,
    required this.onTap,
    this.loading = false,
    this.muted = false,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: (loading || disabled) ? null : onTap,
      child: Container(
        width: double.infinity,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: muted
              ? Colors.white.withOpacity(0.18)
              : Colors.white.withOpacity(0.95),
          borderRadius: BorderRadius.circular(12),
        ),
        child: loading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : Text(
                label,
                style: TextStyle(
                  color: muted
                      ? Colors.white
                      : Colors.black87,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
      ),
    );
  }
}

class _CompletedBadge extends StatelessWidget {
  final String trophyEmoji;
  final String trophyTitle;
  const _CompletedBadge(
      {required this.trophyEmoji, required this.trophyTitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(trophyEmoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 5),
          Text(
            '$trophyTitle ✓',
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Loading skeleton
// =============================================================================

class _CarouselSkeleton extends StatelessWidget {
  const _CarouselSkeleton();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base =
        isDark ? Colors.white.withOpacity(0.07) : Colors.black.withOpacity(0.06);
    return SizedBox(
      height: 220,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: 3,
        itemBuilder: (_, i) => Container(
          width: 200,
          margin: const EdgeInsets.only(right: 14),
          decoration: BoxDecoration(
            color: base,
            borderRadius: BorderRadius.circular(24),
          ),
        ).animate(onPlay: (c) => c.repeat(reverse: true)).shimmer(
              duration: 1000.ms,
              color: isDark
                  ? Colors.white.withOpacity(0.05)
                  : Colors.white.withOpacity(0.7),
            ),
      ),
    );
  }
}

// =============================================================================
// Empty state
// =============================================================================

class _EmptyState extends StatelessWidget {
  final VoidCallback onBrowse;
  const _EmptyState({required this.onBrowse});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.04)
            : Colors.black.withOpacity(0.03),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
            color: isDark
                ? Colors.white.withOpacity(0.08)
                : Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        children: [
          const Text('🏅', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 10),
          Text('Start your first challenge',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            'Short-term challenges build the habits that last a lifetime.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.5),
                height: 1.35),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: onBrowse,
            style: OutlinedButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Browse Challenges',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// "See All / Browse" bottom sheet
// =============================================================================

class _AllChallengesSheet extends StatelessWidget {
  final List<ChallengeTemplate> catalog;
  final List<UserChallenge> userChallenges;
  final Future<UserChallenge?> Function(ChallengeTemplate) onJoin;

  const _AllChallengesSheet({
    required this.catalog,
    required this.userChallenges,
    required this.onJoin,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final joinedIds =
        userChallenges.map((c) => c.templateId).toSet();

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      builder: (_, ctrl) => Container(
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: ListView(
          controller: ctrl,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 14),
            Text('All Challenges',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              'Choose a challenge that fits your current goals.',
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.5)),
            ),
            const SizedBox(height: 18),
            ...catalog.map((t) {
              final joined = joinedIds.contains(t.id);
              final gradients =
                  _categoryGradients[t.category] ?? [_kBlue, _kViolet];
              final icon = _categoryIcons[t.category] ??
                  Icons.emoji_events_rounded;
              return Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      gradients.first.withOpacity(0.85),
                      gradients.last.withOpacity(0.65),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: gradients.first.withOpacity(0.25),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.18),
                        shape: BoxShape.circle,
                      ),
                      child:
                          Icon(icon, color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t.title,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14)),
                          const SizedBox(height: 2),
                          Text('${t.durationDays} days · +${t.xpReward} XP',
                              style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11)),
                          const SizedBox(height: 2),
                          Text(t.goalDescription,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 11,
                                  height: 1.3)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    joined
                        ? const Icon(Icons.check_circle_rounded,
                            color: Colors.white70, size: 22)
                        : GestureDetector(
                            onTap: () async {
                              await onJoin(t);
                              if (context.mounted) Navigator.pop(context);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color:
                                    Colors.white.withOpacity(0.9),
                                borderRadius:
                                    BorderRadius.circular(12),
                              ),
                              child: const Text('Join',
                                  style: TextStyle(
                                      color: Colors.black87,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12)),
                            ),
                          ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
