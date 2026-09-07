import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../widgets/frosted_container.dart';
import 'wellness_library_screen.dart';

/// Guided Reflection screen for Wellness Library interactive prompts.
///
/// Shows sequential prompts. User types a response to each (≤1000 chars).
/// On final submit, writes completion to Firestore
/// `users/{uid}/wellness_library_completions/{itemId}`.
/// On save failure, shows error and retains user's text for retry.
///
/// Requirements: 7.2, 7.6
class GuidedReflectionScreen extends StatefulWidget {
  final WellnessLibraryItem item;

  const GuidedReflectionScreen({super.key, required this.item});

  @override
  State<GuidedReflectionScreen> createState() => _GuidedReflectionScreenState();
}

class _GuidedReflectionScreenState extends State<GuidedReflectionScreen> {
  late List<String> _prompts;
  late List<TextEditingController> _controllers;
  int _currentPromptIndex = 0;
  bool _isSubmitting = false;
  bool _hasCompleted = false;
  String? _errorMessage;

  /// Maximum characters per response.
  static const int _maxCharsPerResponse = 1000;

  @override
  void initState() {
    super.initState();
    _prompts = _getPrompts();
    _controllers =
        List.generate(_prompts.length, (_) => TextEditingController());
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  /// Advances to the next prompt, or submits on the final prompt.
  void _onNext() {
    if (_currentPromptIndex < _prompts.length - 1) {
      setState(() {
        _currentPromptIndex++;
        _errorMessage = null;
      });
    } else {
      _submitReflection();
    }
  }

  /// Goes back to the previous prompt.
  void _onBack() {
    if (_currentPromptIndex > 0) {
      setState(() {
        _currentPromptIndex--;
        _errorMessage = null;
      });
    }
  }

  /// Submits the final reflection and writes completion to Firestore.
  /// On failure, shows error and retains user's text for retry.
  Future<void> _submitReflection() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final docRef = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('wellness_library_completions')
        .doc(widget.item.id);

    // Build responses map
    final responses = <String, String>{};
    for (int i = 0; i < _prompts.length; i++) {
      responses['prompt_${i + 1}'] = _controllers[i].text;
    }

    try {
      await docRef.set(
        {
          'completion_timestamp': FieldValue.serverTimestamp(),
          'itemId': widget.item.id,
          'title': widget.item.title,
          'format': widget.item.format,
          'category': widget.item.category,
          'status': 'completed',
          'responses': responses,
        },
        SetOptions(merge: true),
      );

      setState(() {
        _hasCompleted = true;
        _isSubmitting = false;
      });
    } catch (e) {
      // Show error + retain text for retry (Requirement 7.6)
      setState(() {
        _isSubmitting = false;
        _errorMessage =
            'Failed to save your reflection. Your text has been preserved — please try again.';
      });
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
          'Guided Reflection',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        centerTitle: true,
        actions: [
          // Progress indicator
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                '${_currentPromptIndex + 1}/${_prompts.length}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ),
        ],
      ),
      body: _hasCompleted ? _buildCompletionView(context) : _buildPromptView(context),
    );
  }

  /// Builds the active prompt view with text input.
  Widget _buildPromptView(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isLastPrompt = _currentPromptIndex == _prompts.length - 1;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Prompt card
                FrostedContainer(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.edit_note_rounded,
                                size: 20,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Prompt ${_currentPromptIndex + 1}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withOpacity(0.8),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _prompts[_currentPromptIndex],
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.onSurface,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Text input area
                FrostedContainer(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        TextField(
                          controller: _controllers[_currentPromptIndex],
                          maxLines: 8,
                          maxLength: _maxCharsPerResponse,
                          decoration: InputDecoration(
                            hintText: 'Write your reflection here...',
                            hintStyle: TextStyle(
                              color: isDark
                                  ? Colors.grey[500]
                                  : Colors.grey[400],
                            ),
                            border: InputBorder.none,
                            counterStyle: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? Colors.grey[500]
                                  : Colors.grey[500],
                            ),
                          ),
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.6,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Error message (retained text for retry)
                if (_errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.red.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          color: Colors.red[400],
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.red[400],
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),

        // Navigation buttons
        Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF0F1115).withOpacity(0.9)
                : const Color(0xFFF8F9FB).withOpacity(0.9),
          ),
          child: Row(
            children: [
              // Back button
              if (_currentPromptIndex > 0)
                Expanded(
                  child: OutlinedButton(
                    onPressed: _onBack,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      side: BorderSide(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withOpacity(0.3),
                      ),
                    ),
                    child: Text(
                      'Back',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              if (_currentPromptIndex > 0) const SizedBox(width: 12),

              // Next / Submit button
              Expanded(
                flex: _currentPromptIndex > 0 ? 2 : 1,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _onNext,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    disabledBackgroundColor: Theme.of(context)
                        .colorScheme
                        .primary
                        .withOpacity(0.5),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Text(
                          isLastPrompt ? 'Submit Reflection' : 'Next',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Builds the completion view shown after successful submission.
  Widget _buildCompletionView(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_circle_rounded,
                size: 64,
                color: Colors.green[600],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Reflection Complete',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Thank you for taking the time to reflect. Your responses have been saved.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                height: 1.5,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  'Back to Library',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Returns guided reflection prompts for this item.
  /// In production these would come from Firestore or a CMS.
  List<String> _getPrompts() {
    // Generate contextual prompts based on the item's category
    switch (widget.item.category) {
      case 'Recovery Education':
        return [
          'How is your body feeling right now? Where do you notice tension or ease?',
          'What is one thing your body has done for you today that you can appreciate?',
          'What would gentle recovery look like for you over the next 24 hours?',
        ];
      case 'Stress Management':
        return [
          'What has been occupying your mind the most this week?',
          'When you imagine releasing one source of stress, which one comes to mind first?',
          'What is one small boundary you could set this week to protect your peace?',
        ];
      case 'Sleep Improvement':
        return [
          'How did you sleep last night? What was the quality of your rest?',
          'What does your ideal wind-down routine look like?',
          'What is one change you could make tonight to support better sleep?',
        ];
      case 'Pilates Guidance':
        return [
          'How does your body feel when you move intentionally versus rushing through the day?',
          'What does mindful movement mean to you personally?',
          'What is one way you could incorporate more gentle movement into tomorrow?',
        ];
      default:
        return [
          'What does wellness mean to you in this season of your life?',
          'What is one area where you would like to give yourself more grace?',
          'Looking ahead to this week, what is one small thing you can do to nurture yourself?',
        ];
    }
  }
}
