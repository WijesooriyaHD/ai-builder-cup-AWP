import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import 'add_dream_screen.dart';
import 'wellness_intention_detail_screen.dart';
import '../models/dream.dart';
import 'dart:io';
import 'package:flutter_animate/flutter_animate.dart';
import '../widgets/custom_tab_switcher.dart';
import '../utils/pro_modal_utils.dart';
import '../utils/icon_resolver.dart';
import 'package:lottie/lottie.dart';
import 'achievement_completion_page.dart';
import '../data/dream_templates.dart';

class DreamsScreen extends StatefulWidget {
  const DreamsScreen({super.key});

  @override
  State<DreamsScreen> createState() => _DreamsScreenState();
}

class _DreamsScreenState extends State<DreamsScreen> with TickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showAddDreamBottomSheet(BuildContext context) {
    bool isLoading = false;
    int? loadingColor;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setBottomSheetState) {
          if (isLoading && loadingColor != null) {
            return _DreamTemplateLoader(selectedColor: loadingColor!);
          }

          return Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            height: MediaQuery.of(context).size.height * 0.7,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(32),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Start Something New",
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 24),
                      
                      // Start from scratch option
                      InkWell(
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const AddDreamScreen()),
                          );
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Theme.of(context).primaryColor.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Theme.of(context).primaryColor.withOpacity(0.1)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).primaryColor,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.add_rounded, color: Colors.white, size: 24),
                              ),
                              const SizedBox(width: 16),
                              const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("Start from scratch", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                  Text("Define your own big goal", style: TextStyle(color: Colors.grey, fontSize: 13)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 32),
                      Text(
                        "Choose from a template",
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
                
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    itemCount: dreamTemplates.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (ctx, index) {
                      final template = dreamTemplates[index];
                      return InkWell(
                        onTap: () async {
                          final appState = Provider.of<AppState>(context, listen: false);
                          
                          // Check for Pro limit: 3 dreams max for free users
                          if (!appState.isPro && appState.dreams.length >= 3) {
                            Navigator.pop(context);
                            ProModalUtils.showProLimitModal(context);
                            return;
                          }

                          // Enter loading state internally
                          setBottomSheetState(() {
                            isLoading = true;
                            loadingColor = template.color;
                          });

                          try {
                            final newAchievements = await appState.addDream(
                              template.title,
                              themeColor: template.color,
                              themeIcon: template.icon.codePoint,
                              initialSteps: template.steps,
                            );

                            if (context.mounted) {
                              Navigator.pop(context); // Close the entire bottom sheet
                              
                              if (newAchievements.isNotEmpty) {
                                for (final achievement in newAchievements) {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (context) => AchievementCompletionPage(achievement: achievement),
                                      fullscreenDialog: true,
                                    ),
                                  );
                                  if (newAchievements.length > 1) {
                                    await Future.delayed(const Duration(seconds: 2));
                                  }
                                }
                              }
                            }
                          } catch (e) {
                            if (context.mounted) {
                              setBottomSheetState(() => isLoading = false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text("Failed to add dream: $e")),
                              );
                            }
                          }
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Color(template.color).withOpacity(0.05),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Color(template.color).withOpacity(0.1)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Color(template.color).withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(template.icon, color: Color(template.color), size: 24),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(template.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                    const SizedBox(height: 2),
                                    Text(
                                      template.socialProof, 
                                      style: TextStyle(
                                        color: Color(template.color).withOpacity(0.8), 
                                        fontSize: 12, 
                                        fontWeight: FontWeight.w500
                                      )
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(template.color).withOpacity(0.5)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        final pendingDreams = appState.dreams.where((d) => !d.isCompleted).toList();
        final completedDreams = appState.dreams.where((d) => d.isCompleted).toList();
        
        // Calculate remaining (including completed dreams)
        final freeLimit = 3;
        final remaining = (freeLimit - appState.dreams.length).clamp(0, freeLimit);

        return Scaffold(
          appBar: AppBar(
            centerTitle: false,
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('My Dreams', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 12),
                if (!appState.isPro) 
                  GestureDetector(
                    onTap: () {
                      if (remaining == 0) ProModalUtils.showProLimitModal(context);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: remaining > 0 ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: remaining > 0 ? Colors.green.withOpacity(0.3) : Colors.orange.withOpacity(0.3)
                        )
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            remaining > 0 ? Icons.check_circle_outline : Icons.star_rounded,
                            size: 12,
                            color: remaining > 0 ? Colors.green : Colors.orange,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            remaining > 0 ? "$remaining free" : "Upgrade",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: remaining > 0 ? Colors.green : Colors.orange,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (appState.isPro)
                  Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.purple.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.purple.withOpacity(0.2))
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.all_inclusive_rounded, size: 14, color: Colors.purple),
                          SizedBox(width: 4),
                          Text("Premium", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.purple)),
                        ],
                      )
                  )
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.add_circle_outline_rounded),
                onPressed: () => _showAddDreamBottomSheet(context),
              )
            ],
          ),
          body: Column(
            children: [
               const SizedBox(height: 16),
               CustomTabSwitcher(
                 tabController: _tabController,
                 tabs: const ["Yet to Do", "Completed"],
                 icons: const [Icons.auto_awesome_rounded, Icons.check_circle_rounded],
               ),
               const SizedBox(height: 16),
               Expanded(
                 child: TabBarView(
                   controller: _tabController,
                   children: [
                     _buildDreamsList(context, pendingDreams, isEmpty: pendingDreams.isEmpty, emptyMessage: "No active dreams. Start one!"),
                     _buildCompletedTab(context, completedDreams),
                   ],
                 ),
               )
            ],
          ),
        );
      },
    );
  }

  Widget _buildCompletedTab(BuildContext context, List<Dream> completedDreams) {
     if (completedDreams.isEmpty) {
        return _buildEmptyState(context, "No completed dreams yet.", "Keep going! You got this.");
     }

     return SingleChildScrollView(
       padding: const EdgeInsets.all(16),
       child: Column(
         children: [
           // Stats Card
           Container(
             width: double.infinity,
             padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
             decoration: BoxDecoration(
               color: Theme.of(context).cardColor,
               borderRadius: BorderRadius.circular(32),
               border: Border.all(
                 color: Theme.of(context).brightness == Brightness.dark ? Colors.white10 : Colors.grey.shade100,
                 width: 1,
               ),
               boxShadow: [
                 BoxShadow(
                   color: Colors.black.withOpacity(0.03),
                   blurRadius: 20,
                   offset: const Offset(0, 10),
                 )
               ],
             ),
             child: Column(
               children: [
                 Container(
                   padding: const EdgeInsets.all(12),
                   decoration: BoxDecoration(
                     color: Colors.green.withOpacity(0.1),
                     shape: BoxShape.circle,
                   ),
                   child: const Icon(Icons.emoji_events_rounded, color: Colors.green, size: 32),
                 ),
                 const SizedBox(height: 16),
                 Text(
                   "${completedDreams.length}",
                   style: TextStyle(
                     color: Theme.of(context).textTheme.bodyLarge?.color, 
                     fontSize: 48, 
                     fontWeight: FontWeight.w900,
                     height: 1.0,
                   ),
                 ),
                 const SizedBox(height: 8),
                 Text(
                   "Dreams Achieved", 
                   style: TextStyle(
                     color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6), 
                     fontSize: 16, 
                     fontWeight: FontWeight.w600
                   )
                 ),
                 const SizedBox(height: 4),
                 Text(
                    "You're unstoppable!", 
                    style: TextStyle(
                      color: Theme.of(context).primaryColor, 
                      fontSize: 12, 
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    )
                 ),
               ],
             ),
           ),
           
           const SizedBox(height: 24),
           
           // List of completed items
           ListView.builder(
             shrinkWrap: true,
             physics: const NeverScrollableScrollPhysics(),
             itemCount: completedDreams.length,
             itemBuilder: (context, index) {
                return _buildDreamCard(context, completedDreams[index]);
             },
           )
         ],
       ),
     );
  }

  Widget _buildDreamsList(BuildContext context, List<Dream> dreams, {required bool isEmpty, required String emptyMessage}) {
    if (isEmpty) {
      return _buildEmptyState(context, emptyMessage, "Tap + to add your first big dream.");
    }

    return Consumer<AppState>(
      builder: (context, appState, child) {
        // Sort dreams: Pinned first
        final sortedDreams = [...dreams];
        sortedDreams.sort((a, b) {
          final isAPinned = appState.pinnedDreamIds.contains(a.id);
          final isBPinned = appState.pinnedDreamIds.contains(b.id);
          if (isAPinned && !isBPinned) return -1;
          if (!isAPinned && isBPinned) return 1;
          return 0;
        });

        final freeLimit = 3;
        final isLimitReached = !appState.isPro && dreams.length >= freeLimit;

        // Simple List without inner ScrollView to avoid conflicts if needed, 
        // but here it is the only child of TabBarView -> Column -> Expanded, so it needs to scroll.
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: sortedDreams.length + (isLimitReached ? 1 : 0),
          itemBuilder: (context, index) {
            if (isLimitReached && index == 0) {
              return GestureDetector(
                onTap: () => ProModalUtils.showProLimitModal(context),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.orange.shade400, Colors.deepOrange.shade400],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.orange.withOpacity(0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.lock_rounded, color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Dream Limit Reached",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "Upgrade to Premium for unlimited dreams",
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 16),
                    ],
                  ),
                ),
              );
            }

            final dream = sortedDreams[index - (isLimitReached ? 1 : 0)];
            final masterIndex = appState.dreams.indexOf(dream);
            final isLocked = !appState.isPro && masterIndex >= 3;
            
            return _buildDreamCard(context, dream, isLocked: isLocked);
          },
        );
      },
    );
  }

  Widget _buildDreamCard(BuildContext context, Dream dream, {bool isLocked = false}) {
      final appState = Provider.of<AppState>(context, listen: false);
      final isPinned = appState.pinnedDreamIds.contains(dream.id);
      final themeColor = isLocked ? Colors.grey : (dream.themeColor != null ? Color(dream.themeColor!) : Theme.of(context).colorScheme.primary);
      final themeIcon = dream.themeIcon != null ? resolveIconData(dream.themeIcon!) : Icons.star_rounded;
      final hasBackgroundImage = dream.backgroundImagePath != null;

      return GestureDetector(
        onTap: () {
           if (isLocked) {
             ProModalUtils.showProLimitModal(context);
           } else {
             Navigator.push(context, MaterialPageRoute(builder: (_) => WellnessIntentionDetailScreen(intentionId: dream.id)));
           }
        },
        onLongPress: () {
          if (!isLocked) {
            _showDreamOptionsBottomSheet(context, dream, appState);
          }
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
            border: isLocked 
                ? Border.all(color: Colors.grey.shade200) 
                : (isPinned ? Border.all(color: themeColor.withOpacity(0.3), width: 2) : null),
          ),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hasBackgroundImage)
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                      child: Image.file(
                        File(dream.backgroundImagePath!),
                        height: 140,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isLocked ? Colors.grey.shade100 : themeColor.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                isLocked ? Icons.lock_outline_rounded : themeIcon,
                                color: isLocked ? Colors.grey : themeColor,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          dream.title,
                                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                             decoration: dream.isCompleted ? TextDecoration.lineThrough : null,
                                             color: (isLocked || dream.isCompleted) 
                                                ? Colors.grey 
                                                : Theme.of(context).textTheme.bodyLarge?.color
                                          ),
                                        ),
                                      ),
                                      if (isLocked)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade100,
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: const Row(
                                            children: [
                                              Icon(Icons.lock_rounded, size: 10, color: Colors.grey),
                                              SizedBox(width: 4),
                                              Text("LOCKED", style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  if (!dream.isCompleted)
                                     LinearProgressIndicator(
                                       value: dream.progress,
                                       backgroundColor: Colors.grey.shade100,
                                       color: isLocked ? Colors.grey.shade300 : themeColor,
                                       borderRadius: BorderRadius.circular(10),
                                       minHeight: 8,
                                     ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        dream.isCompleted 
                                          ? "Completed!" 
                                          : (isLocked ? "Pro Feature" : '${(dream.progress * 100).toInt()}% Complete'),
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: dream.isCompleted ? Colors.green : Colors.grey,
                                          fontWeight: (dream.isCompleted || isLocked) ? FontWeight.bold : null
                                        ),
                                      ),
                                      if (dream.deadline != null && !dream.isCompleted && !isLocked)
                                         Text(
                                            "${dream.deadline!.difference(DateTime.now()).inDays} days left",
                                            style: TextStyle(color: themeColor, fontSize: 12, fontWeight: FontWeight.bold),
                                         )
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (isPinned)
                Positioned(
                  top: hasBackgroundImage ? 12 : 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: hasBackgroundImage ? Colors.white.withOpacity(0.9) : Colors.transparent,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.push_pin, size: 16, color: Colors.grey),
                  ),
                ),
            ],
          ),
        ),
      ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0);
  }

  void _showDreamOptionsBottomSheet(BuildContext context, Dream dream, AppState appState) {
    final isPinned = appState.pinnedDreamIds.contains(dream.id);
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark 
              ? Theme.of(context).cardColor 
              : Colors.white,
          borderRadius: BorderRadius.circular(32),
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
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark 
                    ? Colors.white.withOpacity(0.1) 
                    : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            _buildOptionTile(
              context,
              icon: isPinned ? Icons.push_pin : Icons.push_pin_outlined,
              title: isPinned ? "Unpin Dream" : "Pin to Top",
              color: Colors.blue,
              onTap: () {
                appState.toggleDreamPin(dream.id);
                Navigator.pop(context);
              },
            ),
            const Divider(height: 1, indent: 24, endIndent: 24),
            _buildOptionTile(
              context,
              icon: Icons.delete_outline_rounded,
              title: "Delete Dream",
              color: Colors.red,
              onTap: () {
                Navigator.pop(context);
                _confirmDelete(context, appState, dream.id);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionTile(BuildContext context, {required IconData icon, required String title, required Color color, required VoidCallback onTap}) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: 24),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 16,
          color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black,
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, AppState appState, String dreamId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark 
              ? Theme.of(context).cardColor 
              : Colors.white,
          borderRadius: BorderRadius.circular(32),
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
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_forever_rounded, color: Colors.red, size: 32),
            ),
            const SizedBox(height: 20),
            Text(
              "Delete Dream?",
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              "This action cannot be undone. All its progress, notes, and milestones will be permanently removed.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, height: 1.4),
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text("Cancel", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      appState.deleteDream(dreamId);
                      Navigator.pop(ctx);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text("Delete", style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }



  Widget _buildEmptyState(BuildContext context, String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Lottie.asset(
            'assets/images/wellness-rhythm.json',
            height: 280,
            repeat: true,
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(subtitle, style: TextStyle(color: Colors.grey.shade600)),
        ],
      ),
    );
  }
}

class _DreamTemplateLoader extends StatefulWidget {
  final int selectedColor;
  const _DreamTemplateLoader({required this.selectedColor});

  @override
  State<_DreamTemplateLoader> createState() => _DreamTemplateLoaderState();
}

class _DreamTemplateLoaderState extends State<_DreamTemplateLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(32),
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
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            width: 200,
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark 
                    ? Colors.transparent 
                    : Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Lottie.asset(
                'assets/images/loading.json',
                controller: _controller,
                onLoaded: (composition) {
                  _controller.duration = Duration(milliseconds: (composition.duration.inMilliseconds / 6.0).round());
                  _controller.repeat();
                },
                delegates: LottieDelegates(
                  values: [
                    ValueDelegate.color(
                      const ['**'],
                      value: Color(widget.selectedColor),
                    ),
                  ],
                ),
                frameRate: FrameRate.composition,
                errorBuilder: (context, error, stackTrace) {
                  return Center(
                    child: CircularProgressIndicator(
                      color: Color(widget.selectedColor),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            "Setting up your dream...",
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          const Text(
            "We're preparing your journey with the best tools and milestones.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
