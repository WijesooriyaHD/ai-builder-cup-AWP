import 'package:audio_service/audio_service.dart';
import '../models/blog_post.dart';

class BlogAudioHandler extends BaseAudioHandler {
  final Function() onPlay;
  final Function() onPause;
  final Function() onStop;
  final Function() onSkipNext;
  final Function() onSkipPrevious;
  final Function(Duration) onSeek;

  BlogAudioHandler({
    required this.onPlay,
    required this.onPause,
    required this.onStop,
    required this.onSkipNext,
    required this.onSkipPrevious,
    required this.onSeek,
  }) {
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        MediaControl.play,
        MediaControl.stop,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.play,
        MediaAction.pause,
        MediaAction.stop,
        MediaAction.seek,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
      },
      androidCompactActionIndices: const [0, 1, 3],
      playing: false,
      processingState: AudioProcessingState.idle,
    ));
  }

  void updateMetadata(BlogPost blog) {
    mediaItem.add(MediaItem(
      id: blog.id,
      album: blog.category,
      title: blog.title,
      artist: 'AI Wellness Pal Narration',
      duration: Duration(seconds: (blog.content.length / 10).toInt()),
      artUri: Uri.parse('https://images.unsplash.com/photo-1490730141103-6cac27aaab94?auto=format&fit=crop&q=80&w=200'), // Placeholder for now
    ));
  }

  void updatePlaybackState({
    required bool playing,
    required Duration position,
    double speed = 1.0,
  }) {
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.stop,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.play,
        MediaAction.pause,
        MediaAction.stop,
        MediaAction.seek,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
      },
      androidCompactActionIndices: const [0, 1, 3],
      playing: playing,
      processingState: AudioProcessingState.ready,
      updatePosition: position,
      speed: speed,
    ));
  }

  @override
  Future<void> play() async => onPlay();

  @override
  Future<void> pause() async => onPause();

  @override
  Future<void> stop() async {
    await onStop();
    playbackState.add(playbackState.value.copyWith(
      playing: false,
      processingState: AudioProcessingState.idle,
    ));
  }

  @override
  Future<void> skipToNext() async => onSkipNext();

  @override
  Future<void> skipToPrevious() async => onSkipPrevious();

  @override
  Future<void> seek(Duration position) async => onSeek(position);
}
