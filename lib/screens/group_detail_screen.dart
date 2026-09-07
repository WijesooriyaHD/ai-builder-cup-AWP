import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../providers/app_state.dart';
import '../models/journal_entry.dart';
import '../models/journal_group.dart';
import 'add_journal_entry_screen.dart';
import 'achievement_completion_page.dart';
import '../utils/icon_resolver.dart';

class GroupDetailScreen extends StatelessWidget {
  final JournalGroup group;

  const GroupDetailScreen({super.key, required this.group});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              backgroundColor: Color(group.color),
              radius: 12,
              child: Icon(
                resolveIconData(group.iconCodePoint),
                color: Colors.white,
                size: 16,
              ),
            ),
            const SizedBox(width: 12),
            Text(group.name),
          ],
        ),
      ),
      body: Consumer<AppState>(
        builder: (context, appState, child) {
          final entriesInGroup = appState.journalEntries
              .where((e) => e.groupId == group.id)
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

          if (entriesInGroup.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.folder_open_rounded,
                    size: 80,
                    color: Color(group.color).withOpacity(0.3),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'No entries in this group',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Long-press any entry to assign it here',
                    style: TextStyle(color: Colors.grey.shade600),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: MasonryGridView.count(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              itemCount: entriesInGroup.length,
              itemBuilder: (context, index) {
                final entry = entriesInGroup[index];
                return _buildJournalCard(context, entry, appState);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildJournalCard(BuildContext context, JournalEntry entry, AppState appState) {
    final cardColor = Color(entry.color);
    
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AddJournalEntryScreen(entry: entry),
          ),
        );
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
            if (entry.title.isNotEmpty) ...[
              Text(
                entry.title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
            ],
            
            if (entry.type == JournalEntryType.note) ...[
              Text(
                entry.content,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.black87,
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
                          color: todo.isCompleted ? cardColor : Colors.grey.shade600,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            todo.text,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.black87,
                              decoration: todo.isCompleted
                                  ? TextDecoration.lineThrough
                                  : null,
                              decorationColor: cardColor,
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
                      color: Colors.grey.shade600,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
