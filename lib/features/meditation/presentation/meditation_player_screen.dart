import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/meditation_models.dart';
import 'meditation_state.dart';
import 'widgets/meditation_widgets.dart';

/// A premium, timed guided-session player. Since no narrated audio assets are
/// bundled, this drives a calming timer with a breathing orb, phase cues,
/// artwork, and full transport controls — audio can drop in later behind the
/// same screen. On completion it records the session for tracking.
class MeditationPlayerScreen extends StatefulWidget {
  final String title;
  final String emoji;
  final int minutes;
  final SessionType type;

  const MeditationPlayerScreen({
    super.key,
    required this.title,
    required this.emoji,
    required this.minutes,
    required this.type,
  });

  @override
  State<MeditationPlayerScreen> createState() => _MeditationPlayerScreenState();
}

class _MeditationPlayerScreenState extends State<MeditationPlayerScreen> {
  Timer? _timer;
  late int _totalSeconds;
  int _elapsed = 0;
  bool _playing = true;
  bool _completed = false;

  // Breathing orb (6s inhale-hold-exhale loop for calm pacing).
  static const int _inhale = 4, _hold = 2, _exhale = 4;
  int get _cycle => _inhale + _hold + _exhale;

  @override
  void initState() {
    super.initState();
    _totalSeconds = widget.minutes * 60;
    _start();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_playing) return;
      setState(() {
        _elapsed++;
        if (_elapsed >= _totalSeconds) _finish();
      });
    });
  }

  Future<void> _finish() async {
    if (_completed) return;
    _completed = true;
    _timer?.cancel();
    final minutes = (_elapsed / 60).ceil().clamp(1, widget.minutes);
    final newly = await context.read<MeditationState>().completeSession(
          type: widget.type,
          title: widget.title,
          minutes: minutes,
        );
    if (!mounted) return;
    _showCompletion(newly);
  }

  void _togglePlay() => setState(() => _playing = !_playing);

  void _skip(int seconds) {
    setState(() {
      _elapsed = (_elapsed + seconds).clamp(0, _totalSeconds);
      if (_elapsed >= _totalSeconds) _finish();
    });
  }

  // Breathing orb scale + instruction for the current second.
  ({double scale, String label}) _breathState() {
    final pos = _elapsed % _cycle;
    if (pos < _inhale) {
      return (scale: 0.6 + 0.4 * (pos / _inhale), label: 'Inhale');
    } else if (pos < _inhale + _hold) {
      return (scale: 1.0, label: 'Hold');
    } else {
      final e = pos - _inhale - _hold;
      return (scale: 1.0 - 0.4 * (e / _exhale), label: 'Exhale');
    }
  }

  @override
  Widget build(BuildContext context) {
    final remaining = (_totalSeconds - _elapsed).clamp(0, _totalSeconds);
    final breath = _breathState();

    return Scaffold(
      backgroundColor: kMeditationDeep,
      body: SafeArea(
        child: Column(
          children: [
            // Header.
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  Text('${widget.emoji}  ${widget.title}',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            const Spacer(),
            // Breathing orb (doubles as artwork + progress).
            BreathingCircle(
              scale: _playing ? breath.scale : 0.75,
              instruction: _playing ? breath.label : 'Paused',
              countdown: (_cycle - (_elapsed % _cycle)),
              progress: _totalSeconds == 0 ? 0 : _elapsed / _totalSeconds,
            ),
            const SizedBox(height: 32),
            Text(_fmt(remaining),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 40,
                    fontWeight: FontWeight.bold)),
            const Text('remaining',
                style: TextStyle(color: Colors.white60, fontSize: 13)),
            const Spacer(),
            // Transport controls.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ctrl(Icons.replay_10_rounded, () => _skip(-10)),
                const SizedBox(width: 24),
                GestureDetector(
                  onTap: _togglePlay,
                  child: Container(
                    width: 76,
                    height: 76,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: kMeditationDeep,
                      size: 40,
                    ),
                  ),
                ),
                const SizedBox(width: 24),
                _ctrl(Icons.forward_10_rounded, () => _skip(10)),
              ],
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _ctrl(IconData icon, VoidCallback onTap) => IconButton(
        iconSize: 34,
        icon: Icon(icon, color: Colors.white),
        onPressed: onTap,
      );

  String _fmt(int seconds) {
    final m = seconds ~/ 60;
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _showCompletion(List<MindfulnessAchievement> newly) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Column(
          children: [
            const Text('🌿', style: TextStyle(fontSize: 44)),
            const SizedBox(height: 8),
            const Text('Session complete'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Nicely done. You practiced ${widget.title.toLowerCase()}.',
                textAlign: TextAlign.center),
            if (newly.isNotEmpty) ...[
              const SizedBox(height: 16),
              ...newly.map((a) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(a.emoji, style: const TextStyle(fontSize: 18)),
                        const SizedBox(width: 8),
                        Text('Unlocked: ${a.title}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  )),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}
