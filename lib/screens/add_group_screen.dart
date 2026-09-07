import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/journal_group.dart';
import '../utils/wellnesspal_snackbar.dart';

class AddGroupScreen extends StatefulWidget {
  final JournalGroup? group;

  const AddGroupScreen({super.key, this.group});

  @override
  State<AddGroupScreen> createState() => _AddGroupScreenState();
}

class _AddGroupScreenState extends State<AddGroupScreen> {
  final _nameController = TextEditingController();
  late int _selectedColor;
  late int _selectedIconCodePoint;

  final List<Color> _colorPalette = [
    const Color(0xFFFF6B6B), // Red
    const Color(0xFFFF9F43), // Orange
    const Color(0xFFFECA57), // Yellow
    const Color(0xFF48DBFB), // Blue
    const Color(0xFF1DD1A1), // Green
    const Color(0xFF9B59B6), // Purple
    const Color(0xFFE056FD), // Pink
    const Color(0xFF778CA3), // Gray
  ];

  final List<IconData> _iconOptions = [
    Icons.folder_rounded,
    Icons.work_rounded,
    Icons.home_rounded,
    Icons.school_rounded,
    Icons.favorite_rounded,
    Icons.lightbulb_rounded,
    Icons.shopping_cart_rounded,
    Icons.fitness_center_rounded,
    Icons.restaurant_rounded,
    Icons.flight_rounded,
    Icons.music_note_rounded,
    Icons.sports_soccer_rounded,
  ];

  @override
  void initState() {
    super.initState();
    if (widget.group != null) {
      _nameController.text = widget.group!.name;
      _selectedColor = widget.group!.color;
      _selectedIconCodePoint = widget.group!.iconCodePoint;
    } else {
      _selectedColor = _colorPalette[0].toARGB32();
      _selectedIconCodePoint = _iconOptions[0].codePoint;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.group == null ? 'New Group' : 'Edit Group'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check_rounded),
            onPressed: _saveGroup,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Group Name',
                hintText: 'e.g., Work, Personal, Ideas',
                filled: true,
                fillColor: Theme.of(context).brightness == Brightness.dark 
                    ? Theme.of(context).cardColor 
                    : Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 32),
            Text(
              'Icon',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: _iconOptions.map((icon) {
                final isSelected = _selectedIconCodePoint == icon.codePoint;
                return GestureDetector(
                  onTap: () => setState(() => _selectedIconCodePoint = icon.codePoint),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
                          : (Theme.of(context).brightness == Brightness.dark 
                              ? Theme.of(context).cardColor 
                              : Colors.grey.shade100),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : (Theme.of(context).brightness == Brightness.dark 
                                ? Colors.white10 
                                : Colors.grey.shade300),
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      icon,
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : (Theme.of(context).brightness == Brightness.dark 
                              ? Colors.white54 
                              : Colors.grey.shade600),
                      size: 28,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 32),
            Text(
              'Color',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: _colorPalette.map((color) {
                final isSelected = _selectedColor == color.toARGB32();
                return GestureDetector(
                  onTap: () => setState(() => _selectedColor = color.toARGB32()),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? Colors.black : Colors.transparent,
                        width: 3,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: color.withOpacity(0.4),
                          blurRadius: isSelected ? 12 : 6,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, color: Colors.white, size: 28)
                        : null,
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  void _saveGroup() {
    final name = _nameController.text.trim();

    if (name.isEmpty) {
      WellnessPalSnackBar.show(
        context,
        message: 'Please enter a group name',
        icon: Icons.edit_rounded,
        isError: true, // Validation error
      );
      return;
    }

    final group = widget.group?.copyWith(
          name: name,
          color: _selectedColor,
          iconCodePoint: _selectedIconCodePoint,
        ) ??
        JournalGroup(
          name: name,
          color: _selectedColor,
          iconCodePoint: _selectedIconCodePoint,
        );

    final appState = Provider.of<AppState>(context, listen: false);
    if (widget.group == null) {
      appState.addJournalGroup(group);
    } else {
      appState.updateJournalGroup(group);
    }

    Navigator.pop(context);
  }
}
