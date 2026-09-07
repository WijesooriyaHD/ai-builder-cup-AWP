import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/journal_entry.dart';
import '../providers/app_state.dart';
import '../services/ai_service.dart';
import '../services/content_safety_filter.dart';
import '../utils/wellnesspal_snackbar.dart';
import 'package:intl/intl.dart';

class AddJournalEntryScreen extends StatefulWidget {
  final JournalEntry? entry;
  final String? initialTitle;

  const AddJournalEntryScreen({super.key, this.entry, this.initialTitle});

  @override
  State<AddJournalEntryScreen> createState() => _AddJournalEntryScreenState();
}

class _AddJournalEntryScreenState extends State<AddJournalEntryScreen> {
  late TextEditingController _titleController;
  late TextEditingController _contentController;
  late TextEditingController _tagController;
  
  // State variables
  late JournalEntryType _type;
  late int _selectedColor;
  String? _selectedMood;
  List<String> _tags = [];
  List<TodoItem> _todos = [];
  
  // Moods available
  final List<String> _moods = ["😊", "😔", "🔥", "🧘", "😴", "💡", "🌿", "🚀"];
  
  // Colors available (soft, premium palette)
  final List<int> _colors = [
    0xFFFF8DA1, // Soft Rose
    0xFFB0A2F2, // Lavender
    0xFF8ECAE6, // Sky Blue 
    0xFF80CFBC, // Sage Green
    0xFFFFD166, // Soft Gold
    0xFFFF9F6D, // Muted Orange
    0xFF94A3B8, // Slate Blue
  ];

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.entry?.title ?? widget.initialTitle ?? '');
    _contentController = TextEditingController(text: widget.entry?.content ?? '');
    _tagController = TextEditingController();
    
    _type = widget.entry?.type ?? JournalEntryType.note;
    _selectedColor = widget.entry?.color ?? _colors[0];
    _selectedMood = widget.entry?.mood;
    _tags = List.from(widget.entry?.tags ?? []);
    
    if (widget.entry != null) {
      _todos = List.from(widget.entry!.todos.map((t) => t.copyWith()));
    } else {
      _todos = [];
      if (_type == JournalEntryType.todo) {
        _todos.add(TodoItem(text: ''));
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  void _saveEntry() {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();
    
    if (title.isEmpty) {
      WellnessPalSnackBar.show(context, message: "Please enter a title", isError: true);
      return;
    }
    
    if (_type == JournalEntryType.todo) {
      _todos.removeWhere((t) => t.text.trim().isEmpty);
      if (_todos.isEmpty) {
        WellnessPalSnackBar.show(context, message: "Add at least one item to your list", isError: true);
        return;
      }
    }

    final appState = Provider.of<AppState>(context, listen: false);
    
    if (widget.entry == null) {
      final newEntry = JournalEntry(
        title: title,
        content: content,
        type: _type,
        color: _selectedColor,
        mood: _selectedMood,
        tags: _tags,
        todos: _todos,
      );
      appState.addJournalEntry(newEntry);
      WellnessPalSnackBar.show(context, message: "Journal entry created");
      
      // Trigger async AI insight generation + Firestore write (non-blocking)
      _generateAiInsightAndSync(newEntry, appState);
    } else {
      final updatedEntry = widget.entry!.copyWith(
        title: title,
        content: content,
        type: _type,
        color: _selectedColor,
        mood: _selectedMood,
        tags: _tags,
        todos: _todos,
        updatedAt: DateTime.now(),
      );
      appState.updateJournalEntry(updatedEntry);
      WellnessPalSnackBar.show(context, message: "Journal entry updated");
      
      // Sync updated entry to Firestore
      _writeEntryToFirestore(updatedEntry);
    }
    
    Navigator.pop(context);
  }

  /// Generates an AI insight for the entry and writes the full entry to Firestore.
  ///
  /// AI insight generation has a 10-second timeout; on failure uses a fallback.
  /// Firestore write has a 3-second timeout; on failure shows error state and
  /// retains text locally for retry.
  /// All AI-generated content is passed through [ContentSafetyFilter.sanitize()].
  ///
  /// Requirements: 8.4, 8.5, 8.6
  Future<void> _generateAiInsightAndSync(
      JournalEntry entry, AppState appState) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    String? aiInsight;
    
    try {
      final aiService = AIService();
      aiInsight = await aiService.generateReflectionInsight(
        userId: user.uid,
        entryContent: entry.content,
        entryTitle: entry.title,
      );
    } catch (e) {
      debugPrint('❌ AI insight generation failed: $e');
    }

    // Use fallback if AI failed or returned null
    aiInsight ??= ContentSafetyFilter.fallbackMessage;

    // Sanitize the AI insight before storing
    aiInsight = ContentSafetyFilter.sanitize(aiInsight);

    // Update entry with AI insight
    final updatedEntry = entry.copyWith(aiInsight: aiInsight);
    appState.updateJournalEntry(updatedEntry);

    // Write to Firestore within 3 seconds; show error state on failure
    final success = await _writeEntryToFirestore(updatedEntry);
    if (!success) {
      appState.markEntryNeedsSync(updatedEntry.id);
    }
  }

  /// Writes a [JournalEntry] to Firestore under `users/{uid}/journal_entries`.
  ///
  /// Enforces a 3-second timeout. On failure the entry remains locally cached
  /// and an error state is shown so the user can retry.
  /// Returns `true` on success, `false` on failure.
  /// Requirement: 8.5
  Future<bool> _writeEntryToFirestore(JournalEntry entry) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('journal_entries')
          .doc(entry.id)
          .set(entry.toMap())
          .timeout(const Duration(seconds: 3));
      return true;
    } on TimeoutException catch (_) {
      debugPrint('⏱️ Firestore write timed out for entry ${entry.id}');
      // Entry is retained locally by AppState — user can retry from history
      return false;
    } catch (e) {
      debugPrint('❌ Firestore write failed for entry ${entry.id}: $e');
      // Entry is retained locally by AppState — user can retry from history
      return false;
    }
  }

  void _deleteEntry() {
    if (widget.entry == null) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Entry?"),
        content: const Text("This action cannot be undone."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              final appState = Provider.of<AppState>(context, listen: false);
              appState.deleteJournalEntry(widget.entry!.id);
              Navigator.pop(context); 
              Navigator.pop(context);
              WellnessPalSnackBar.show(context, message: "Entry deleted");
            },
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Color(_selectedColor);
    
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFFAFAFA),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Container(
          margin: const EdgeInsets.only(left: 12),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: Icon(Icons.close_rounded, color: isDark ? Colors.white70 : Colors.black54),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        title: Text(
          widget.entry == null ? "New Entry" : "Edit Entry",
           style: TextStyle(
             color: isDark ? Colors.white : Colors.black87,
             fontWeight: FontWeight.w600,
           ),
        ),
        actions: [
          if (widget.entry != null)
            Container(
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 22),
                onPressed: _deleteEntry,
              ),
            ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              primaryColor.withOpacity(isDark ? 0.05 : 0.08),
              isDark ? const Color(0xFF121212) : const Color(0xFFFAFAFA),
            ],
            stops: const [0.0, 0.4],
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 120, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Type Selector Chips
                    Row(
                      children: [
                        _buildTypeChip(JournalEntryType.note, "Note", Icons.edit_note_rounded),
                        const SizedBox(width: 10),
                        _buildTypeChip(JournalEntryType.todo, "Checklist", Icons.checklist_rounded),
                      ],
                    ),
                    const SizedBox(height: 32),
  
                    // Title Input
                    TextField(
                      controller: _titleController,
                      autofocus: widget.entry == null,
                      style: TextStyle(
                        fontSize: 28, 
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      decoration: InputDecoration(
                        hintText: "Give it a title...",
                        border: InputBorder.none,
                        hintStyle: TextStyle(color: isDark ? Colors.white24 : Colors.grey.shade400),
                      ),
                    ),
                    Row(
                      children: [
                        Icon(Icons.calendar_today_rounded, size: 12, color: isDark ? Colors.white38 : Colors.grey),
                        const SizedBox(width: 6),
                        Text(
                          DateFormat('MMMM d, yyyy • h:mm a').format(widget.entry?.createdAt ?? DateTime.now()),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: isDark ? Colors.white38 : Colors.grey,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 48),
  
                    // Mood Selector
                    _buildSectionHeader("HOW ARE YOU FEELING?", isDark),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 56,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _moods.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 16),
                        itemBuilder: (context, index) {
                          final mood = _moods[index];
                          final isSelected = _selectedMood == mood;
                          return GestureDetector(
                            onTap: () => setState(() => _selectedMood = isSelected ? null : mood),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: isSelected 
                                    ? primaryColor.withOpacity(isDark ? 0.3 : 0.15) 
                                    : (isDark ? Colors.white.withOpacity(0.05) : Colors.white),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: isSelected 
                                      ? primaryColor.withOpacity(0.5) 
                                      : (isDark ? Colors.white10 : Colors.black.withOpacity(0.05)),
                                  width: 1.5,
                                ),
                                boxShadow: isSelected ? [
                                  BoxShadow(
                                    color: primaryColor.withOpacity(0.2),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  )
                                ] : null,
                              ),
                              child: Center(
                                child: AnimatedScale(
                                  scale: isSelected ? 1.2 : 1.0,
                                  duration: const Duration(milliseconds: 200),
                                  child: Text(mood, style: const TextStyle(fontSize: 26))
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 48),
  
                    // Color Selector
                    _buildSectionHeader("PICK A VIBE", isDark),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 44,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _colors.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 14),
                        itemBuilder: (context, index) {
                          final colorCode = _colors[index];
                          final color = Color(colorCode);
                          final isSelected = _selectedColor == colorCode;
                          return GestureDetector(
                            onTap: () => setState(() => _selectedColor = colorCode),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSelected ? (isDark ? Colors.white : Colors.black87) : Colors.transparent,
                                  width: 2.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: color.withOpacity(0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  )
                                ],
                              ),
                              child: isSelected 
                                   ? Icon(Icons.check_rounded, color: Colors.white.withOpacity(0.9), size: 20) 
                                   : null,
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 48),
  
                    // Content Area
                    if (_type == JournalEntryType.note)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionHeader("THOUGHTS", isDark),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _contentController,
                            maxLines: null,
                            textCapitalization: TextCapitalization.sentences,
                            style: TextStyle(
                              fontSize: 18, 
                              height: 1.6,
                              color: isDark ? Colors.white.withOpacity(0.85) : Colors.black87,
                            ),
                            decoration: InputDecoration(
                              hintText: "Start writing from your heart...",
                              border: InputBorder.none,
                              hintStyle: TextStyle(color: isDark ? Colors.white24 : Colors.grey.shade400),
                            ),
                          ),
                        ],
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionHeader("CHECKLIST", isDark),
                          const SizedBox(height: 12),
                          ..._todos.asMap().entries.map((entry) {
                            final index = entry.key;
                            final todo = entry.value;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: Checkbox(
                                      value: todo.isCompleted,
                                      onChanged: (val) => setState(() => _todos[index] = todo.copyWith(isCompleted: val)),
                                      activeColor: primaryColor,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                      side: BorderSide(color: isDark ? Colors.white30 : Colors.grey.shade400, width: 2),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextField(
                                      controller: TextEditingController(text: todo.text)
                                        ..selection = TextSelection.fromPosition(TextPosition(offset: todo.text.length)),
                                      onChanged: (val) => _todos[index] = todo.copyWith(text: val),
                                      decoration: InputDecoration(
                                        hintText: "Add a task...",
                                        border: InputBorder.none,
                                        hintStyle: TextStyle(color: isDark ? Colors.white24 : Colors.grey.shade400),
                                      ),
                                      style: TextStyle(
                                        decoration: todo.isCompleted ? TextDecoration.lineThrough : null,
                                        color: todo.isCompleted 
                                            ? (isDark ? Colors.white38 : Colors.grey) 
                                            : (isDark ? Colors.white : Colors.black87),
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.close_rounded, size: 18, color: isDark ? Colors.white24 : Colors.grey),
                                    onPressed: () => setState(() => _todos.removeAt(index)),
                                  ),
                                ],
                              ),
                            );
                          }),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: () => setState(() => _todos.add(TodoItem(text: ''))),
                            icon: Icon(Icons.add_circle_outline_rounded, size: 20, color: primaryColor),
                            label: Text("Add item", style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold)),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 0),
                            ),
                          ),
                        ],
                      ),
                    
                    const SizedBox(height: 48),
                    
                    // Tags Section
                    _buildSectionHeader("TAGS", isDark),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        ..._tags.map((tag) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: primaryColor.withOpacity(isDark ? 0.2 : 0.08),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                "#$tag", 
                                style: TextStyle(
                                  color: primaryColor, 
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                )
                              ),
                              const SizedBox(width: 6),
                              GestureDetector(
                                onTap: () => setState(() => _tags.remove(tag)),
                                child: Icon(Icons.close_rounded, size: 14, color: primaryColor),
                              ),
                            ],
                          ),
                        )),
                        GestureDetector(
                          onTap: _showAddTagDialog,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.add_rounded, size: 16, color: isDark ? Colors.white54 : Colors.black45),
                                const SizedBox(width: 4),
                                Text(
                                  "Add Tag", 
                                  style: TextStyle(
                                    color: isDark ? Colors.white54 : Colors.black54,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  )
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 60),
                  ],
                ),
              ),
            ),
            
            // Fixed Bottom Save Button
            Container(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF121212) : const Color(0xFFFAFAFA),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.3 : 0.03),
                    blurRadius: 15,
                    offset: const Offset(0, -5),
                  )
                ],
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                    elevation: 5,
                    shadowColor: primaryColor.withOpacity(0.4),
                  ),
                  onPressed: _saveEntry,
                  child: const Text(
                    "Keep This Memory", 
                    style: TextStyle(
                      fontSize: 17, 
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    )
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, bool isDark) {
    return Text(
      title, 
      style: TextStyle(
        color: isDark ? Colors.white30 : Colors.grey.shade400, 
        fontWeight: FontWeight.w800,
        fontSize: 11,
        letterSpacing: 1.2,
      )
    );
  }

  Widget _buildTypeChip(JournalEntryType type, String label, IconData icon) {
    final isSelected = _type == type;
    final primaryColor = Color(_selectedColor);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return GestureDetector(
      onTap: () {
        setState(() {
          _type = type;
          if (_type == JournalEntryType.todo && _todos.isEmpty) {
            _todos.add(TodoItem(text: ''));
          }
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected 
              ? primaryColor 
              : (isDark ? Colors.white.withOpacity(0.05) : Colors.white),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected 
                ? primaryColor 
                : (isDark ? Colors.white10 : Colors.black.withOpacity(0.05)),
          ),
          boxShadow: isSelected ? [
            BoxShadow(
              color: primaryColor.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 3),
            )
          ] : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon, 
              size: 18, 
              color: isSelected ? Colors.white : (isDark ? Colors.white54 : Colors.grey.shade600)
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.grey.shade700),
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddTagDialog() {
    _tagController.clear();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text("Add Tag"),
        content: TextField(
          controller: _tagController,
          autofocus: true,
          style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color),
          decoration: InputDecoration(
            hintText: "e.g., Ideas, Work, Personal",
            hintStyle: const TextStyle(color: Colors.grey),
            prefixText: "#",
            prefixStyle: TextStyle(color: Color(_selectedColor), fontWeight: FontWeight.bold),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey.withOpacity(0.2))),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(_selectedColor))),
          ),
          onSubmitted: (val) {
            if (val.isNotEmpty) {
              setState(() => _tags.add(val.trim()));
              Navigator.pop(context);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context), 
            child: Text("Cancel", style: TextStyle(color: Colors.grey.shade600))
          ),
          TextButton(
            onPressed: () {
              if (_tagController.text.isNotEmpty) {
                setState(() => _tags.add(_tagController.text.trim()));
                Navigator.pop(context);
              }
            },
            child: Text("Add", style: TextStyle(color: Color(_selectedColor), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
