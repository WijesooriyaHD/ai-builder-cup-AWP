import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../providers/app_state.dart';
import '../models/journal_entry.dart';
import 'add_journal_entry_screen.dart';
import '../utils/wellnesspal_snackbar.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'journal_ai_discussion_screen.dart';
import 'achievement_completion_page.dart';

class JournalScreen extends StatefulWidget {
  const JournalScreen({super.key});

  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = '';
  String? _selectedMoodFilter;
  late TabController _filterTabController;
  bool _isSearchVisible = false;

  final List<String> _moods = ["😊", "😔", "🔥", "🧘", "😴", "💡", "🌿", "🚀"];

  @override
  void initState() {
    super.initState();
    _filterTabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _filterTabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(
            _isSearchVisible ? Icons.search_off_rounded : Icons.search_rounded,
            color: Theme.of(context).iconTheme.color,
          ),
          onPressed: () {
            setState(() {
              _isSearchVisible = !_isSearchVisible;
              if (!_isSearchVisible) {
                _searchController.clear();
                _searchQuery = '';
              }
            });
          },
        ),
        title: null, // Title removed to make space for tabs
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: SizedBox(
              width: MediaQuery.of(context).size.width * 0.75, // Give tabs 75% of width
              child: _buildFilterTabs(context, MediaQuery.of(context).size.width * 0.75),
            ),
          ),
        ],
        backgroundColor: Colors.transparent,
        elevation: 0,
        bottom: _isSearchVisible ? PreferredSize(
          preferredSize: const Size.fromHeight(132),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value.toLowerCase();
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'Search notes and todos...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded),
                            onPressed: () {
                              setState(() {
                                _searchController.clear();
                                _searchQuery = '';
                              });
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: Theme.of(context).brightness == Brightness.dark 
                        ? Theme.of(context).cardColor 
                        : Colors.grey.shade100,
                    hintStyle: TextStyle(color: Theme.of(context).hintColor),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ),
              _buildMoodFilterBar(),
              const SizedBox(height: 16),
            ],
          ),
        ) : null,
      ),
      body: Column(
        children: [
          // Filter tabs moved to AppBar
          
          // Journal entries grid
          Expanded(
            child: Consumer<AppState>(
              builder: (context, appState, child) {
                // Sort entries: pinned first, then by latest
                final sortedEntries = List<JournalEntry>.from(appState.journalEntries)
                  ..sort((a, b) {
                    // Pinned entries come first
                    if (a.isPinned && !b.isPinned) return -1;
                    if (!a.isPinned && b.isPinned) return 1;
                    // Then sort by date
                    return b.createdAt.compareTo(a.createdAt);
                  });

                // Filter by type based on selected tab
                List<JournalEntry> typeFilteredEntries;
                if (_filterTabController.index == 1) {
                  // Saved view - show everything marked as saved
                  typeFilteredEntries = sortedEntries.where((e) => e.isSaved).toList();
                } else {
                  // Journal view - hide entries that are explicitly saved insights from discussions
                  typeFilteredEntries = sortedEntries.where((e) => !e.tags.contains("AI Discussion")).toList();
                }

                // Filter entries based on search query and mood
                var filteredEntries = typeFilteredEntries.where((entry) {
                  // Search query filter
                  bool matchesSearch = true;
                  if (_searchQuery.isNotEmpty) {
                    final titleMatch = entry.title.toLowerCase().contains(_searchQuery);
                    final contentMatch = entry.content.toLowerCase().contains(_searchQuery);
                    final todoMatch = entry.todos.any(
                      (todo) => todo.text.toLowerCase().contains(_searchQuery),
                    );
                    matchesSearch = titleMatch || contentMatch || todoMatch;
                  }

                  // Mood filter
                  bool matchesMood = true;
                  if (_selectedMoodFilter != null) {
                    matchesMood = entry.mood == _selectedMoodFilter;
                  }

                  return matchesSearch && matchesMood;
                }).toList();

                if (filteredEntries.isEmpty) {
                  if (_filterTabController.index == 1) {
                     return _buildEmptySavedState(context);
                  }
                  return _searchQuery.isNotEmpty
                      ? _buildNoResultsState(context)
                      : _buildEmptyState(context);
                }

                // (Groups View block removed)


                // Show grouped view when Groups tab is selected
                if (_filterTabController.index == 1) {
                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: filteredEntries.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      return _buildSavedJournalCard(context, filteredEntries[index], appState);
                    },
                  );
                }

                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: MasonryGridView.count(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    itemCount: filteredEntries.length,
                    itemBuilder: (context, index) {
                      final entry = filteredEntries[index];
                      return _buildJournalCard(context, entry, appState);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: 'add_fab',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AddJournalEntryScreen()),
              );
            },
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: const Icon(Icons.add),
          ),
          const SizedBox(height: 110), // Shifted up
        ],
      ),
    );
  }


  Widget _buildSavedJournalCard(BuildContext context, JournalEntry entry, AppState appState) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return GestureDetector(
      onTap: () => _showViewEntryPopup(context, entry, appState),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(
             color: Colors.amber.withOpacity(0.3),
             width: 1,
          )
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, size: 16, color: Colors.purple.shade300),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    entry.title.isNotEmpty ? entry.title : "Untitled Insight",
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (entry.mood != null) ...[
                  Text(entry.mood!, style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 8),
                ],
                Icon(Icons.bookmark, size: 18, color: Colors.amber),
              ],
            ),
            const SizedBox(height: 12),
            if (entry.aiInsight != null && entry.aiInsight!.isNotEmpty)
              Text(
                entry.aiInsight!, // Show raw text preview, markdown might be too heavy for list
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.black87,
                  fontSize: 14,
                  height: 1.5,
                ),
              )
            else
              Text(
                entry.content,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isDark ? Colors.white54 : Colors.grey.shade700,
                  fontStyle: FontStyle.italic,
                  fontSize: 14,
                ),
              ),
              
             if (entry.tags.isNotEmpty) ...[
               const SizedBox(height: 8),
               Wrap(
                 spacing: 4,
                 runSpacing: 4,
                 children: entry.tags.take(2).map((tag) => Container(
                   padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                   decoration: BoxDecoration(
                     color: Colors.grey.withOpacity(0.1),
                     borderRadius: BorderRadius.circular(4),
                   ),
                   child: Text(
                     "#$tag",
                     style: const TextStyle(fontSize: 10, color: Colors.grey),
                   ),
                 )).toList(),
               ),
             ],
             const SizedBox(height: 12),
             Row(
               mainAxisAlignment: MainAxisAlignment.end,
               children: [
                 Text(
                   "${entry.updatedAt.month}/${entry.updatedAt.day}",
                   style: TextStyle(fontSize: 12, color: Colors.grey),
                 ),
               ],
             )
          ],
        ),
      ),
    );
  }

  Widget _buildJournalCard(BuildContext context, JournalEntry entry, AppState appState) {
    final cardColor = Color(entry.color);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Adapt ink color context: darker for light mode, lighter/original for dark mode
    final inkColor = isDark 
        ? Colors.white.withOpacity(0.9) // White text on dark cards
        : Color.lerp(cardColor, Colors.black, 0.5) ?? cardColor;
    
    return GestureDetector(
      onTap: () => _showViewEntryPopup(context, entry, appState),
      onLongPress: () {
        _showEntryOptionsDialog(context, entry, appState);
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardColor.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cardColor.withOpacity(0.3), width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Pin indicator
            if (entry.isPinned) ...[
              Row(
                children: [
                  Icon(
                    Icons.push_pin,
                    size: 16,
                    color: inkColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Pinned',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: inkColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            // Group badge removed

            if (entry.title.isNotEmpty) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Expanded(
                     child: Text(
                        entry.title,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                   ),
                   if (entry.mood != null) ...[
                     Text(entry.mood!, style: const TextStyle(fontSize: 18)),
                     const SizedBox(width: 8),
                   ],
                ],
              ),
              const SizedBox(height: 8),
            ],
            
            if (entry.type == JournalEntryType.note) ...[
              Text(
                entry.content,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                maxLines: 8,
                overflow: TextOverflow.ellipsis,
              ),
            ] else ...[
              // Todo list with inline checkboxes
              ...entry.todos.take(5).map((todo) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: GestureDetector(
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
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          todo.isCompleted
                              ? Icons.check_box_rounded
                              : Icons.check_box_outline_blank_rounded,
                          size: 20,
                          color: todo.isCompleted 
                              ? inkColor 
                              : (isDark ? Colors.white38 : Colors.grey.shade600),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            todo.text,
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark ? Colors.white70 : Colors.black87,
                              decoration: todo.isCompleted
                                  ? TextDecoration.lineThrough
                                  : null,
                              decorationColor: inkColor,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
              if (entry.todos.length > 5)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text(
                    '+${entry.todos.length - 5} more',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white38 : Colors.grey.shade600,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
            ],
            
            if (entry.tags.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: entry.tags.take(3).map((tag) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: cardColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    "#$tag",
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: inkColor.withOpacity(0.8),
                    ),
                  ),
                )).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMoodFilterBar() {
    return SizedBox(
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _moods.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            // "All" option
            final isSelected = _selectedMoodFilter == null;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: ChoiceChip(
                label: const Text("All"),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    _selectedMoodFilter = null;
                  });
                },
                selectedColor: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                backgroundColor: Colors.transparent,
                labelStyle: TextStyle(
                  color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                side: BorderSide(
                  color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey.withOpacity(0.3),
                ),
                showCheckmark: false,
              ),
            );
          }

          final mood = _moods[index - 1];
          final isSelected = _selectedMoodFilter == mood;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: ChoiceChip(
              label: Text(mood, style: const TextStyle(fontSize: 18)),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  _selectedMoodFilter = selected ? mood : null;
                });
              },
              selectedColor: Theme.of(context).colorScheme.primary.withOpacity(0.2),
              backgroundColor: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              side: BorderSide(
                color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey.withOpacity(0.3),
              ),
              showCheckmark: false,
            ),
          );
        },
      ),
    );
  }

  Widget _buildFilterTabs(BuildContext context, double width) {
    // Total width is divided equally among tabs
    final double segmentWidth = width / 2;
    // Pill starts with 4px margin and ends with 4px margin inside the segment
    final double pillWidth = segmentWidth - 8;
    
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark 
            ? Colors.black.withOpacity(0.2) 
            : Colors.white.withOpacity(0.4),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Stack(
        children: [
          // Animated Indicator
          AnimatedBuilder(
            animation: _filterTabController.animation!,
            builder: (context, child) {
              // Calculate offset: index * segmentWidth + 4px padding
              final double offset = _filterTabController.animation!.value * segmentWidth + 4;
              
              return Positioned(
                left: offset,
                top: 4,
                bottom: 4,
                width: pillWidth,
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark 
                        ? Theme.of(context).scaffoldBackgroundColor // Use dark background for tab indicator
                        : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          // Labels
          Row(
            children: [
              _buildFilterTab('Journal', 0, Icons.edit_note_rounded),
              _buildFilterTab('Saved', 1, Icons.bookmark_rounded),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterTab(String label, int index, IconData icon) {
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _filterTabController.animateTo(index)),
        child: Container(
          color: Colors.transparent,
          alignment: Alignment.center,
          child: AnimatedBuilder(
            animation: _filterTabController.animation!,
            builder: (context, child) {
              final isSelected = (_filterTabController.animation!.value - index).abs() < 0.5;
              final color = isSelected 
                      ? Theme.of(context).primaryColor 
                      : (Theme.of(context).brightness == Brightness.dark ? Colors.white54 : Colors.grey);
              
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon, 
                    size: 18, 
                    color: color,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: color,
                      fontSize: 14,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildEmptySavedState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.bookmark_border_rounded,
            size: 80,
            color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
          ),
          const SizedBox(height: 24),
          Text(
            'No Saved Insights',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Generate AI insights on your notes\nand save them here!',
            style: TextStyle(color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.book_outlined,
            size: 80,
            color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
          ),
          const SizedBox(height: 24),
          Text(
            'Start Journaling',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Tap + to create your first note or todo list',
            style: TextStyle(color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildNoResultsState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 80,
            color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
          ),
          const SizedBox(height: 24),
          Text(
            'No results found',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Try a different search term',
            style: TextStyle(color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _showViewEntryPopup(BuildContext context, JournalEntry entry, AppState appState) {
    final isInsight = entry.tags.contains("AI Discussion");
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        builder: (context, scrollController) => Consumer<AppState>(
          builder: (context, currentAppState, _) {
            // Re-fetch entry from state to ensure we have the latest (e.g. after todo toggle)
            final currentEntry = currentAppState.journalEntries.firstWhere(
              (e) => e.id == entry.id, 
              orElse: () => entry
            );
            
            return Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: BorderRadius.circular(32),
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      if (currentEntry.mood != null) ...[
                        Text(currentEntry.mood!, style: const TextStyle(fontSize: 24)),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Text(
                          isInsight ? "AI Insight" : (currentEntry.title.isNotEmpty ? currentEntry.title : "Journal Entry"),
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (currentEntry.isSaved)
                        IconButton(
                          icon: const Icon(Icons.bookmark_remove_rounded, color: Colors.blue),
                          onPressed: () {
                             currentAppState.toggleSavedEntry(currentEntry.id);
                             Navigator.pop(context);
                             WellnessPalSnackBar.show(context, message: "Removed from Saved");
                          },
                          tooltip: "Unsave",
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (isInsight && currentEntry.sourceEntryId != null) ...[
                    GestureDetector(
                      onTap: () {
                        final sourceEntry = currentAppState.journalEntries.firstWhere((e) => e.id == currentEntry.sourceEntryId, orElse: () => currentEntry);
                        if (sourceEntry != currentEntry) {
                           Navigator.pop(context);
                           _showViewEntryPopup(context, sourceEntry, currentAppState);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.blue.withOpacity(0.2)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.link_rounded, size: 14, color: Colors.blue),
                            const SizedBox(width: 4),
                            Text(
                              "From: ${currentAppState.journalEntries.firstWhere((e) => e.id == currentEntry.sourceEntryId, orElse: () => currentEntry).title.isNotEmpty ? currentAppState.journalEntries.firstWhere((e) => e.id == currentEntry.sourceEntryId, orElse: () => currentEntry).title : 'Original Note'}",
                              style: const TextStyle(fontSize: 12, color: Colors.blue, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (currentEntry.tags.isNotEmpty && !isInsight)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: currentEntry.tags.map((tag) => Chip(
                        label: Text(tag, style: const TextStyle(fontSize: 12)),
                        backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                        side: BorderSide.none,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      )).toList(),
                    ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      child: currentEntry.type == JournalEntryType.note
                          ? Text(
                              currentEntry.content,
                              style: const TextStyle(fontSize: 16, height: 1.6),
                            )
                          : Column(
                              children: currentEntry.todos.map((todo) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: InkWell(
                                  onTap: () {
                                    currentAppState.toggleTodoItem(currentEntry.id, todo.id);
                                  },
                                  borderRadius: BorderRadius.circular(12),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                                    child: Row(
                                      children: [
                                        AnimatedContainer(
                                          duration: const Duration(milliseconds: 200),
                                          width: 24,
                                          height: 24,
                                          decoration: BoxDecoration(
                                            color: todo.isCompleted ? Colors.green : Colors.transparent,
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(
                                              color: todo.isCompleted 
                                                  ? Colors.green 
                                                  : Colors.grey.withOpacity(0.4),
                                              width: 2,
                                            ),
                                          ),
                                          child: todo.isCompleted 
                                              ? const Icon(Icons.check, size: 16, color: Colors.white)
                                              : null,
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: Text(
                                            todo.text,
                                            style: TextStyle(
                                              fontSize: 16,
                                              decoration: todo.isCompleted ? TextDecoration.lineThrough : null,
                                              color: todo.isCompleted ? Colors.grey : null,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              )).toList(),
                            ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (!isInsight)
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => AddJournalEntryScreen(entry: currentEntry),
                                ),
                              );
                            },
                            icon: const Icon(Icons.edit_note_rounded, color: Colors.amber),
                            label: const Text("Edit Entry"),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              backgroundColor: Colors.amber.withOpacity(0.1),
                              foregroundColor: Colors.amber.shade900,
                              elevation: 0,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              _openAiDiscussion(context, currentEntry);
                            },
                            icon: const Icon(Icons.auto_awesome_rounded, color: Colors.purple),
                            label: const Text("Discuss"),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              backgroundColor: Colors.purple.withOpacity(0.1),
                              foregroundColor: Colors.purple,
                              elevation: 0,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            );
          }
        ),
      ),
    );
  }

  void _openAiDiscussion(BuildContext context, JournalEntry entry) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => JournalAiDiscussionScreen(entry: entry),
      ),
    );
  }

  void _showEntryOptionsDialog(BuildContext context, JournalEntry entry, AppState appState) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor, // Use theme background
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
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            _buildOptionTile(
              context,
              icon: entry.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
              title: entry.isPinned ? 'Unpin' : 'Pin to Top',
              color: Colors.blue,
              onTap: () async {
                final success = await appState.togglePinEntry(entry.id);
                if (!success && !entry.isPinned) {
                  Navigator.pop(context);
                  WellnessPalSnackBar.show(
                    context,
                    message: 'Maximum 3 entries can be pinned',
                    icon: Icons.error_outline_rounded,
                    isError: true, // Logic limit
                  );
                } else {
                  Navigator.pop(context);
                }
              },
            ),
            const Divider(height: 1, indent: 24, endIndent: 24),
            _buildOptionTile(
              context,
              icon: appState.pinnedJournalToHomeIds.contains(entry.id) 
                  ? Icons.home_rounded 
                  : Icons.home_outlined,
              title: appState.pinnedJournalToHomeIds.contains(entry.id)
                  ? 'Remove from Home'
                  : 'Add to Home',
              color: Colors.teal,
              onTap: () {
                appState.toggleJournalPinToHome(entry.id);
                Navigator.pop(context);
                WellnessPalSnackBar.show(
                  context, 
                  message: appState.pinnedJournalToHomeIds.contains(entry.id) 
                      ? "Added to Home Screen"
                      : "Removed from Home",
                  icon: Icons.home_rounded,
                );
              },
            ),
            const Divider(height: 1, indent: 24, endIndent: 24),
            _buildOptionTile(
              context,
              icon: entry.isSaved ? Icons.bookmark_remove_rounded : Icons.bookmark_add_rounded,
              title: entry.isSaved ? 'Remove from Saved' : 'Save to Favorites',
              color: Colors.amber,
              onTap: () async {
                 await appState.toggleSavedEntry(entry.id);
                 Navigator.pop(context);
                 WellnessPalSnackBar.show(context, message: entry.isSaved ? "Removed from Saved" : "Saved to Favorites");
              },
            ),
            const Divider(height: 1, indent: 24, endIndent: 24),
            _buildOptionTile(
              context,
              icon: Icons.delete_outline_rounded,
              title: 'Delete Entry',
              color: Colors.red,
              onTap: () {
                Navigator.pop(context);
                _showDeleteDialog(context, entry.id, appState);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _showAiInsight(BuildContext context, String text, String entryId) async {
    final appState = Provider.of<AppState>(context, listen: false);
    
    // Check if this entry already has an insight saved
    final existingEntry = appState.journalEntries.firstWhere((e) => e.id == entryId, orElse: () => JournalEntry(title: '', content: '', type: JournalEntryType.note, color: 0));
    String? currentContent = existingEntry.aiInsight;
    bool isSaved = existingEntry.isSaved;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder( // Use StatefulBuilder for local toggle updates
        builder: (context, setSheetState) {
          return DraggableScrollableSheet(
            initialChildSize: 0.5,
            minChildSize: 0.3,
            maxChildSize: 0.9,
            builder: (context, scrollController) {
              return Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                clipBehavior: Clip.hardEdge,
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: [
                     BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, -5))
                  ]
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "AI Insights",
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          
                          // Save Toggle (Icon Button)
                          GestureDetector(
                            onTap: () {
                               setSheetState(() {
                                  isSaved = !isSaved;
                               });
                               appState.toggleSavedEntry(entryId, save: isSaved, insight: currentContent);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isSaved ? Colors.amber.withOpacity(0.1) : Colors.transparent,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                isSaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                                color: isSaved ? Colors.amber : Colors.grey,
                                size: 28,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Expanded(
                      child: currentContent != null && currentContent!.isNotEmpty
                        ? SingleChildScrollView( // Show cached insight if available
                            controller: scrollController,
                            padding: const EdgeInsets.all(24),
                            child: MarkdownBody(
                              data: currentContent!,
                              styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)),
                            ),
                          )
                        : FutureBuilder<HttpsCallableResult>(
                        future: () async {
                          debugPrint("DEBUG: Sending to AI Journal Insight: $text");
                          final callable = FirebaseFunctions.instance.httpsCallable('journalInsight');
                          return callable.call({'text': text});
                        }(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const CircularProgressIndicator(),
                                  const SizedBox(height: 16),
                                  Text(
                                    "Analyzing your thoughts...",
                                    style: TextStyle(color: Colors.grey.shade600),
                                  ),
                                ],
                              ),
                            );
                          }
                          
                          if (snapshot.hasError) {
                            return Center(child: Text("Error: ${snapshot.error}"));
                          }
                          
                          final response = snapshot.data;
                          final data = response?.data;
                          String content = "";
                          if (data is Map) {
                             content = data['reply'] ?? data['insight'] ?? data['message'] ?? response?.data.toString();
                          } else {
                             content = response?.data.toString() ?? "No insights available.";
                          }
                          
                          // Cache this loaded content locally so if they toggle save, it saves THIS content
                          if (content.isNotEmpty && content != currentContent) {
                             currentContent = content;
                             // If it was already marked as saved (e.g. user toggled while loading), update the text now
                             if (isSaved) {
                               WidgetsBinding.instance.addPostFrameCallback((_) {
                                 appState.toggleSavedEntry(entryId, save: true, insight: content);
                               });
                             }
                          }

                          return SingleChildScrollView(
                            controller: scrollController,
                            padding: const EdgeInsets.all(24),
                            child: MarkdownBody(
                              data: content,
                              styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                                p: const TextStyle(fontSize: 16, height: 1.5),
                                h1: const TextStyle(fontWeight: FontWeight.bold, fontSize: 24),
                                h2: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                                h3: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                                blockquote: TextStyle(color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                                blockquoteDecoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border(left: BorderSide(color: Colors.purple.withOpacity(0.5), width: 4)),
                                ),
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
          );
        }
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
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
    );
  }



  void _showDeleteDialog(BuildContext context, String entryId, AppState appState) {
    showModalBottomSheet(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Delete Entry?'),
        content: const Text('Are you sure you want to delete this journal entry? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              appState.deleteJournalEntry(entryId);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
