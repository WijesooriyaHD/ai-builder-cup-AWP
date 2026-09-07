import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/blog_post.dart';
import '../providers/app_state.dart';

class AudioPodcastSheet extends StatefulWidget {
  final BlogPost blog;

  const AudioPodcastSheet({super.key, required this.blog});

  @override
  State<AudioPodcastSheet> createState() => _AudioPodcastSheetState();
}

class _AudioPodcastSheetState extends State<AudioPodcastSheet> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  
  @override
  void initState() {
    super.initState();
    
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  String _formatDuration(int seconds) {
    if (seconds < 0) return "0:00";
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return "$minutes:${remainingSeconds.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final appState = Provider.of<AppState>(context);
    final displayedBlog = appState.currentAudioBlog ?? widget.blog;
    
    final totalSeconds = appState.audioTotalSeconds;
    final elapsedSeconds = appState.audioElapsedSeconds;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2635) : Colors.white,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 24),
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          // Blog Info
          Text(
            displayedBlog.category.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
              color: Theme.of(context).primaryColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            displayedBlog.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 32),
          
          // Seek Bar
          Column(
            children: [
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                  activeTrackColor: Theme.of(context).primaryColor,
                  inactiveTrackColor: Theme.of(context).primaryColor.withOpacity(0.1),
                  thumbColor: Theme.of(context).primaryColor,
                ),
                child: Slider(
                  value: appState.audioProgress.clamp(0.0, 1.0),
                  onChanged: appState.seekAudio,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDuration(elapsedSeconds),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white54 : Colors.black54,
                      ),
                    ),
                    Text(
                      _formatDuration(totalSeconds),
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          
          // Visualizer / Wave
          SizedBox(
            height: 120,
            child: Center(
              child: WaveVisualizer(
                isPlaying: appState.isAudioPlaying,
                pulseController: _pulseController,
              ),
            ),
          ),
          const SizedBox(height: 48),
          
          // Controls
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: appState.skipPreviousBlog,
                icon: const Icon(Icons.skip_previous_rounded),
                iconSize: 40,
                color: Theme.of(context).primaryColor,
              ),
              const SizedBox(width: 24),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(context).primaryColor,
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(context).primaryColor.withOpacity(0.3),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: IconButton(
                  onPressed: () {
                    if (appState.isAudioPlaying) {
                      appState.pauseBlog();
                    } else {
                      appState.playBlog(appState.currentAudioBlog ?? widget.blog);
                    }
                  },
                  icon: Icon(
                    appState.isAudioPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: 40,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 24),
              IconButton(
                onPressed: appState.skipNextBlog,
                icon: const Icon(Icons.skip_next_rounded),
                iconSize: 40,
                color: Theme.of(context).primaryColor,
              ),
            ],
          ),
          const SizedBox(height: 32),
          
          // Stop Button / Close
          TextButton(
            onPressed: () {
              appState.stopBlog();
              Navigator.pop(context);
            },
            child: Text(
              "Stop Narration",
              style: TextStyle(
                color: Colors.redAccent.withOpacity(0.8),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class WaveVisualizer extends StatelessWidget {
  final bool isPlaying;
  final AnimationController pulseController;

  const WaveVisualizer({
    super.key,
    required this.isPlaying,
    required this.pulseController,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).primaryColor;

    return AnimatedBuilder(
      animation: pulseController,
      builder: (context, child) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(15, (index) {
            // Create a variety of heights and animation offsets for each bar
            final offset = index * 0.2;
            final animValue = isPlaying 
                ? (0.2 + (0.8 * ((pulseController.value + offset) % 1.0)))
                : 0.1;
                
            // Sinusoidal distribution for the wave shape
            final multiplier = 1.0 - (0.1 * (index - 7).abs());
            final height = 20.0 + (60.0 * animValue * multiplier);

            return AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: 4,
              height: height,
              decoration: BoxDecoration(
                color: color.withOpacity(isPlaying ? 0.8 : 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        );
      },
    );
  }
}
