import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';

import '../models/wellness_action.dart';
import '../models/wellness_enums.dart';
import '../models/wellness_method.dart';
import '../providers/app_state.dart';
import '../services/ai_service.dart';
import '../utils/pro_modal_utils.dart';
import '../utils/wellnesspal_snackbar.dart';
import '../widgets/frosted_container.dart';

/// Detail view for a single [WellnessAction].
///
/// Displayed when the user taps an action card on the Home screen.
/// Back navigation returns the user to the Home screen in one step
/// (Requirement 4.4).
class ActionDetailScreen extends StatefulWidget {
  const ActionDetailScreen({super.key, required this.action});

  final WellnessAction action;

  @override
  State<ActionDetailScreen> createState() => _ActionDetailScreenState();
}

class _ActionDetailScreenState extends State<ActionDetailScreen> {
  /// The AI-generated "how to" lesson, once requested. Null until the user
  /// asks for it (we deliberately do NOT show instructions up front).
  String? _lesson;
  bool _isGeneratingLesson = false;
  String? _lessonError;

  WellnessAction get action => widget.action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Infer the wellness method from the action title (e.g. "Pilates core
    // flow" -> Pilates). Only shown when a keyword match is found.
    final method = wellnessMethodForText(action.title);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Action Detail'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Category icon and badge
            Center(
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: _categoryColor(action.category).withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _categoryIcon(action.category),
                  size: 48,
                  color: _categoryColor(action.category),
                ),
              ),
            ).animate().fadeIn(duration: 400.ms).scale(
                  begin: const Offset(0.8, 0.8),
                  end: const Offset(1.0, 1.0),
                ),
            const SizedBox(height: 24),

            // Title
            Center(
              child: Text(
                action.title,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ).animate().fadeIn(delay: 100.ms, duration: 400.ms),
            const SizedBox(height: 24),

            // Details card
            FrostedContainer(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _DetailRow(
                      icon: Icons.timer_rounded,
                      label: 'Duration',
                      value: '${action.durationMinutes} minutes',
                    ),
                    const Divider(height: 24),
                    _DetailRow(
                      icon: Icons.category_rounded,
                      label: 'Category',
                      value: _categoryLabel(action.category),
                    ),
                    if (method != null) ...[
                      const Divider(height: 24),
                      _DetailRow(
                        icon: method.icon,
                        label: 'Wellness Method',
                        value: method.label,
                      ),
                    ],
                    const Divider(height: 24),
                    _DetailRow(
                      icon: Icons.speed_rounded,
                      label: 'Intensity',
                      value: _intensityLabel(action.intensityLevel),
                    ),
                    const Divider(height: 24),
                    _DetailRow(
                      icon: Icons.check_circle_outline_rounded,
                      label: 'Status',
                      value: action.isCompleted ? 'Completed' : 'Not started',
                    ),
                  ],
                ),
              ),
            ).animate().fadeIn(delay: 200.ms, duration: 400.ms),
            const SizedBox(height: 20),

            // "How to do this" — a Premium-gated section where the user can
            // ask the AI for a lesson-style walkthrough of the action. The
            // instructions are hidden until explicitly requested.
            _buildHowToSection(theme, method)
                .animate()
                .fadeIn(delay: 300.ms, duration: 400.ms),
          ],
        ),
      ),
    );
  }

  Widget _buildHowToSection(ThemeData theme, WellnessMethod? method) {
    return FrostedContainer(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'How to do this',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                // Premium badge for free users.
                if (!context.watch<AppState>().isPro)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6B9D).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.workspace_premium_rounded,
                            size: 14, color: Color(0xFFFF6B9D)),
                        SizedBox(width: 4),
                        Text(
                          'Premium',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFFF6B9D),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _lesson == null
                  ? 'Not sure how to do this? Get a friendly, step-by-step '
                      'walkthrough tailored to this activity.'
                  : 'Your personalized step-by-step guide:',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),

            // Generated lesson (once available).
            if (_lesson != null)
              MarkdownBody(
                data: _lesson!,
                styleSheet: MarkdownStyleSheet.fromTheme(theme),
              ),

            // Inline error (e.g. timeout / App Check).
            if (_lessonError != null) ...[
              Text(
                _lessonError!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Action button: generate / regenerate.
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isGeneratingLesson ? null : _onExplainPressed,
                icon: _isGeneratingLesson
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(_lesson == null
                        ? Icons.auto_awesome_rounded
                        : Icons.refresh_rounded),
                label: Text(
                  _isGeneratingLesson
                      ? 'Generating…'
                      : (_lesson == null
                          ? 'Show me how'
                          : 'Regenerate guide'),
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onExplainPressed() async {
    final appState = context.read<AppState>();

    // Premium gate: free users see the upsell modal instead of a lesson.
    if (!appState.isPro) {
      ProModalUtils.showFeatureUpsellModal(
        context,
        title: 'Premium Feature',
        message:
            'Step-by-step AI guidance for each wellness action is a Premium '
            'feature. Upgrade to learn exactly how to do every activity in '
            'your plan.',
        icon: Icons.auto_awesome_rounded,
      );
      return;
    }

    setState(() {
      _isGeneratingLesson = true;
      _lessonError = null;
    });

    final method = wellnessMethodForText(action.title);

    try {
      final lesson = await AIService().explainAction(
        actionTitle: action.title,
        category: _categoryLabel(action.category),
        intensity: _intensityLabel(action.intensityLevel),
        durationMinutes: action.durationMinutes,
        method: method?.label,
      );

      if (!mounted) return;
      setState(() {
        _isGeneratingLesson = false;
        if (lesson == null || lesson.trim().isEmpty) {
          _lessonError =
              "I couldn't put together a guide right now. Please try again.";
        } else {
          _lesson = lesson;
        }
      });
    } catch (e) {
      if (!mounted) return;
      final reason = e.toString().replaceFirst('Exception: ', '');
      setState(() {
        _isGeneratingLesson = false;
        _lessonError = reason;
      });
      WellnessPalSnackBar.show(context, message: reason, isError: true);
    }
  }

  IconData _categoryIcon(WellnessCategory category) {
    switch (category) {
      case WellnessCategory.flexibility:
        return Icons.accessibility_new_rounded;
      case WellnessCategory.stress:
        return Icons.spa_rounded;
      case WellnessCategory.sleep:
        return Icons.bedtime_rounded;
      case WellnessCategory.movement:
        return Icons.directions_run_rounded;
      case WellnessCategory.recovery:
        return Icons.healing_rounded;
      case WellnessCategory.energy:
        return Icons.bolt_rounded;
      case WellnessCategory.mentalClarity:
        return Icons.psychology_rounded;
      case WellnessCategory.mindfulness:
        return Icons.self_improvement_rounded;
      case WellnessCategory.general:
        return Icons.favorite_rounded;
    }
  }

  Color _categoryColor(WellnessCategory category) {
    switch (category) {
      case WellnessCategory.flexibility:
        return Colors.purple.shade400;
      case WellnessCategory.stress:
        return Colors.teal.shade400;
      case WellnessCategory.sleep:
        return Colors.indigo.shade400;
      case WellnessCategory.movement:
        return Colors.orange.shade400;
      case WellnessCategory.recovery:
        return Colors.green.shade400;
      case WellnessCategory.energy:
        return Colors.amber.shade600;
      case WellnessCategory.mentalClarity:
        return Colors.blue.shade400;
      case WellnessCategory.mindfulness:
        return Colors.deepPurple.shade300;
      case WellnessCategory.general:
        return Colors.pink.shade300;
    }
  }

  String _categoryLabel(WellnessCategory category) {
    switch (category) {
      case WellnessCategory.flexibility:
        return 'Flexibility';
      case WellnessCategory.stress:
        return 'Stress Relief';
      case WellnessCategory.sleep:
        return 'Sleep';
      case WellnessCategory.movement:
        return 'Movement';
      case WellnessCategory.recovery:
        return 'Recovery';
      case WellnessCategory.energy:
        return 'Energy';
      case WellnessCategory.mentalClarity:
        return 'Mental Clarity';
      case WellnessCategory.mindfulness:
        return 'Mindfulness';
      case WellnessCategory.general:
        return 'General Wellness';
    }
  }

  String _intensityLabel(IntensityLevel level) {
    switch (level) {
      case IntensityLevel.low:
        return 'Low — Gentle';
      case IntensityLevel.medium:
        return 'Medium — Moderate';
      case IntensityLevel.high:
        return 'High — Active';
    }
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: theme.colorScheme.primary.withOpacity(0.7),
        ),
        const SizedBox(width: 12),
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withOpacity(0.6),
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}
