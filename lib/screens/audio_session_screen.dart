import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/blog_post.dart';
import '../providers/app_state.dart';
import '../widgets/frosted_container.dart';
import 'wellness_library_screen.dart';

/// Audio Session screen for Wellness Library audio content.
///
/// Reuses the existing `audio_floating_player.dart` floating player bar by
/// starting playback via `AppState.playBlog()`. The floating player persists
/// across screen navigations (it's overlaid at the app level).
///
/// On the final second of playback (progress >= 0.99), writes completion to
/// Firestore `users/{uid}/wellness_library_completions/{itemId}` using the
/// same partial-success pattern as Short Read.
///
/// Requirements: 7.2, 7.3, 7.5
class AudioSessionScreen extends StatefulWidget {
  final WellnessLibraryItem item;

  const AudioSessionScreen({super.key, required this.item});

  @override
  State<AudioSessionScreen> createState() => _AudioSessionScreenState();
}

class _AudioSessionScreenState extends State<AudioSessionScreen> {
  bool _hasMarkedComplete = false;
  bool _isWritingCompletion = false;

  @override
  void initState() {
    super.initState();
    // Start listening for completion
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startAudio();
    });
  }

  /// Starts audio playback using the existing AppState TTS infrastructure.
  /// Creates a BlogPost from the WellnessLibraryItem to reuse the audio system.
  void _startAudio() {
    final appState = context.read<AppState>();
    final blog = _itemToBlogPost(widget.item);
    appState.playBlog(blog);
  }

  /// Converts a WellnessLibraryItem to a BlogPost for the TTS system.
  BlogPost _itemToBlogPost(WellnessLibraryItem item) {
    return BlogPost(
      id: item.id,
      title: item.title,
      excerpt: item.description,
      category: item.category,
      readTimeMinutes: item.durationMinutes,
      imageUrl: '',
      content: _getAudioContent(),
    );
  }

  /// Monitors audio progress and triggers completion write on final second.
  void _checkCompletion(AppState appState) {
    if (_hasMarkedComplete || _isWritingCompletion) return;

    // Check if audio is on the final second (progress >= 0.99)
    if (appState.audioProgress >= 0.99 &&
        appState.currentAudioBlog?.id == widget.item.id) {
      _writeCompletion();
    }
  }

  /// Writes completion to Firestore using partial-success pattern.
  ///
  /// Two independent writes:
  /// 1. `completion_timestamp` field
  /// 2. `status: 'listened'` field
  ///
  /// If one succeeds and the other fails, the successful write is retained.
  Future<void> _writeCompletion() async {
    if (_hasMarkedComplete) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _isWritingCompletion = true);

    final docRef = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('wellness_library_completions')
        .doc(widget.item.id);

    bool timestampWriteSucceeded = false;
    bool statusWriteSucceeded = false;

    // Write 1: completion_timestamp
    try {
      await docRef.set(
        {
          'completion_timestamp': FieldValue.serverTimestamp(),
          'itemId': widget.item.id,
          'title': widget.item.title,
          'format': widget.item.format,
          'category': widget.item.category,
        },
        SetOptions(merge: true),
      );
      timestampWriteSucceeded = true;
    } catch (e) {
      debugPrint('AudioSession: completion_timestamp write failed: $e');
    }

    // Write 2: mark as listened status
    try {
      await docRef.set(
        {'status': 'listened'},
        SetOptions(merge: true),
      );
      statusWriteSucceeded = true;
    } catch (e) {
      debugPrint('AudioSession: status write failed: $e');
    }

    // Partial success: retain whichever write succeeded
    if (timestampWriteSucceeded || statusWriteSucceeded) {
      setState(() {
        _hasMarkedComplete = true;
        _isWritingCompletion = false;
      });
    } else {
      setState(() => _isWritingCompletion = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0F1115) : const Color(0xFFF8F9FB),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_rounded,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Audio Session',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        centerTitle: true,
      ),
      body: Consumer<AppState>(
        builder: (context, appState, child) {
          // Check for completion on each rebuild
          _checkCompletion(appState);

          final isPlaying = appState.isAudioPlaying &&
              appState.currentAudioBlog?.id == widget.item.id;
          final progress = appState.currentAudioBlog?.id == widget.item.id
              ? appState.audioProgress
              : 0.0;
          final elapsed = appState.currentAudioBlog?.id == widget.item.id
              ? appState.audioElapsedSeconds
              : 0;
          final total = appState.currentAudioBlog?.id == widget.item.id
              ? appState.audioTotalSeconds
              : 0;

          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              children: [
                const SizedBox(height: 40),

                // Album art / icon area
                FrostedContainer(
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Column(
                      children: [
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isPlaying
                                ? Icons.graphic_eq_rounded
                                : Icons.headphones_rounded,
                            size: 56,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          widget.item.title,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.item.category,
                          style: TextStyle(
                            fontSize: 14,
                            color:
                                isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Progress bar
                FrostedContainer(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        // Seek slider
                        SliderTheme(
                          data: SliderThemeData(
                            activeTrackColor:
                                Theme.of(context).colorScheme.primary,
                            inactiveTrackColor: Theme.of(context)
                                .colorScheme
                                .primary
                                .withOpacity(0.2),
                            thumbColor:
                                Theme.of(context).colorScheme.primary,
                            overlayColor: Theme.of(context)
                                .colorScheme
                                .primary
                                .withOpacity(0.1),
                            trackHeight: 4,
                            thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 6),
                          ),
                          child: Slider(
                            value: progress.clamp(0.0, 1.0),
                            onChanged: appState.seekAudio,
                          ),
                        ),
                        // Time labels
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _formatTime(elapsed),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? Colors.grey[400]
                                      : Colors.grey[600],
                                ),
                              ),
                              Text(
                                _formatTime(total),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? Colors.grey[400]
                                      : Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Playback controls
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Rewind
                            IconButton(
                              onPressed: () {
                                final newVal =
                                    (progress - 0.1).clamp(0.0, 1.0);
                                appState.seekAudio(newVal);
                              },
                              icon: Icon(
                                Icons.replay_10_rounded,
                                size: 32,
                                color: isDark
                                    ? Colors.grey[300]
                                    : Colors.grey[700],
                              ),
                            ),
                            const SizedBox(width: 20),

                            // Play/Pause
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color:
                                    Theme.of(context).colorScheme.primary,
                              ),
                              child: IconButton(
                                onPressed: () {
                                  if (isPlaying) {
                                    appState.pauseBlog();
                                  } else {
                                    final blog =
                                        _itemToBlogPost(widget.item);
                                    appState.playBlog(blog);
                                  }
                                },
                                icon: Icon(
                                  isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  size: 36,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 20),

                            // Forward
                            IconButton(
                              onPressed: () {
                                final newVal =
                                    (progress + 0.1).clamp(0.0, 1.0);
                                appState.seekAudio(newVal);
                              },
                              icon: Icon(
                                Icons.forward_10_rounded,
                                size: 32,
                                color: isDark
                                    ? Colors.grey[300]
                                    : Colors.grey[700],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Description
                FrostedContainer(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'About this session',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color:
                                Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.item.description,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.6,
                            color: isDark
                                ? Colors.grey[300]
                                : Colors.grey[700],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(
                              Icons.timer_rounded,
                              size: 16,
                              color: isDark
                                  ? Colors.grey[400]
                                  : Colors.grey[600],
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${widget.item.durationMinutes} min',
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark
                                    ? Colors.grey[400]
                                    : Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Completion indicator
                if (_hasMarkedComplete)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle_rounded,
                          color: Colors.green[600],
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Session Completed',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.green[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 40),

                // Note about floating player
                Text(
                  'The audio player will continue across screens.\nYou can navigate away and come back anytime.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.grey[500] : Colors.grey[400],
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Formats seconds into MM:SS string.
  String _formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// Returns audio content text that the TTS engine will read.
  /// In production this would come from Firestore or a CMS.
  String _getAudioContent() {
    return '''${widget.item.description}

Welcome to this guided audio session. Take a comfortable position and allow yourself to fully arrive in this moment. 

Let your shoulders relax away from your ears. Notice the rhythm of your breath without trying to change it. Simply observe.

As we move through this session together, remember that there is no right or wrong way to experience this. Whatever comes up for you is perfectly valid.

Begin to deepen your breath. Inhale slowly through your nose, feeling your belly expand. Hold for just a moment at the top. Then release through your mouth, letting go of any tension you've been carrying.

Continue this pattern. Each breath brings you deeper into a state of calm awareness. Each exhale releases something you no longer need.

Now bring your attention to how your body feels in this moment. Without judgment, simply notice. Where do you feel lightness? Where do you feel heaviness? Where do you feel warmth?

Remember that caring for yourself is not selfish. It is necessary. You cannot pour from an empty cup, and you deserve the same compassion you so freely give to others.

As we near the end of this session, carry this sense of calm with you into the rest of your day. You can return to this feeling anytime simply by pausing and taking three slow breaths.

Thank you for giving yourself this time. You are worthy of this care.''';
  }
}
