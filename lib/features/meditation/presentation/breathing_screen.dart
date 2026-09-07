import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../domain/meditation_catalog.dart';
import '../domain/meditation_models.dart';
import 'meditation_state.dart';
import 'widgets/meditation_widgets.dart';

/// Breathing exercises: pick a pattern + duration, then follow the animated
/// breathing circle. Light haptics mark each phase transition.
class BreathingScreen extends StatefulWidget {
  const BreathingScreen({super.key});

  @override
  State<BreathingScreen> createState() => _BreathingScreenState();
}

class _BreathingScreenState extends State<BreathingScreen> {
  BreathingPattern _pattern = MeditationCatalog.breathing.first;
  int _durationMinutes = MeditationCatalog.breathingDurations[1]; // 3 min
  bool _running = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Breathing'),
        backgroundColor: kMeditationDeep,
        foregroundColor: Colors.white,
      ),
      body: _running
          ? _BreathingSession(
              pattern: _pattern,
              durationMinutes: _durationMinutes,
              onExit: () => setState(() => _running = false),
            )
          : _buildSetup(context),
    );
  }

  Widget _buildSetup(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Text('Choose a pattern',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        ...MeditationCatalog.breathing.map((p) {
          final selected = p.id == _pattern.id;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GestureDetector(
              onTap: () => setState(() => _pattern = p),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: selected
                      ? kMeditationAccent.withOpacity(0.12)
                      : theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: selected
                        ? kMeditationAccent
                        : theme.colorScheme.onSurface.withOpacity(0.08),
                    width: selected ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.name,
                              style: theme.textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 2),
                          Text(p.description,
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant)),
                          const SizedBox(height: 6),
                          Text(_phaseSummary(p),
                              style: theme.textTheme.labelSmall?.copyWith(
                                  color: kMeditationAccent,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    if (selected)
                      const Icon(Icons.check_circle_rounded,
                          color: kMeditationAccent),
                  ],
                ),
              ),
            ),
          );
        }),
        const SizedBox(height: 20),
        Text('Duration',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          children: MeditationCatalog.breathingDurations.map((d) {
            final selected = d == _durationMinutes;
            return ChoiceChip(
              label: Text('$d min'),
              selected: selected,
              onSelected: (_) => setState(() => _durationMinutes = d),
              selectedColor: kMeditationAccent,
              labelStyle: TextStyle(
                color: selected ? Colors.white : theme.colorScheme.onSurface,
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
              ),
              backgroundColor: kMeditationAccent.withOpacity(0.08),
            );
          }).toList(),
        ),
        const SizedBox(height: 32),
        SizedBox(
          height: 54,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: kMeditationAccent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onPressed: () => setState(() => _running = true),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Begin',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  String _phaseSummary(BreathingPattern p) {
    final parts = <String>['In ${p.inhale}s'];
    if (p.hold1 > 0) parts.add('Hold ${p.hold1}s');
    parts.add('Out ${p.exhale}s');
    if (p.hold2 > 0) parts.add('Hold ${p.hold2}s');
    return parts.join(' · ');
  }
}

/// The live breathing session driven by the pattern's phase timings.
class _BreathingSession extends StatefulWidget {
  final BreathingPattern pattern;
  final int durationMinutes;
  final VoidCallback onExit;

  const _BreathingSession({
    required this.pattern,
    required this.durationMinutes,
    required this.onExit,
  });

  @override
  State<_BreathingSession> createState() => _BreathingSessionState();
}

class _BreathingSessionState extends State<_BreathingSession> {
  Timer? _timer;
  int _elapsed = 0;
  late int _totalSeconds;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _totalSeconds = widget.durationMinutes * 60;
    HapticFeedback.lightImpact();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        final prevPhase = _phaseAt(_elapsed).label;
        _elapsed++;
        final phase = _phaseAt(_elapsed).label;
        if (phase != prevPhase) HapticFeedback.selectionClick();
        if (_elapsed >= _totalSeconds) _finish();
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _finish() async {
    if (_completed) return;
    _completed = true;
    _timer?.cancel();
    HapticFeedback.mediumImpact();
    final minutes =
        (_elapsed / 60).ceil().clamp(1, widget.durationMinutes);
    await context.read<MeditationState>().completeSession(
          type: SessionType.breathing,
          title: widget.pattern.name,
          minutes: minutes,
        );
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Column(
          children: const [
            Text('🌬️', style: TextStyle(fontSize: 44)),
            SizedBox(height: 8),
            Text('Well breathed'),
          ],
        ),
        content: Text(
          'You completed ${widget.durationMinutes} minutes of '
          '${widget.pattern.name}.',
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              widget.onExit();
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  /// Returns the current phase scale (0.6→1.0) and label for [second].
  ({double scale, String label, int remaining}) _phaseAt(int second) {
    final p = widget.pattern;
    final cycle = p.cycleSeconds;
    var pos = cycle == 0 ? 0 : second % cycle;

    if (pos < p.inhale) {
      final t = p.inhale == 0 ? 1.0 : pos / p.inhale;
      return (scale: 0.6 + 0.4 * t, label: 'Inhale', remaining: p.inhale - pos);
    }
    pos -= p.inhale;
    if (pos < p.hold1) {
      return (scale: 1.0, label: 'Hold', remaining: p.hold1 - pos);
    }
    pos -= p.hold1;
    if (pos < p.exhale) {
      final t = p.exhale == 0 ? 1.0 : pos / p.exhale;
      return (scale: 1.0 - 0.4 * t, label: 'Exhale', remaining: p.exhale - pos);
    }
    pos -= p.exhale;
    return (scale: 0.6, label: 'Hold', remaining: p.hold2 - pos);
  }

  @override
  Widget build(BuildContext context) {
    final phase = _phaseAt(_elapsed);
    final remaining = (_totalSeconds - _elapsed).clamp(0, _totalSeconds);

    return Container(
      color: kMeditationDeep,
      child: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () {
                  _timer?.cancel();
                  widget.onExit();
                },
              ),
            ),
            const Spacer(),
            BreathingCircle(
              scale: phase.scale,
              instruction: phase.label,
              countdown: phase.remaining,
              progress: _totalSeconds == 0 ? 0 : _elapsed / _totalSeconds,
            ),
            const SizedBox(height: 28),
            Text(
              _fmt(remaining),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Text('remaining',
                style: TextStyle(color: Colors.white60, fontSize: 12)),
            const Spacer(),
            Text(widget.pattern.name,
                style: const TextStyle(color: Colors.white70, fontSize: 14)),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  String _fmt(int seconds) {
    final m = seconds ~/ 60;
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
