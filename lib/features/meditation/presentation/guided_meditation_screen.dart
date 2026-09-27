import 'package:flutter/material.dart';

import '../domain/meditation_catalog.dart';
import '../domain/meditation_models.dart';
import 'meditation_player_screen.dart';
import 'widgets/meditation_widgets.dart';

/// Browse guided meditations by category, then launch the timed player.
class GuidedMeditationScreen extends StatefulWidget {
  const GuidedMeditationScreen({super.key});

  @override
  State<GuidedMeditationScreen> createState() => _GuidedMeditationScreenState();
}

class _GuidedMeditationScreenState extends State<GuidedMeditationScreen> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Only offer categories that actually have sessions.
    final categories = MeditationCatalog.categories
        .where((c) => MeditationCatalog.guidedFor(c).isNotEmpty)
        .toList();
    if (categories.isEmpty) categories.add(MeditationCatalog.categories.first);
    if (_selected >= categories.length) _selected = 0;
    final category = categories[_selected];
    final items = MeditationCatalog.guidedFor(category);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Guided Meditation'),
        backgroundColor: kMeditationDeep,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Category selector.
          SizedBox(
            height: 52,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final selected = i == _selected;
                return ChoiceChip(
                  label: Text(categories[i]),
                  selected: selected,
                  onSelected: (_) => setState(() => _selected = i),
                  selectedColor: kMeditationAccent,
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : theme.colorScheme.onSurface,
                    fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                  ),
                  backgroundColor: kMeditationAccent.withOpacity(0.08),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                );
              },
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? const MeditationEmptyState(
                    emoji: '🧘',
                    title: 'No sessions here',
                    message: 'Try another category to find a session.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) {
                      final g = items[i];
                      return MeditationListCard(
                        emoji: g.emoji,
                        title: g.title,
                        subtitle: g.description,
                        trailing:
                            '${g.durationMinutes} min · ${g.difficulty.label}',
                        onTap: () => _play(g),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _play(GuidedMeditation g) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MeditationPlayerScreen(
          title: g.title,
          emoji: g.emoji,
          minutes: g.durationMinutes,
          type: SessionType.guided,
        ),
      ),
    );
  }
}
