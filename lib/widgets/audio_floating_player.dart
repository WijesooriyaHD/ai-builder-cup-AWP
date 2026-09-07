import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import 'audio_podcast_sheet.dart';
import '../main.dart';

class AudioFloatingPlayer extends StatefulWidget {
  const AudioFloatingPlayer({super.key});

  @override
  State<AudioFloatingPlayer> createState() => _AudioFloatingPlayerState();
}

class _AudioFloatingPlayerState extends State<AudioFloatingPlayer> {
  Offset _position = const Offset(20, 100); // Initial position

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Consumer<AppState>(
      builder: (context, appState, child) {
        if (appState.currentAudioBlog == null) return const SizedBox.shrink();

        return Positioned(
          left: _position.dx,
          top: _position.dy,
          child: GestureDetector(
            onPanUpdate: (details) {
              setState(() {
                _position += details.delta;
                // Clamp within screen bounds
                double x = _position.dx.clamp(16, screenWidth - 76);
                double y = _position.dy.clamp(60, screenHeight - 120);
                _position = Offset(x, y);
              });
            },
            onTap: () {
              final blog = appState.currentAudioBlog;
              final navContext = globalNavigatorKey.currentContext;
              if (blog != null && navContext != null) {
                showModalBottomSheet(
                  context: navContext,
                  backgroundColor: Colors.transparent,
                  isScrollControlled: true,
                  builder: (context) => AudioPodcastSheet(blog: blog),
                );
              }
            },
            child: _buildPlayer(appState),
          ),
        );
      },
    );
  }

  Widget _buildPlayer(AppState appState) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      elevation: 8,
      shape: const CircleBorder(),
      color: Colors.transparent,
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isDark ? const Color(0xFF2A2635) : Colors.white,
          border: Border.all(
            color: Theme.of(context).primaryColor.withOpacity(0.1),
            width: 1,
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Circular Progress
            SizedBox(
              width: 52,
              height: 52,
              child: CircularProgressIndicator(
                value: appState.audioProgress,
                strokeWidth: 3,
                backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
                valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).primaryColor),
              ),
            ),
            // Icon
            Icon(
              appState.isAudioPlaying ? Icons.graphic_eq_rounded : Icons.headphones_rounded,
              size: 24,
              color: Theme.of(context).primaryColor,
            ),
          ],
        ),
      ),
    );
  }
}
