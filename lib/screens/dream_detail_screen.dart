import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:confetti/confetti.dart';
import '../providers/app_state.dart';
import '../models/dream.dart';
import '../models/challenge_step.dart';
import '../widgets/confetti_overlay.dart';
import 'achievement_completion_page.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../utils/icon_resolver.dart';

class DreamDetailScreen extends StatefulWidget {
  final String dreamId;
  const DreamDetailScreen({super.key, required this.dreamId});

  @override
  State<DreamDetailScreen> createState() => _DreamDetailScreenState();
}

class _DreamDetailScreenState extends State<DreamDetailScreen> {
  // Track which steps are currently being toggled
  final Set<String> _loadingStepIds = {};
  late ConfettiController _confettiController;
  bool _showPendingFirst = false;
  bool _isRearranging = false;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(duration: const Duration(seconds: 1));
  }

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        final dreamIndex = appState.dreams.indexWhere((d) => d.id == widget.dreamId);
        if (dreamIndex == -1) {
           return const Scaffold(body: Center(child: Text("Dream not found")));
        }
        final dream = appState.dreams[dreamIndex];
        
        // Use theme color if available, else primary
        final themeColor = dream.themeColor != null ? Color(dream.themeColor!) : Theme.of(context).primaryColor;
        final themeIcon = dream.themeIcon != null ? resolveIconData(dream.themeIcon!) : Icons.star_rounded;

        // Calculate time left
        String timeLeft = "No Deadline";
        if (dream.isCompleted) {
          timeLeft = "Goal Reached!";
        } else if (dream.deadline != null) {
          final diff = dream.deadline!.difference(DateTime.now());
          if (diff.isNegative) {
            timeLeft = "Overdue!";
          } else {
            timeLeft = "${diff.inDays} days left";
          }
        }

        // Sort steps if filter is active
        final displaySteps = List<ChallengeStep>.from(dream.steps);
        if (_showPendingFirst) {
          displaySteps.sort((a, b) {
            if (a.isCompleted == b.isCompleted) return 0;
            return a.isCompleted ? 1 : -1; // Pending (false) comes first
          });
        }

        return Scaffold(
          body: ConfettiOverlay(
            controller: _confettiController,
            child: CustomScrollView(
              slivers: [
                SliverAppBar(
                  expandedHeight: 250.0,
                  floating: false,
                  pinned: true,
                  backgroundColor: themeColor,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
                  ),
                  flexibleSpace: FlexibleSpaceBar(
                    title: Text(dream.title, 
                        style: const TextStyle(
                            color: Colors.white, 
                            fontWeight: FontWeight.bold,
                            shadows: [Shadow(color: Colors.black45, blurRadius: 10)]
                        )
                    ),
                    background: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Background Image or Gradient base
                         dream.backgroundImagePath != null 
                            ? Container(
                                margin: const EdgeInsets.only(bottom: 2), // Match gradient margin
                                child: ClipRRect(
                                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
                                  child: Image.file(
                                    File(dream.backgroundImagePath!), 
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) => Container(color: themeColor),
                                  ),
                                ),
                              )
                            : Container(
                                margin: const EdgeInsets.only(bottom: 2),
                                decoration: BoxDecoration(
                                  color: themeColor,
                                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
                                ),
                              ),
                        
                        // Gradient Overlay
                        Container(
                          margin: const EdgeInsets.only(bottom: 2),
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: dream.backgroundImagePath != null 
                                ? [
                                    Colors.transparent,
                                    Colors.black.withOpacity(0.0), // Extra clear zone
                                    themeColor.withOpacity(0.8), // Text legibility
                                  ]
                                : [
                                    themeColor,
                                    themeColor.withOpacity(0.7),
                                  ],
                                stops: dream.backgroundImagePath != null 
                                  ? [0.0, 0.5, 1.0] 
                                  : [0.0, 1.0],
                            ),
                          ),
                          child: dream.backgroundImagePath == null 
                              ? Center(
                                  child: Icon(themeIcon, size: 100, color: Colors.white.withOpacity(0.3)),
                                )
                              : null,
                        ),
                      ],
                    ),
                  ),
                  actions: [
                     Container(
                       margin: const EdgeInsets.only(right: 8),
                       width: 36,
                       height: 36,
                       decoration: BoxDecoration(
                         color: Colors.black.withOpacity(0.3),
                         shape: BoxShape.circle,
                       ),
                       child: IconButton(
                         padding: EdgeInsets.zero,
                         icon: const Icon(Icons.add_photo_alternate_outlined, color: Colors.white, size: 18),
                         tooltip: "Change Cover",
                         onPressed: () => _pickBackgroundImage(context, appState, dream),
                       ),
                     ),
                     Container(
                       margin: const EdgeInsets.only(right: 16),
                       width: 36,
                       height: 36,
                       decoration: BoxDecoration(
                         color: Colors.black.withOpacity(0.3),
                         shape: BoxShape.circle,
                       ),
                       child: IconButton(
                         padding: EdgeInsets.zero,
                         icon: const Icon(Icons.delete_outline, color: Colors.white, size: 18),
                         tooltip: "Delete Dream",
                         onPressed: () {
                            // Allow deleting logic via dialog
                            _confirmDelete(context, appState, dream.id);
                         },
                       ),
                     )
                  ],
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                             GestureDetector(
                               onLongPress: () => _pickDeadline(context, appState, dream),
                               child: _buildStatCard(context, timeLeft, Icons.timer_outlined, Colors.orange),
                             ),
                             _buildStatCard(context, "${(dream.progress * 100).toInt()}% Done", Icons.pie_chart_outline, Colors.green),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text("Your Journey", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                            Row(
                              children: [
                                InkWell(
                                  onTap: () {
                                    setState(() {
                                      _isRearranging = !_isRearranging;
                                      if (_isRearranging) _showPendingFirst = false;
                                    });
                                  },
                                  borderRadius: BorderRadius.circular(20),
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).primaryColor.withOpacity(0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      _isRearranging ? Icons.check_rounded : Icons.reorder_rounded,
                                      size: 20,
                                      color: Theme.of(context).primaryColor,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                TextButton.icon(
                                  onPressed: () {
                                    setState(() {
                                      _showPendingFirst = !_showPendingFirst;
                                      if (_showPendingFirst) _isRearranging = false;
                                    });
                                  },
                                  icon: Icon(
                                    _showPendingFirst ? Icons.filter_list_off : Icons.filter_list,
                                    size: 18,
                                    color: Theme.of(context).primaryColor,
                                  ),
                                  label: Text(
                                    _showPendingFirst ? "All" : "Pending",
                                    style: TextStyle(
                                      color: Theme.of(context).primaryColor,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final step = displaySteps[index];
                      // Find actual index for numbering if sorted? 
                      // Or just use the display index? User probably cares about sequence.
                      // If we sort, the numbers 1, 2, 3... will correspond to the new order.
                      // If we want to preserve original step numbers, we need to find the index in original list.
                      final originalIndex = dream.steps.indexOf(step);
                      
                      final isStepLoading = _loadingStepIds.contains(step.id);

                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                        child: Card(
                           shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                           elevation: 0,
                           color: step.isCompleted 
                               ? (Theme.of(context).brightness == Brightness.dark ? Colors.white10 : Colors.grey[100])
                               : Theme.of(context).cardColor,
                           // Custom Row with Animated Checkbox
                           child: InkWell(
                             onTap: () async {
                               if (isStepLoading) return;
                               setState(() => _loadingStepIds.add(step.id));
                               
                               try {
                                 final wasCompleted = step.isCompleted;
                                 final newAchievements = await appState.toggleStepCompletion(dream.id, step.id);
                                 
                                 if (!mounted) return;
                                 
                                 if (!wasCompleted) {
                                    _confettiController.play();
                                 }
                                 
                                 if (newAchievements.isNotEmpty) {
                                   for (final achievement in newAchievements) {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (context) => AchievementCompletionPage(achievement: achievement),
                                          fullscreenDialog: true,
                                        ),
                                      );
                                      await Future.delayed(const Duration(seconds: 3));
                                   }
                                 }
                               } finally {
                                 if (mounted) {
                                   setState(() => _loadingStepIds.remove(step.id));
                                 }
                               }
                             },
                             onLongPress: () {
                               _showEditStepDialog(context, appState, dream, step);
                             },
                             borderRadius: BorderRadius.circular(16),
                             child: Padding(
                               padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                               child: Row(
                                 children: [
                                   // Number Circle (Use original index + 1 to keep context)
                                   Container(
                                     padding: const EdgeInsets.all(10),
                                     decoration: BoxDecoration(
                                       color: themeColor.withOpacity(0.1),
                                       shape: BoxShape.circle,
                                     ),
                                     child: Text("${originalIndex + 1}", style: TextStyle(color: themeColor, fontWeight: FontWeight.bold)),
                                   ),
                                   const SizedBox(width: 16),
                                   // Text
                                   Expanded(
                                     child: Column(
                                       crossAxisAlignment: CrossAxisAlignment.start,
                                       children: [
                                         Text(
                                            step.title, 
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w500,
                                              decoration: step.isCompleted ? TextDecoration.lineThrough : null,
                                              color: step.isCompleted 
                                                  ? Colors.grey 
                                                  : Theme.of(context).textTheme.bodyLarge?.color,
                                            )
                                          ),
                                          if (step.durationMinutes > 0) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              "${step.durationMinutes} mins",
                                              style: TextStyle(
                                                fontSize: 12, 
                                                color: Theme.of(context).brightness == Brightness.dark 
                                                    ? Colors.white54 
                                                    : Colors.grey.shade500
                                              ),
                                            ),
                                          ]
                                       ],
                                     ),
                                   ),
                                   if (_isRearranging) ...[
                                     Column(
                                       mainAxisSize: MainAxisSize.min,
                                       children: [
                                         if (originalIndex > 0)
                                           GestureDetector(
                                             onTap: () => _reorderStep(dream, appState, originalIndex, originalIndex - 1),
                                             child: Icon(Icons.keyboard_arrow_up_rounded, size: 22, color: themeColor.withOpacity(0.5)),
                                           ),
                                         if (originalIndex < dream.steps.length - 1)
                                           GestureDetector(
                                             onTap: () => _reorderStep(dream, appState, originalIndex, originalIndex + 1),
                                             child: Icon(Icons.keyboard_arrow_down_rounded, size: 22, color: themeColor.withOpacity(0.5)),
                                           ),
                                       ],
                                     ),
                                     const SizedBox(width: 8),
                                   ],
                                   // Custom Animated Checkbox
                                   _AnimatedCheckbox(
                                     isChecked: step.isCompleted,
                                     isLoading: isStepLoading,
                                     activeColor: themeColor,
                                   ),
                                 ],
                               ),
                             ),
                           ),
                        ),
                       );
                    },
                    childCount: displaySteps.length,
                  ),
                ),
                if (!_isRearranging)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: InkWell(
                      onTap: () => _showAddStepDialog(context, appState, dream),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          border: Border.all(color: themeColor.withOpacity(0.3), style: BorderStyle.solid),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_rounded, color: themeColor),
                            const SizedBox(width: 8),
                            Text("Add Step", style: TextStyle(color: themeColor, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SliverPadding(padding: EdgeInsets.only(bottom: 40)),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showEditStepDialog(BuildContext context, AppState appState, Dream dream, ChallengeStep step) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final controller = TextEditingController(text: step.title);
        
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(32),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08), 
                  blurRadius: 20, 
                  offset: const Offset(0, 5)
                )
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
                  ),
                  const SizedBox(height: 16),
                  
                  Text(
                    "Edit Step", 
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)
                  ),
                  const SizedBox(height: 24),
                  
                  TextField(
                    controller: controller,
                    autofocus: true,
                    minLines: 1,
                    maxLines: 3,
                    style: const TextStyle(fontSize: 16),
                    decoration: InputDecoration(
                      hintText: "What's the step?",
                      filled: true,
                      fillColor: Theme.of(context).brightness == Brightness.dark
                          ? Theme.of(context).scaffoldBackgroundColor
                          : Colors.grey[50],
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  Row(
                    children: [
                       Expanded(
                         child: TextButton(
                           onPressed: () {
                             // Delete logic
                             final index = dream.steps.indexWhere((s) => s.id == step.id);
                             if (index != -1) {
                               dream.steps.removeAt(index);
                               appState.updateDream(dream);
                             }
                             Navigator.pop(context);
                           },
                           style: TextButton.styleFrom(
                             foregroundColor: Colors.red,
                             padding: const EdgeInsets.symmetric(vertical: 16),
                             backgroundColor: Colors.red.withOpacity(0.1),
                             shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                           ),
                           child: const Text("Delete", style: TextStyle(fontWeight: FontWeight.bold)),
                         ),
                       ),
                       const SizedBox(width: 12),
                       Expanded(
                         child: ElevatedButton(
                           onPressed: () {
                               final newTitle = controller.text.trim();
                               if (newTitle.isNotEmpty) {
                                  final index = dream.steps.indexWhere((s) => s.id == step.id);
                                  if (index != -1) {
                                    dream.steps[index] = step.copyWith(title: newTitle);
                                    appState.updateDream(dream);
                                  }
                               }
                               Navigator.pop(context);
                           },
                           style: ElevatedButton.styleFrom(
                             backgroundColor: Theme.of(context).brightness == Brightness.dark 
                                 ? Theme.of(context).scaffoldBackgroundColor 
                                 : Colors.black,
                             foregroundColor: Colors.white,
                             padding: const EdgeInsets.symmetric(vertical: 16),
                             shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                           ),
                           child: const Text("Save", style: TextStyle(fontWeight: FontWeight.bold)),
                         ),
                       ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatCard(BuildContext context, String title, IconData icon, Color color) {
    return Container(
      width: MediaQuery.of(context).size.width * 0.42,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
           BoxShadow(
             color: Colors.black.withOpacity(0.05),
             blurRadius: 10, 
             offset: const Offset(0, 4)
           )
        ]
      ),
      child: Column(
        children: [
           Icon(icon, color: color, size: 30),
           const SizedBox(height: 8),
           Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, AppState appState, String dreamId) {
     showDialog(
       context: context,
       builder: (ctx) => AlertDialog(
         title: const Text("Give up on this dream?"),
         content: const Text("Are you sure you want to delete it?"),
         actions: [
           TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("No")),
           TextButton(
             onPressed: () {
                appState.deleteDream(dreamId);
                Navigator.pop(ctx); // Close dialog
                Navigator.pop(context); // Go back to list
             },
             child: const Text("Yes", style: TextStyle(color: Colors.red)),
           )
         ],
       )
     );
  }

  Future<void> _pickBackgroundImage(BuildContext context, AppState appState, Dream dream) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      // Create a copy of the dream with new background path
      final updatedDream = Dream(
        id: dream.id,
        title: dream.title,
        description: dream.description,
        startDate: dream.startDate,
        deadline: dream.deadline,
        themeColor: dream.themeColor,
        themeIcon: dream.themeIcon,
        backgroundImagePath: pickedFile.path,
        steps: dream.steps,
      );

      await appState.updateDream(updatedDream);
    }
  }

  void _reorderStep(Dream dream, AppState appState, int oldIndex, int newIndex) {
    if (newIndex < 0 || newIndex >= dream.steps.length) return;
    
    setState(() {
      final step = dream.steps.removeAt(oldIndex);
      dream.steps.insert(newIndex, step);
    });
    appState.updateDream(dream);
  }

  void _showAddStepDialog(BuildContext context, AppState appState, Dream dream) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final titleController = TextEditingController();
        final durationController = TextEditingController(text: "15");
        
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(32),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08), 
                  blurRadius: 20, 
                  offset: const Offset(0, 5)
                )
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
                  ),
                  const SizedBox(height: 16),
                  
                  Text(
                    "Add New Step", 
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)
                  ),
                  const SizedBox(height: 24),
                  
                  TextField(
                    controller: titleController,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: "What's the next action?",
                      filled: true,
                      fillColor: Theme.of(context).brightness == Brightness.dark
                          ? Theme.of(context).scaffoldBackgroundColor
                          : Colors.grey[50],
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  Row(
                    children: [
                      const Text("Duration (mins):", style: TextStyle(fontWeight: FontWeight.w500)),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 100,
                        child: TextField(
                          controller: durationController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Theme.of(context).brightness == Brightness.dark
                                ? Theme.of(context).scaffoldBackgroundColor
                                : Colors.grey[50],
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        final title = titleController.text.trim();
                        final duration = int.tryParse(durationController.text) ?? 15;
                        if (title.isNotEmpty) {
                          dream.steps.add(ChallengeStep(
                            title: title,
                            durationMinutes: duration,
                            scheduledDate: DateTime.now(),
                          ));
                          appState.updateDream(dream);
                        }
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text("Add to Journey", style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickDeadline(BuildContext context, AppState appState, Dream dream) async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
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
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 24),
            Text("Manage Deadline", style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            ListTile(
              leading: const Icon(Icons.calendar_today_rounded, color: Colors.blue),
              title: const Text("Set New Date", style: TextStyle(fontWeight: FontWeight.w500)),
              onTap: () async {
                Navigator.pop(context);
                final picked = await showDatePicker(
                  context: context,
                  initialDate: dream.deadline ?? DateTime.now().add(const Duration(days: 30)),
                  firstDate: DateTime.now().subtract(const Duration(days: 365)),
                  lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                );

                if (picked != null) {
                  final updatedDream = Dream(
                    id: dream.id,
                    title: dream.title,
                    description: dream.description,
                    startDate: dream.startDate,
                    deadline: picked,
                    themeColor: dream.themeColor,
                    themeIcon: dream.themeIcon,
                    backgroundImagePath: dream.backgroundImagePath,
                    steps: dream.steps,
                  );
                  await appState.updateDream(updatedDream);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.event_busy_rounded, color: Colors.red),
              title: const Text("Remove Deadline", style: TextStyle(color: Colors.red, fontWeight: FontWeight.w500)),
              onTap: () async {
                Navigator.pop(context);
                final updatedDream = Dream(
                  id: dream.id,
                  title: dream.title,
                  description: dream.description,
                  startDate: dream.startDate,
                  deadline: null,
                  themeColor: dream.themeColor,
                  themeIcon: dream.themeIcon,
                  backgroundImagePath: dream.backgroundImagePath,
                  steps: dream.steps,
                );
                await appState.updateDream(updatedDream);
              },
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _AnimatedCheckbox extends StatelessWidget {
  final bool isChecked;
  final bool isLoading;
  final Color activeColor;

  const _AnimatedCheckbox({
    required this.isChecked,
    this.isLoading = false,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: activeColor.withOpacity(0.5),
            width: 2,
          ),
        ),
        child: Center(
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: activeColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ).animate(onPlay: (controller) => controller.repeat())
       .rotate(duration: 1200.ms, curve: Curves.easeInOut);
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutBack,
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: isChecked ? activeColor : Colors.transparent,
        borderRadius: BorderRadius.circular(10), // Rounded corners
        border: Border.all(
          color: isChecked 
              ? activeColor 
              : (Theme.of(context).brightness == Brightness.dark ? Colors.white38 : Colors.grey.shade300),
          width: 2,
        ),
      ),
      child: isChecked
          ? const Icon(Icons.check, color: Colors.white, size: 18)
          : null,
    );
  }
}
