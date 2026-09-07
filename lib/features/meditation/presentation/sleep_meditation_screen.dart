import 'package:flutter/material.dart';

import '../domain/meditation_catalog.dart';
import '../domain/meditation_models.dart';
import 'meditation_player_screen.dart';
import 'widgets/meditation_widgets.dart';

/// Sleep meditations: soothing sessions and ambient soundscapes to help the
/// user drift off. Launches the timed player with a calming visual.
class SleepMeditationScreen extends StatelessWidget {
  const SleepMeditationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sleep'),
        backgroundColor: kMeditationDeep,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [kMeditationDeep, Color(0xFF1E1848)],
              ),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              children: const [
                Text('🌙', style: TextStyle(fontSize: 34)),
                SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Wind down with a calming session or ambient sounds to '
                    'ease into restful sleep.',
                    style: TextStyle(color: Colors.white70, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ...MeditationCatalog.sleep.map(
            (s) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: MeditationListCard(
                emoji: s.emoji,
                title: s.title,
                subtitle: s.description,
                trailing: '${s.durationMinutes} min',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => MeditationPlayerScreen(
                      title: s.title,
                      emoji: s.emoji,
                      minutes: s.durationMinutes,
                      type: SessionType.sleep,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
