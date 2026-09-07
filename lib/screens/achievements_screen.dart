import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/achievement_service.dart';
import 'package:lottie/lottie.dart';

class AchievementsScreen extends StatelessWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AchievementService>(
      builder: (context, achievementService, child) {
        final achievements = achievementService.achievements;
        final unlockedCount = achievementService.totalUnlocked;
        
        // Sort: unlocked first, then locked
        final sortedAchievements = [...achievements];
        sortedAchievements.sort((a, b) {
          final aUnlocked = achievementService.isUnlocked(a.id);
          final bUnlocked = achievementService.isUnlocked(b.id);
          if (aUnlocked && !bUnlocked) return -1;
          if (!aUnlocked && bUnlocked) return 1;
          return 0;
        });

        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: AppBar(
            title: const Text('Achievements', style: TextStyle(fontWeight: FontWeight.bold)),
            backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
            foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
            elevation: 0,
          ),
          // Whole page scrolls as one unit (header + grid) so it stays
          // scrollable regardless of how many achievements there are.
          body: CustomScrollView(
            slivers: [
              // Progress header
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
                      // Achievement Lottie
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
                        '$unlockedCount / ${achievements.length}',
                        style: const TextStyle(
                            fontSize: 32, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Achievements Unlocked',
                        style:
                            TextStyle(fontSize: 16, color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 16),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: achievements.isEmpty
                              ? 0
                              : unlockedCount / achievements.length,
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

              // Achievements grid
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
                      final achievement = sortedAchievements[index];
                      final isUnlocked =
                          achievementService.isUnlocked(achievement.id);
                      return _buildAchievementCard(
                          context, achievement, isUnlocked);
                    },
                    childCount: sortedAchievements.length,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAchievementCard(BuildContext context, Achievement achievement, bool isUnlocked) {
    return GestureDetector(
      onTap: () => _showAchievementDetails(context, achievement, isUnlocked),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: isUnlocked ? null : Border.all(
            color: Theme.of(context).brightness == Brightness.dark 
                ? Colors.white10 
                : Colors.grey.shade300,
            width: 1,
          ),
          boxShadow: isUnlocked ? [
             BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
             )
          ] : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icon/Emoji
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark 
                    ? Colors.white.withOpacity(0.05) 
                    : Colors.grey.shade100,
                shape: BoxShape.circle,
                border: isUnlocked ? Border.all(color: Colors.orange.withOpacity(0.3)) : null,
              ),
              child: Center(
                child: Text(
                  achievement.emoji,
                  style: TextStyle(
                    fontSize: 28,
                    color: isUnlocked ? null : Colors.grey.shade400,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            
            // Name
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                achievement.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isUnlocked 
                      ? Theme.of(context).textTheme.bodyLarge?.color 
                      : (Theme.of(context).brightness == Brightness.dark ? Colors.white38 : Colors.grey.shade500),
                ),
              ),
            ),
            
            // Lock icon for locked achievements
            if (!isUnlocked) ...[
              const SizedBox(height: 4),
              Icon(Icons.lock_outline, size: 14, color: Colors.grey.shade400),
            ],
          ],
        ),
      ),
    );
  }

  void _showAchievementDetails(BuildContext context, Achievement achievement, bool isUnlocked) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20), // Margin all sides
        child: Container(
          height: 400,
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(24), // Rounded all corners
          ),
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Handle and Close
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox(width: 24), // Spacer for balance
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
            
            // Icon
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: isUnlocked ? Colors.orange.shade50 : Colors.grey.shade100,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isUnlocked ? Colors.orange.shade200 : Colors.transparent,
                  width: 2,
                ),
                 boxShadow: isUnlocked ? [
                  BoxShadow(
                    color: Colors.orange.withOpacity(0.2),
                    blurRadius: 20,
                    spreadRadius: 5,
                  )
                ] : [],
              ),
              child: Center(
                child: Text(
                  achievement.emoji,
                  style: TextStyle(
                    fontSize: 48,
                    color: isUnlocked ? null : Colors.grey.withOpacity(0.5),
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Title
            Text(
              achievement.name,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            
            const SizedBox(height: 8),
            
            // Description
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                achievement.description,
                style: TextStyle(
                  fontSize: 16, 
                  color: Theme.of(context).brightness == Brightness.dark 
                      ? Colors.white70 
                      : Colors.grey.shade600, 
                  height: 1.4
                ),
                textAlign: TextAlign.center,
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Requirement / Status
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isUnlocked 
                    ? Colors.green.withOpacity(0.1) 
                    : (Theme.of(context).brightness == Brightness.dark ? Colors.white10 : Colors.grey.shade100),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isUnlocked 
                      ? Colors.green.withOpacity(0.3) 
                      : Colors.transparent,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isUnlocked ? Icons.check_circle : Icons.lock,
                    size: 16,
                    color: isUnlocked ? Colors.green.shade700 : Colors.grey.shade600,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isUnlocked ? 'Unlocked' : achievement.requirementText,
                    style: TextStyle(
                      color: isUnlocked ? Colors.green.shade700 : Colors.grey.shade600,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
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
