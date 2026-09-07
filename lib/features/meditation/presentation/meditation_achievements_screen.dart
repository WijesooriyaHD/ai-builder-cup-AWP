import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';

import '../domain/meditation_catalog.dart';
import '../domain/meditation_models.dart';
import 'meditation_state.dart';

/// Mindfulness achievements displayed in the same visual pattern as the global
/// AchievementsScreen: 3-column grid, unlocked first, detail bottom sheet on
/// tap. Reads from [MeditationState] (separate from [AchievementService]).
class MeditationAchievementsScreen extends StatelessWidget {
  const MeditationAchievementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<MeditationState>();
    final all = MeditationCatalog.achievements;
    final unlockedCount = state.achievementCount;

    // Unlocked badges first, locked after — same sort as global screen.
    final sorted = [...all]..sort((a, b) {
        final au = state.isUnlocked(a.id);
        final bu = state.isUnlocked(b.id);
        if (au && !bu) return -1;
        if (!au && bu) return 1;
        return 0;
      });

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Achievements',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
        elevation: 0,
      ),
      body: CustomScrollView(
        slivers: [
          // Progress header — same layout as global screen.
          SliverToBoxAdapter(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                border: Border(
                  bottom: BorderSide(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white10
                        : Colors.black12,
                  ),
                ),
              ),
              child: Column(
                children: [
                  SizedBox(
                    height: 180,
                    child: Lottie.asset(
                      'assets/images/achievement.json',
                      repeat: true,
                      animate: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '$unlockedCount / ${all.length}',
                    style: const TextStyle(
                        fontSize: 32, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Mindfulness Badges Unlocked',
                    style: TextStyle(
                        fontSize: 16, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: all.isEmpty ? 0 : unlockedCount / all.length,
                      minHeight: 8,
                      backgroundColor:
                          Theme.of(context).brightness == Brightness.dark
                              ? Colors.white10
                              : Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Theme.of(context).brightness == Brightness.dark
                            ? Theme.of(context).primaryColor
                            : Colors.black,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 3-column achievement grid.
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverGrid(
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 0.85,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final a = sorted[index];
                  final unlocked = state.isUnlocked(a.id);
                  return _buildCard(context, a, unlocked, state);
                },
                childCount: sorted.length,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(BuildContext context, MindfulnessAchievement a,
      bool unlocked, MeditationState state) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () => _showDetail(context, a, unlocked),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: unlocked
              ? null
              : Border.all(
                  color: isDark ? Colors.white10 : Colors.grey.shade300,
                  width: 1,
                ),
          boxShadow: unlocked
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withOpacity(0.05)
                    : Colors.grey.shade100,
                shape: BoxShape.circle,
                border: unlocked
                    ? Border.all(color: Colors.orange.withOpacity(0.3))
                    : null,
              ),
              child: Center(
                child: Text(
                  a.emoji,
                  style: TextStyle(
                    fontSize: 28,
                    color: unlocked ? null : Colors.grey.shade400,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                a.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: unlocked
                      ? Theme.of(context).textTheme.bodyLarge?.color
                      : (isDark ? Colors.white38 : Colors.grey.shade500),
                ),
              ),
            ),
            if (!unlocked) ...[
              const SizedBox(height: 4),
              Icon(Icons.lock_outline,
                  size: 14, color: Colors.grey.shade400),
            ],
          ],
        ),
      ),
    );
  }

  void _showDetail(BuildContext context, MindfulnessAchievement a,
      bool unlocked) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Container(
          height: 400,
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(24),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              // Handle + close
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(width: 24),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    splashRadius: 20,
                  ),
                ],
              ),
              const Spacer(),
              // Emoji
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: unlocked
                      ? Colors.orange.shade50
                      : Colors.grey.shade100,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: unlocked
                        ? Colors.orange.shade200
                        : Colors.transparent,
                    width: 2,
                  ),
                  boxShadow: unlocked
                      ? [
                          BoxShadow(
                            color: Colors.orange.withOpacity(0.2),
                            blurRadius: 20,
                            spreadRadius: 5,
                          )
                        ]
                      : [],
                ),
                child: Center(
                  child: Text(
                    a.emoji,
                    style: TextStyle(
                      fontSize: 48,
                      color: unlocked
                          ? null
                          : Colors.grey.withOpacity(0.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // Title
              Text(
                a.title,
                style: const TextStyle(
                    fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              // Description
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  a.description,
                  style: TextStyle(
                    fontSize: 16,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white70
                        : Colors.grey.shade600,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 24),
              // Status chip
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: unlocked
                      ? Colors.green.withOpacity(0.1)
                      : Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  unlocked ? 'Unlocked ✅' : 'Locked 🔒',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: unlocked ? Colors.green : Colors.grey,
                  ),
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
