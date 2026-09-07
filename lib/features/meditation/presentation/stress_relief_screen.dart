import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/meditation_catalog.dart';
import '../domain/meditation_models.dart';
import 'meditation_state.dart';
import 'widgets/meditation_widgets.dart';

/// Quick stress-relief exercises with step-by-step guidance.
class StressReliefScreen extends StatelessWidget {
  const StressReliefScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stress Relief'),
        backgroundColor: kMeditationDeep,
        foregroundColor: Colors.white,
      ),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        itemCount: MeditationCatalog.stressExercises.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) {
          final e = MeditationCatalog.stressExercises[i];
          return MeditationListCard(
            emoji: e.emoji,
            title: e.title,
            subtitle: e.benefits,
            trailing: '${e.durationMinutes} min',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => _StressExerciseScreen(exercise: e),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _StressExerciseScreen extends StatefulWidget {
  final StressExercise exercise;
  const _StressExerciseScreen({required this.exercise});

  @override
  State<_StressExerciseScreen> createState() => _StressExerciseScreenState();
}

class _StressExerciseScreenState extends State<_StressExerciseScreen> {
  int _step = 0;
  bool _completed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = widget.exercise;
    final steps = e.steps;
    final isLast = _step >= steps.length - 1;

    return Scaffold(
      backgroundColor: kMeditationDeep,
      appBar: AppBar(
        title: Text(e.title),
        backgroundColor: kMeditationDeep,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Text(e.emoji, style: const TextStyle(fontSize: 48)),
              const SizedBox(height: 8),
              Text(
                e.benefits,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 32),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Step ${_step + 1} of ${steps.length}',
                          style: const TextStyle(
                              color: kMeditationAccent,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      Text(
                        steps[_step],
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  if (_step > 0)
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white54),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: () => setState(() => _step--),
                        child: const Text('Back'),
                      ),
                    ),
                  if (_step > 0) const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: kMeditationAccent,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: () {
                        if (isLast) {
                          _finish();
                        } else {
                          setState(() => _step++);
                        }
                      },
                      child: Text(
                        isLast ? 'Finish' : 'Next',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _finish() async {
    if (_completed) return;
    _completed = true;
    await context.read<MeditationState>().completeSession(
          type: SessionType.stressRelief,
          title: widget.exercise.title,
          minutes: widget.exercise.durationMinutes,
        );
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Column(
          children: const [
            Text('😌', style: TextStyle(fontSize: 44)),
            SizedBox(height: 8),
            Text('Nicely done'),
          ],
        ),
        content: Text(
          'You completed ${widget.exercise.title}. Carry that calm with you.',
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop(); // dialog
              Navigator.of(context).pop(); // exercise screen
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}
