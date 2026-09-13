import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../widgets/passport_bottom_sheet.dart';
import '../providers/app_state.dart';
import 'dart:io';
import 'achievements_screen.dart';
import '../services/achievement_service.dart';
import '../models/challenge_step.dart';
import '../models/dream.dart';
import '../models/journal_entry.dart';
import '../widgets/world_map_svg.dart';
import 'dream_completion_page.dart';
import 'achievement_completion_page.dart';
import '../widgets/bloom_garden_card.dart';
import '../utils/wellnesspal_snackbar.dart';
import '../utils/pro_modal_utils.dart';
import '../widgets/world_map_sheet.dart';
import '../services/auth_service.dart';

class HomeTabScreen extends StatelessWidget {
  final VoidCallback? onChallengeCardTap;
  final VoidCallback? onConfettiPlay;
  
  const HomeTabScreen({super.key, this.onChallengeCardTap, this.onConfettiPlay});

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour >= 21 || hour < 5) return 'Good Night';
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  static const String kCardPoints = 'points';
  static const String kCardJourney = 'journey';
  static const String kCardMotivation = 'motivation';
  static const String kCardAchievements = 'achievements';
  static const String kCardChallenge = 'challenge';
  static const String kCardMap = 'map';

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Consumer<AppState>(
        builder: (context, appState, child) {
          // Define card order
          final allCards = [
            kCardPoints,
            kCardJourney, 
            kCardMotivation,
            kCardAchievements, 
            kCardChallenge, 
            kCardMap,
            // Include added journal entries
            ...appState.journalEntries
                .where((e) => appState.pinnedJournalToHomeIds.contains(e.id))
                .map((e) => 'journal_${e.id}'),
          ];
          final pinnedCards = appState.pinnedCardIds;
          
          // Sort: Pinned first, then original order
          final sortedCards = [...allCards];
          sortedCards.sort((a, b) {
            final isAPinned = pinnedCards.contains(a);
            final isBPinned = pinnedCards.contains(b);
            if (isAPinned && !isBPinned) return -1;
            if (!isAPinned && isBPinned) return 1;
            return allCards.indexOf(a).compareTo(allCards.indexOf(b));
          });

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _getGreeting(),
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 2),
              StreamBuilder<User?>(
                stream: AuthService().authStateChanges,
                builder: (context, snapshot) {
                  final user = AuthService().currentUser;
                  final displayNameRaw = user?.displayName ?? 
                                     (user?.email?.split('@').first ?? 'Traveler');
                  
                  // Convert to Title Case (e.g., "john doe" -> "John Doe")
                  final displayName = displayNameRaw.trim().split(' ').map((word) {
                    if (word.isEmpty) return '';
                    return word[0].toUpperCase() + word.substring(1).toLowerCase();
                  }).join(' ');
                  


                  return Text(
                    displayName,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          height: 1.1,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ).animate()
                   .fadeIn(duration: 600.ms, curve: Curves.easeOut);
                }
              ),
              const SizedBox(height: 24),
              
              ...sortedCards.map((cardId) {
                final widget = _buildCardWithPin(context, cardId, appState);
                if (widget == null) return const SizedBox.shrink();
                return Column(
                  children: [
                    widget,
                    const SizedBox(height: 12),
                  ],
                );
              }),
              
              const SizedBox(height: 28), // Bottom padding
            ],
          );
        },
      ),
    );
  }

  Widget? _buildCardWithPin(BuildContext context, String cardId, AppState appState) {
    Widget? cardContent;
    
    switch (cardId) {
      case kCardPoints:
        cardContent = _buildPointsCard(context, appState);
        break;
      case kCardJourney:
        if (!appState.showGarden) return null;
        cardContent = BloomGardenCard(appState: appState);
        break;
      case kCardMotivation:
        if (!appState.showMotivation) return null;
        cardContent = _buildMotivationCard(context);
        break;
      case kCardAchievements:
        if (!appState.showAchievements) return null;
        cardContent = _buildAchievementsCard(context);
        break;
      case kCardChallenge:
        cardContent = _buildChallengeCard(context, appState);
        break;
      case kCardMap:
        if (!appState.showMap) return null;
        cardContent = _buildWorldMapCard(context);
        break;
      default:
        if (cardId.startsWith('journal_')) {
          final entryId = cardId.replaceFirst('journal_', '');
          final entries = appState.journalEntries.where((e) => e.id == entryId);
          if (entries.isEmpty) return null; // Entry was deleted/purged
          cardContent = _buildPinnedJournalCard(context, entries.first, appState);
        }
    }

    if (cardContent == null) return null;

    final isPinned = appState.pinnedCardIds.contains(cardId);

    return GestureDetector(
      onLongPress: () {
        if (!isPinned) {
          _showPinOptionsBottomSheet(context, cardId, appState);
        }
      },
      child: Stack(
        children: [
          cardContent,
          if (isPinned)
            Positioned(
              top: 12,
              right: 12,
              child: GestureDetector(
                onTap: () => appState.toggleCardPin(cardId),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: (Theme.of(context).brightness == Brightness.dark 
                        ? Theme.of(context).cardColor 
                        : Colors.white).withOpacity(0.9),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.push_pin,
                    size: 18,
                    color: Theme.of(context).primaryColor,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMotivationCard(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final quotes = [
      {'text': "The question isn't who is going to let me; it's who is going to stop me.", 'author': "Ayn Rand"},
      {'text': "The most effective way to do it, is to do it.", 'author': "Amelia Earhart"},
      {'text': "I'm not afraid of storms, for I'm learning how to sail my ship.", 'author': "Louisa May Alcott"},
      {'text': "Define success on your own terms, achieve it by your own rules.", 'author': "Anne Sweeney"},
      {'text': "Don't be intimidated by what you don't know. That can be your greatest strength.", 'author': "Sara Blakely"},
      {'text': "You may encounter many defeats, but you must not be defeated.", 'author': "Maya Angelou"},
      {'text': "The most courageous act is still to think for yourself. Aloud.", 'author': "Coco Chanel"},
      {'text': "I raise up my voice—not so that I can shout, but so that those without a voice can be heard.", 'author': "Malala Yousafzai"},
      {'text': "A woman is like a tea bag; you never know how strong it is until it's in hot water.", 'author': "Eleanor Roosevelt"},
      {'text': "Success is only meaningful and enjoyable if it feels like your own.", 'author': "Michelle Obama"},
      {'text': "Power is not given to you. You have to take it.", 'author': "Beyoncé"},
      {'text': "Don't wait for people to give you opportunities. You must create them.", 'author': "Catherine the Great"},
      {'text': "Option A is not available. So let's just kick the sh*t out of Option B.", 'author': "Sheryl Sandberg"},
      {'text': "I've learned that people will forget what you said, but people will never forget how you made them feel.", 'author': "Maya Angelou"},
      {'text': "You are more powerful than you know; you are beautiful just as you are.", 'author': "Melissa Etheridge"},
      {'text': "We need to reshape our own perception of how we view ourselves.", 'author': "Beyoncé"},
      {'text': "The standard you walk past is the standard you accept.", 'author': "Elizabeth Broderick"},
      {'text': "If you don't see a clear path for what you want, sometimes you have to make it yourself.", 'author': "Mindy Kaling"},
      {'text': "Everything is possible as long as you have the courage to try.", 'author': "Serena Williams"},
      {'text': "Challenges are gifts that force us to search for a new center of gravity.", 'author': "Oprah Winfrey"},
      {'text': "Do one thing every day that scares you.", 'author': "Eleanor Roosevelt"},
      {'text': "The power to create, to transform and to empower, is in each and every one of us.", 'author': "Melinda Gates"},
      {'text': "I can and I will. Watch me.", 'author': "Carrie Green"},
      {'text': "Stop waiting for the 'right time'. The time is what you make of it.", 'author': "Unknown"},
      {'text': "Your intuition is the most powerful tool you have.", 'author': "Oprah Winfrey"},
      {'text': "Whatever you do, be different – that was the advice my mother gave me.", 'author': "Anita Roddick"},
      {'text': "Courage starts with showing up and letting ourselves be seen.", 'author': "Brené Brown"},
      {'text': "It is our choices that show what we truly are, far more than our abilities.", 'author': "J.K. Rowling"},
      {'text': "She believed she could, so she did.", 'author': "R.S. Grey"},
      {'text': "Your life is your story, and you have the power to write the next chapter.", 'author': "Unknown"},
    ];

    // Select quote based on the day of the month
    final dayOfMonth = DateTime.now().day;
    final quote = quotes[(dayOfMonth - 1) % quotes.length];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? Theme.of(context).cardColor : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.format_quote_rounded, color: Theme.of(context).colorScheme.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                "Daily Motivation",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.0,
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            "\"${quote['text']}\"",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              fontStyle: FontStyle.italic,
              height: 1.4,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                width: 20,
                height: 2,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                quote['author']!,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPointsCard(BuildContext context, AppState appState) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () => _showPointsBreakdown(context, appState),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: isDark ? Theme.of(context).cardColor : Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade100),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.auto_awesome_rounded, color: Colors.amber, size: 20),
            ),
            const SizedBox(width: 12),
            const Text(
              "Activity Score",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            _buildPointsCapsule(
              context, 
              "${appState.activityPoints} pts",
              icon: appState.currentStreak > 0 ? Icons.local_fire_department_rounded : null,
              iconColor: Colors.orange,
            ),
            const SizedBox(width: 8),
            Icon(Icons.arrow_forward_ios_rounded, size: 12, color: Colors.grey.withOpacity(0.5)),
          ],
        ),
      ),
    );
  }

  Widget _buildPointsCapsule(BuildContext context, String label, {IconData? icon, Color? iconColor}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? Colors.amber.withOpacity(0.2) : Colors.amber.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.amber.withOpacity(0.3) : Colors.amber.shade100,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: iconColor ?? (isDark ? Colors.amber.shade200 : Colors.amber.shade900)),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 13,
              color: isDark ? Colors.amber.shade200 : Colors.amber.shade900,
            ),
          ),
        ],
      ),
    );
  }

  void _showPointsBreakdown(BuildContext context, AppState appState) {
    final achievementsCount = AchievementService().totalUnlocked;
    final memoriesCount = appState.travelMemories.length;
    final streakCount = appState.currentStreak;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        builder: (context, scrollController) => Container(
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 5)),
            ],
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(24),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                "Points Breakdown",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              const Text(
                "Daily actions and milestones fuel your growth.",
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 24),
              _buildBreakdownItem(
                context,
                Icons.emoji_events_rounded,
                "Achievements",
                "$achievementsCount unlocked",
                "+${achievementsCount * 100}",
                Colors.amber,
              ),
              const SizedBox(height: 12),
              _buildBreakdownItem(
                context,
                Icons.travel_explore_rounded,
                "Travel Memories",
                "$memoriesCount recorded",
                "+${memoriesCount * 50}",
                Colors.blue,
              ),
              const SizedBox(height: 12),
              _buildBreakdownItem(
                context,
                Icons.local_fire_department_rounded,
                "Garden Streak",
                "$streakCount active days",
                "+${streakCount * 25}",
                Colors.green,
              ),
              const SizedBox(height: 24),
              Container(height: 1, color: Colors.grey.withOpacity(0.1)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Total Activity Score", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  Text("${appState.activityPoints} pts", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 24, color: Colors.green)),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBreakdownItem(BuildContext context, IconData icon, String title, String subtitle, String points, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
          ),
          Text(points, style: TextStyle(fontWeight: FontWeight.w900, color: color, fontSize: 16)),
        ],
      ),
    );
  }

  void _showPinOptionsBottomSheet(BuildContext context, String cardId, AppState appState) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        margin: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 20),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.push_pin, color: Theme.of(context).primaryColor),
              ),
              title: const Text(
                'Pin to Top',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: const Text('Keep this card at the top of your home screen'),
              onTap: () {
                appState.toggleCardPin(cardId);
                Navigator.pop(context);
                WellnessPalSnackBar.show(
                  context,
                  message: 'Card pinned to top!',
                  icon: Icons.push_pin_rounded,
                );
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget? _buildChallengeCard(BuildContext context, AppState appState) {
    // Find the first dream that isn't fully completed
    Dream? activeDream;
    try {
      activeDream = appState.dreams.firstWhere((d) => !d.isCompleted);
    } catch (_) {
      // No active dreams found
    }

    if (activeDream == null) {
      return null;
    }
    
    final dream = activeDream; // Local non-null variable for compiler promotion
    final masterIndex = appState.dreams.indexOf(dream);
    final isLocked = !appState.isPro && masterIndex >= 3;
    final hasBackgroundImage = dream.backgroundImagePath != null;

    return GestureDetector(
      onTap: () {
        if (isLocked) {
           ProModalUtils.showProLimitModal(context);
        } else {
           _showMicroActionBottomSheet(context, appState);
        }
      },
      child: Container(
        height: hasBackgroundImage ? 220 : null,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(24),
          image: (hasBackgroundImage && !isLocked) ? DecorationImage(
            image: FileImage(File(dream.backgroundImagePath!)),
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(Colors.black.withOpacity(0.4), BlendMode.darken),
          ) : null,
          boxShadow: [
             BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 4))
          ],
          border: Border.all(color: isLocked 
              ? (Theme.of(context).brightness == Brightness.dark ? Colors.white10 : Colors.grey.shade200) 
              : (Theme.of(context).brightness == Brightness.dark ? Colors.white10 : Colors.grey.shade100)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: hasBackgroundImage ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            if (!hasBackgroundImage) ...[
              _buildCardHeader(context, isLocked, dream),
              const SizedBox(height: 16),
            ] else 
               // For background image, put header at top but keep visually separated if needed, 
               // or just let it float. Let's rebuild the header to handle the image context.
               // Actually, let's keep the structure but change colors.
               Expanded(
                 child: Align(
                   alignment: Alignment.topLeft,
                   child: _buildCardHeader(context, isLocked, dream, forceWhite: true),
                 ),
               ),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    dream.title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                          color: (isLocked || hasBackgroundImage) ? Colors.white : null,
                          shadows: hasBackgroundImage ? [
                            Shadow(color: Colors.black.withOpacity(0.5), blurRadius: 8, offset: const Offset(0, 2))
                          ] : null,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  isLocked ? Icons.lock_rounded : Icons.arrow_forward_ios_rounded, 
                  color: hasBackgroundImage ? Colors.white70 : Colors.grey, 
                  size: 16
                ),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: dream.progress,
                minHeight: 8,
                backgroundColor: hasBackgroundImage ? Colors.white24 : Theme.of(context).colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(
                  isLocked ? Colors.grey.shade300 
                  : (hasBackgroundImage ? Colors.white : Theme.of(context).colorScheme.primary)
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isLocked ? "Upgrade to continue this dream" : "${(dream.progress * 100).toInt()}% Completed",
              style: TextStyle(
                fontSize: 12, 
                color: isLocked ? const Color(0xFFFF6B9D) 
                  : (hasBackgroundImage ? Colors.white70 : Colors.grey.shade600), 
                fontWeight: FontWeight.w500
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardHeader(BuildContext context, bool isLocked, Dream dream, {bool forceWhite = false}) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: (isLocked 
                ? Colors.grey 
                : (forceWhite ? Colors.white24 : Theme.of(context).colorScheme.primary.withOpacity(0.1))),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            isLocked ? Icons.lock_outline_rounded : Icons.rocket_launch_rounded, 
            color: isLocked 
                ? Colors.grey 
                : (forceWhite ? Colors.white : Theme.of(context).colorScheme.primary), 
            size: 20
          ),
        ),
        const SizedBox(width: 12),
        Text(
          isLocked ? "PRO VISION LOCKED" : "CONTINUE VISION",
          style: TextStyle(
            fontSize: 12, 
            fontWeight: FontWeight.bold, 
            color: isLocked 
                ? Colors.grey 
                : (forceWhite ? Colors.white : Theme.of(context).colorScheme.outline),
            letterSpacing: 1.0,
            shadows: forceWhite ? [
               Shadow(color: Colors.black.withOpacity(0.3), blurRadius: 4, offset: const Offset(0, 1))
            ] : null,
          ),
        ),
        if (!isLocked && dream.deadline != null) ...[
          const Spacer(),
          () {
            final now = DateTime.now();
            final today = DateTime(now.year, now.month, now.day);
            final deadline = DateTime(dream.deadline!.year, dream.deadline!.month, dream.deadline!.day);
            final daysLeft = deadline.difference(today).inDays;
            
            Color urgencyColor;
            String daysText;
            
            if (daysLeft < 0) {
              urgencyColor = Colors.red;
              daysText = "Overdue";
            } else if (daysLeft == 0) {
              urgencyColor = Colors.red;
              daysText = "Due Today";
            } else if (daysLeft == 1) {
              urgencyColor = Colors.deepOrange;
              daysText = "Due Tomorrow";
            } else if (daysLeft < 4) {
              urgencyColor = Colors.orange;
              daysText = "$daysLeft days left";
            } else if (daysLeft < 8) {
              urgencyColor = Colors.amber.shade700;
              daysText = "$daysLeft days left";
            } else {
              urgencyColor = Theme.of(context).colorScheme.primary;
              daysText = "$daysLeft days left";
            }
            
            // Adjust for white background context
            if (forceWhite) {
               if (urgencyColor == Theme.of(context).colorScheme.primary) {
                 urgencyColor = Colors.white;
               } 
               // else keep the warning colors but maybe brighten them?
               // For simplicity, let's just make text white and background translucent white/colored
            }

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: forceWhite ? urgencyColor.withOpacity(0.2) : urgencyColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: forceWhite ? urgencyColor.withOpacity(0.5) : urgencyColor.withOpacity(0.2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.timer_outlined, size: 12, color: forceWhite ? Colors.white : urgencyColor),
                  const SizedBox(width: 4),
                  Text(
                    daysText,
                    style: TextStyle(
                      fontSize: 10, 
                      fontWeight: FontWeight.w900, 
                      color: forceWhite ? Colors.white : urgencyColor,
                      shadows: forceWhite ? [
                        Shadow(color: Colors.black.withOpacity(0.3), blurRadius: 4, offset: const Offset(0, 1))
                      ] : null,
                    ),
                  ),
                ],
              ),
            );
          }(),
        ],
      ],
    );
  }





  // Journey card replaced by Garden card
  // Keep original method for reference or to be removed later if verified
  Widget? _buildJourneyCard(BuildContext context) {
    return null;
  }

  Widget _buildAchievementsCard(BuildContext context) {
    return Consumer<AchievementService>(
      builder: (context, achievementService, child) {
        // Get first 6 achievements from service for display
        final allAchievements = achievementService.achievements;
        
        // Sort to show unlocked first, then take first 6
        final sortedAchievements = [...allAchievements];
        sortedAchievements.sort((a, b) {
          final aUnlocked = achievementService.isUnlocked(a.id);
          final bUnlocked = achievementService.isUnlocked(b.id);
          if (aUnlocked && !bUnlocked) return -1;
          if (!aUnlocked && bUnlocked) return 1;
          return 0;
        });
        final displayAchievements = sortedAchievements.take(6).toList();

        return GestureDetector(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => const AchievementsScreen(),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Theme.of(context).brightness == Brightness.dark ? Colors.white10 : Colors.grey.shade100),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Achievements',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Row(
                      children: [
                        Text(
                          'View All',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.arrow_forward_ios, size: 12, color: Colors.grey.shade600),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 85,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: displayAchievements.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 16),
                    itemBuilder: (context, index) {
                      final achievement = displayAchievements[index];
                      final isUnlocked = achievementService.isUnlocked(achievement.id);
                      
                      return Column(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
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
                                  fontSize: 24,
                                  color: isUnlocked ? null : Colors.grey.withOpacity(0.5),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            achievement.name,
                            style: TextStyle(
                              fontSize: 10,
                              color: isUnlocked 
                                  ? (Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87)
                                  : (Theme.of(context).brightness == Brightness.dark ? Colors.grey.shade600 : Colors.grey.shade400),
                              fontWeight: isUnlocked ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showMicroActionBottomSheet(BuildContext context, AppState appState) {
    // Get the first incomplete step
    ChallengeStep? nextStepNullable;
    String? dreamTitle;
    String? dreamId;
    
    for (var dream in appState.dreams) {
      for (var step in dream.steps) {
        if (!step.isCompleted) {
          nextStepNullable = step;
          dreamTitle = dream.title;
          dreamId = dream.id;
          break;
        }
      }
      if (nextStepNullable != null) break;
    }

    if (nextStepNullable == null) return;
    
    final nextStep = nextStepNullable;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        margin: const EdgeInsets.all(16),
        child: Container(
          padding: const EdgeInsets.all(32.0),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(40),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 30,
                offset: const Offset(0, 10),
              )
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Close button
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                ),
              ),
              
              // Dream tag
              if (dreamTitle != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    dreamTitle.toUpperCase(),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.secondary,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
              const SizedBox(height: 32),
              
              // Timer icon
              Icon(
                Icons.timer_outlined,
                size: 40,
                color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
              ),
              const SizedBox(height: 8),
              Text(
                '${nextStep.durationMinutes} MIN',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                ),
              ),
              const SizedBox(height: 24),
              
              // Task title
              Text(
                nextStep.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 32),
              
              // Complete button
              SizedBox(
                width: double.infinity,
                height: 64,
                child: ElevatedButton(
                  onPressed: () async {
                    if (dreamId != null) {
                      final newAchievements = await appState.toggleStepCompletion(dreamId, nextStep.id);
                      if (context.mounted) {
                        Navigator.pop(context);
                        
                        // Check if the dream was just completed
                        final updatedDream = appState.dreams.firstWhere((d) => d.id == dreamId);
                        if (updatedDream.isCompleted) {
                           await Navigator.of(context).push(
                             MaterialPageRoute(
                               builder: (context) => DreamCompletionPage(dream: updatedDream),
                             ),
                           );
                        } else {
                          onConfettiPlay?.call(); // Play confetti!
                          WellnessPalSnackBar.show(
                            context,
                            message: 'Micro-action completed!',
                            icon: Icons.check_circle_rounded,
                            iconColor: Colors.green,
                          );
                        }

                        // Check for new achievements to display
                        if (context.mounted && newAchievements.isNotEmpty) {
                          for (final achievement in newAchievements) {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => AchievementCompletionPage(achievement: achievement),
                                fullscreenDialog: true,
                              ),
                            );
                            // Add a small delay if there are multiple to avoid stacking weirdness
                            if (newAchievements.length > 1) {
                              await Future.delayed(const Duration(seconds: 2)); 
                            }
                          }
                        }
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(32),
                    ),
                  ),
                  child: const Text(
                    'I did it!',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              
              // Skip button
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  WellnessPalSnackBar.show(
                    context,
                    message: "We'll skip this one for now!",
                    icon: Icons.refresh_rounded,
                  );
                },
                icon: Icon(Icons.refresh_rounded, size: 18, color: Theme.of(context).colorScheme.outline),
                label: Text(
                  "Give me something easier",
                  style: TextStyle(color: Theme.of(context).colorScheme.outline),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }





  Widget _buildWorldMapCard(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        if (appState.travelMemories.isEmpty) return const SizedBox.shrink();

        // Calculate stats
        Map<String, int> countryVisits = {};
        for (var memory in appState.travelMemories) {
          String country = memory.place;
          if (country.contains(',')) {
            country = country.split(',').last.trim();
          }
          if (country.isNotEmpty) {
            countryVisits[country] = (countryVisits[country] ?? 0) + 1;
          }
        }

        final isPinned = appState.pinnedCardIds.contains(kCardMap);
        
        return GestureDetector(
          onTap: () {
            showModalBottomSheet(
      context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (context) => const WorldMapSheet(),
            );
          },
          onLongPress: isPinned ? null : () {
            showModalBottomSheet(
      context: context,
              backgroundColor: Colors.transparent,
              builder: (context) => Container(
                margin: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Handle bar
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(top: 12, bottom: 20),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    // Pin to Top option
                    ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).primaryColor.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.push_pin, color: Theme.of(context).primaryColor),
                      ),
                      title: const Text(
                        'Pin to Top',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: const Text('Keep this card at the top of your home screen'),
                      onTap: () {
                        appState.toggleCardPin(kCardMap);
                        Navigator.pop(context);
                        WellnessPalSnackBar.show(
                          context,
                          message: 'Card pinned to top!',
                          icon: Icons.push_pin_rounded,
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            );
          },
          child: Stack(
            children: [
              Container(
            width: double.infinity,
            height: 280,
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Theme.of(context).brightness == Brightness.dark ? Colors.white10 : Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Map Background
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Opacity(
                  opacity: 0.8,
                  child: WorldMapSvg(countryVisits: countryVisits),
                ),
              ),

              // Passport Button (Top Right)
              Positioned(
                top: 16,
                right: 16,
                child: GestureDetector(
                  onTap: () {
                    showModalBottomSheet(
      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (context) => const PassportBottomSheet(),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        )
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.badge_rounded, size: 14, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 6),
                        const Text(
                          'PASSPORT',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              
              // Overlay Content
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: (Theme.of(context).brightness == Brightness.dark 
                                ? Theme.of(context).cardColor 
                                : Colors.white).withOpacity(0.9),
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)
                            ],
                          ),
                          child: const Icon(Icons.public, size: 20, color: Colors.blue),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: (Theme.of(context).brightness == Brightness.dark 
                                ? Theme.of(context).cardColor 
                                : Colors.white).withOpacity(0.9),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${countryVisits.length} Countries',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: (Theme.of(context).brightness == Brightness.dark 
                            ? Theme.of(context).cardColor 
                            : Colors.white).withOpacity(0.95),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'My Travel Map',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.arrow_forward_ios_rounded, size: 12, color: Colors.grey.shade700),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Pin badge when card is pinned
        if (isPinned)
          Positioned(
            top: 12,
            right: 12,
            child: GestureDetector(
              onTap: () => appState.toggleCardPin(kCardMap),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (Theme.of(context).brightness == Brightness.dark 
                      ? Theme.of(context).cardColor 
                      : Colors.white).withOpacity(0.9),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.push_pin,
                  size: 18,
                  color: Theme.of(context).primaryColor,
                ),
              ),
            ),
          ),
        ],
      ),
    );
      },
    );
  }

  Widget _buildSkeletonLoader(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade200;
    final shimmerColor = isDark ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(0.5);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Greeting Skeleton
        Container(
          height: 32,
          width: 150,
          decoration: BoxDecoration(
            color: baseColor,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 40,
          width: 220,
          decoration: BoxDecoration(
            color: baseColor,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        const SizedBox(height: 32),

        // Cards Skeleton
        ...List.generate(4, (index) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Container(
              height: 160,
              width: double.infinity,
              decoration: BoxDecoration(
                color: baseColor,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isDark ? Colors.white.withOpacity(0.05) : Colors.transparent
                )
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildPinnedJournalCard(BuildContext context, JournalEntry entry, AppState appState) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = Color(entry.color);
    final iconColor = isDark 
        ? Colors.white.withOpacity(0.9) 
        : Color.lerp(accentColor, Colors.black, 0.4) ?? accentColor;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? Theme.of(context).cardColor : Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Color.lerp(accentColor, Colors.black, 0.2) ?? accentColor,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.assignment_turned_in_rounded, size: 16, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  entry.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () {
                   appState.toggleJournalPinToHome(entry.id);
                   WellnessPalSnackBar.show(context, message: "Removed from Home", icon: Icons.home_outlined);
                },
                child: Icon(Icons.close_rounded, size: 18, color: Colors.grey.withOpacity(0.5)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...entry.todos.take(5).map((todo) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              onTap: () async {
                 final newAchievements = await appState.toggleTodoItem(entry.id, todo.id);
                 if (context.mounted && newAchievements.isNotEmpty) {
                    for (final achievement in newAchievements) {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => AchievementCompletionPage(achievement: achievement),
                            fullscreenDialog: true,
                          ),
                        );
                        if (newAchievements.length > 1) {
                           await Future.delayed(const Duration(milliseconds: 500));
                        }
                    }
                 }
              },
              borderRadius: BorderRadius.circular(8),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: todo.isCompleted ? const Color(0xFF4CAF50) : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: todo.isCompleted 
                            ? const Color(0xFF4CAF50) 
                            : (isDark ? Colors.white30 : Colors.black26),
                        width: 1.5,
                      ),
                    ),
                    child: todo.isCompleted 
                        ? const Icon(Icons.check, size: 12, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      todo.text,
                      style: TextStyle(
                        fontSize: 14,
                        decoration: todo.isCompleted ? TextDecoration.lineThrough : null,
                        color: todo.isCompleted ? Colors.grey.withOpacity(0.4) : (isDark ? Colors.white70 : Colors.black87),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )),
          if (entry.todos.length > 5)
             Padding(
               padding: const EdgeInsets.only(top: 4, left: 32),
               child: Text(
                 "+${entry.todos.length - 5} more items",
                 style: TextStyle(fontSize: 12, color: Colors.grey.withOpacity(0.5), fontStyle: FontStyle.italic),
               ),
             ),
        ],
      ),
    );
  }
}
