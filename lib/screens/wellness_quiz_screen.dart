import 'package:flutter/material.dart';

import '../widgets/frosted_container.dart';

/// A single quiz question with multiple choice answers.
class QuizQuestion {
  final String question;
  final List<String> options;
  final int correctIndex;
  final String explanation;

  const QuizQuestion({
    required this.question,
    required this.options,
    required this.correctIndex,
    required this.explanation,
  });
}

/// Data holder for a wellness quiz.
class WellnessQuizData {
  final String title;
  final List<QuizQuestion> questions;

  const WellnessQuizData({required this.title, required this.questions});
}

/// Wellness Quiz screen that displays questions one at a time and shows
/// total score with per-answer explanations (≤60 words each) on completion.
///
/// On completion, pops with result `true` so calling code can record completion.
///
/// Requirements: 6.6
class WellnessQuizScreen extends StatefulWidget {
  const WellnessQuizScreen({super.key, this.quizId});

  /// Optional quiz ID to select a specific quiz. Defaults to the first quiz.
  final String? quizId;

  @override
  State<WellnessQuizScreen> createState() => _WellnessQuizScreenState();
}

class _WellnessQuizScreenState extends State<WellnessQuizScreen> {
  int _currentQuestionIndex = 0;
  int? _selectedOptionIndex;
  bool _quizCompleted = false;
  final List<int> _userAnswers = [];

  late WellnessQuizData _quiz;

  @override
  void initState() {
    super.initState();
    _quiz = _getQuiz(widget.quizId);
  }

  WellnessQuizData _getQuiz(String? quizId) {
    final quizMap = {
      'quiz_1': _stressAwarenessQuiz,
      'quiz_2': _sleepHygieneQuiz,
      'quiz_3': _recoveryKnowledgeQuiz,
    };
    return quizMap[quizId] ?? _stressAwarenessQuiz;
  }

  int get _totalScore {
    int score = 0;
    for (int i = 0; i < _userAnswers.length; i++) {
      if (_userAnswers[i] == _quiz.questions[i].correctIndex) {
        score++;
      }
    }
    return score;
  }

  void _selectOption(int index) {
    setState(() {
      _selectedOptionIndex = index;
    });
  }

  void _nextQuestion() {
    if (_selectedOptionIndex == null) return;

    setState(() {
      _userAnswers.add(_selectedOptionIndex!);
      _selectedOptionIndex = null;

      if (_currentQuestionIndex < _quiz.questions.length - 1) {
        _currentQuestionIndex++;
      } else {
        _quizCompleted = true;
      }
    });
  }

  void _onComplete() {
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0F1115) : const Color(0xFFF8F9FB),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: theme.colorScheme.onSurface),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        title: Text(
          _quiz.title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: _quizCompleted ? _buildResultsView() : _buildQuestionView(),
      ),
    );
  }

  Widget _buildQuestionView() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final question = _quiz.questions[_currentQuestionIndex];
    final progress = (_currentQuestionIndex + 1) / _quiz.questions.length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),

          // Progress indicator
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: isDark ? Colors.white10 : Colors.grey[200],
                    valueColor: AlwaysStoppedAnimation<Color>(
                      theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${_currentQuestionIndex + 1}/${_quiz.questions.length}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
            ],
          ),

          const SizedBox(height: 32),

          // Question text
          FrostedContainer(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                question.question,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                  height: 1.4,
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Answer options
          Expanded(
            child: ListView.separated(
              itemCount: question.options.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final isSelected = _selectedOptionIndex == index;
                return GestureDetector(
                  onTap: () => _selectOption(index),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? theme.colorScheme.primary.withOpacity(0.12)
                          : (isDark ? Colors.white.withOpacity(0.05) : Colors.white),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected
                            ? theme.colorScheme.primary
                            : (isDark
                                ? Colors.white.withOpacity(0.1)
                                : Colors.grey.withOpacity(0.2)),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isSelected
                                ? theme.colorScheme.primary
                                : Colors.transparent,
                            border: Border.all(
                              color: isSelected
                                  ? theme.colorScheme.primary
                                  : (isDark
                                      ? Colors.white30
                                      : Colors.grey[400]!),
                              width: 2,
                            ),
                          ),
                          child: isSelected
                              ? const Icon(
                                  Icons.check,
                                  size: 16,
                                  color: Colors.white,
                                )
                              : null,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            question.options[index],
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight:
                                  isSelected ? FontWeight.w600 : FontWeight.w500,
                              color: theme.colorScheme.onSurface,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 16),

          // Next button
          SizedBox(
            height: 56,
            child: ElevatedButton(
              onPressed: _selectedOptionIndex != null ? _nextQuestion : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                    isDark ? Colors.grey[800] : Colors.grey[300],
                disabledForegroundColor:
                    isDark ? Colors.grey[600] : Colors.grey[500],
                elevation: _selectedOptionIndex != null ? 2 : 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                _currentQuestionIndex < _quiz.questions.length - 1
                    ? 'Next'
                    : 'See Results',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildResultsView() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),

          // Score card
          FrostedContainer(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Text(
                    'Your Score',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$_totalScore / ${_quiz.questions.length}',
                    style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _scoreMessage,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: theme.colorScheme.onSurface.withOpacity(0.7),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Per-answer explanations
          Text(
            'Review',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),

          ...List.generate(_quiz.questions.length, (index) {
            final question = _quiz.questions[index];
            final userAnswer = _userAnswers[index];
            final isCorrect = userAnswer == question.correctIndex;

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: FrostedContainer(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isCorrect
                                ? Icons.check_circle_rounded
                                : Icons.cancel_rounded,
                            size: 20,
                            color: isCorrect
                                ? Colors.green[400]
                                : Colors.red[300],
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Q${index + 1}: ${question.question}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.onSurface,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (!isCorrect) ...[
                        Text(
                          'Your answer: ${question.options[userAnswer]}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.red[300],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Correct: ${question.options[question.correctIndex]}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.green[400],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 6),
                      ],
                      Text(
                        question.explanation,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: isDark
                              ? Colors.grey[300]
                              : Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),

          const SizedBox(height: 16),

          // Done button
          SizedBox(
            height: 56,
            child: ElevatedButton(
              onPressed: _onComplete,
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: Colors.white,
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(
                'Done',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  String get _scoreMessage {
    final percent = _totalScore / _quiz.questions.length;
    if (percent >= 0.8) {
      return 'Wonderful awareness! You have a strong understanding of wellness fundamentals.';
    } else if (percent >= 0.6) {
      return 'Good effort! You\'re building solid wellness knowledge.';
    } else {
      return 'Every quiz is a learning opportunity. Review the explanations below to deepen your understanding.';
    }
  }
}

// ---------------------------------------------------------------------------
// Sample Quiz Data (hardcoded, at least 5 questions per quiz)
// All explanations are ≤60 words.
// ---------------------------------------------------------------------------

const _stressAwarenessQuiz = WellnessQuizData(
  title: 'Stress Awareness',
  questions: [
    QuizQuestion(
      question: 'Which hormone is primarily released during acute stress?',
      options: ['Melatonin', 'Cortisol', 'Serotonin', 'Dopamine'],
      correctIndex: 1,
      explanation:
          'Cortisol is released by the adrenal glands during stress to mobilize energy. While helpful short-term, chronic elevation can affect sleep, immunity, and mood. Managing stress helps keep cortisol at healthy levels.',
    ),
    QuizQuestion(
      question:
          'What is a common physical sign that stress levels are too high?',
      options: [
        'Improved focus',
        'Tension in shoulders and jaw',
        'Increased appetite for vegetables',
        'Deeper sleep',
      ],
      correctIndex: 1,
      explanation:
          'Muscle tension, especially in the shoulders, neck, and jaw, is one of the earliest physical indicators of elevated stress. Noticing these signals early helps you intervene with relaxation techniques before stress compounds.',
    ),
    QuizQuestion(
      question: 'Which breathing technique can quickly activate the relaxation response?',
      options: [
        'Rapid shallow breathing',
        'Holding breath for 30 seconds',
        'Slow diaphragmatic breathing',
        'Breathing only through the mouth',
      ],
      correctIndex: 2,
      explanation:
          'Slow diaphragmatic (belly) breathing stimulates the vagus nerve and activates the parasympathetic nervous system, shifting the body from fight-or-flight into rest-and-restore mode within a few breaths.',
    ),
    QuizQuestion(
      question: 'How does regular physical movement help reduce stress?',
      options: [
        'It increases cortisol permanently',
        'It releases endorphins and lowers tension',
        'It has no effect on stress hormones',
        'It only helps if done for over an hour',
      ],
      correctIndex: 1,
      explanation:
          'Movement releases endorphins, natural mood boosters, and helps metabolize excess stress hormones. Even short walks or gentle stretching can reduce tension and improve mental clarity.',
    ),
    QuizQuestion(
      question: 'What is the recommended first step when you notice stress building?',
      options: [
        'Push through and ignore it',
        'Pause and take three slow breaths',
        'Drink coffee to stay alert',
        'Skip meals to save time',
      ],
      correctIndex: 1,
      explanation:
          'Pausing to take slow breaths interrupts the stress cycle, giving your nervous system a moment to recalibrate. This small act of awareness prevents stress from escalating and helps you respond rather than react.',
    ),
  ],
);

const _sleepHygieneQuiz = WellnessQuizData(
  title: 'Sleep Hygiene',
  questions: [
    QuizQuestion(
      question: 'What is the ideal room temperature for quality sleep?',
      options: ['15–17°C (59–63°F)', '18–20°C (65–68°F)', '23–25°C (73–77°F)', '26–28°C (79–82°F)'],
      correctIndex: 1,
      explanation:
          'A cool room around 18-20 degrees Celsius supports the body\'s natural temperature drop during sleep. Rooms that are too warm can disrupt deep sleep stages and cause restlessness.',
    ),
    QuizQuestion(
      question: 'How long before bed should you stop using screens for better sleep?',
      options: ['5 minutes', '30–60 minutes', 'No restriction needed', '3 hours'],
      correctIndex: 1,
      explanation:
          'Blue light from screens suppresses melatonin production. Stopping screen use 30–60 minutes before bed allows melatonin to rise naturally, supporting a smoother transition into sleep.',
    ),
    QuizQuestion(
      question: 'Which substance most disrupts sleep architecture even in small amounts?',
      options: ['Water', 'Caffeine after 2pm', 'Herbal tea', 'Magnesium'],
      correctIndex: 1,
      explanation:
          'Caffeine has a half-life of 5–6 hours and blocks adenosine receptors that promote sleepiness. Consuming it after early afternoon can reduce deep sleep duration even if you fall asleep easily.',
    ),
    QuizQuestion(
      question: 'What is a consistent sleep schedule\'s primary benefit?',
      options: [
        'It lets you sleep less overall',
        'It strengthens your circadian rhythm',
        'It eliminates the need for darkness',
        'It replaces exercise',
      ],
      correctIndex: 1,
      explanation:
          'Going to bed and waking at the same time daily reinforces your circadian rhythm, making it easier to fall asleep and wake feeling rested. Irregular schedules confuse your internal clock.',
    ),
    QuizQuestion(
      question: 'Which pre-sleep activity is most supportive of restful sleep?',
      options: [
        'Intense exercise',
        'Watching thrilling content',
        'Gentle stretching or reading',
        'Checking work emails',
      ],
      correctIndex: 2,
      explanation:
          'Calming activities like gentle stretching or reading lower heart rate and signal to your body that it is time to wind down. Stimulating activities keep the nervous system alert, delaying sleep onset.',
    ),
  ],
);

const _recoveryKnowledgeQuiz = WellnessQuizData(
  title: 'Recovery Knowledge',
  questions: [
    QuizQuestion(
      question: 'What is active recovery?',
      options: [
        'Complete bed rest after exercise',
        'Light movement that promotes blood flow without strain',
        'Repeating the same workout at lower weight',
        'Taking pain medication to mask soreness',
      ],
      correctIndex: 1,
      explanation:
          'Active recovery involves low-intensity movement like walking or gentle stretching that increases circulation, helping deliver nutrients to muscles and clear metabolic waste without adding stress.',
    ),
    QuizQuestion(
      question: 'How many hours of sleep do most adults need for optimal recovery?',
      options: ['4–5 hours', '5–6 hours', '7–9 hours', '10–12 hours'],
      correctIndex: 2,
      explanation:
          'Most adults need 7–9 hours for the body to complete essential repair processes, including muscle recovery, immune function, and memory consolidation that occur during deep sleep cycles.',
    ),
    QuizQuestion(
      question: 'Which nutrient is most important for muscle repair after activity?',
      options: ['Sugar', 'Protein', 'Caffeine', 'Sodium'],
      correctIndex: 1,
      explanation:
          'Protein provides amino acids needed to repair and rebuild muscle fibers stressed during activity. Consuming adequate protein within a few hours of exercise supports faster recovery.',
    ),
    QuizQuestion(
      question: 'What does delayed onset muscle soreness (DOMS) typically indicate?',
      options: [
        'A serious injury requiring medical attention',
        'Normal micro-damage from unaccustomed activity',
        'Dehydration only',
        'You should never exercise again',
      ],
      correctIndex: 1,
      explanation:
          'DOMS is a normal response to new or intensified activity, caused by microscopic muscle fiber damage. It usually peaks 24–72 hours after exercise and resolves on its own with rest and gentle movement.',
    ),
    QuizQuestion(
      question: 'Why is hydration important for recovery?',
      options: [
        'It has no effect on recovery',
        'Water transports nutrients and removes waste from cells',
        'Only athletes need to hydrate',
        'It replaces the need for sleep',
      ],
      correctIndex: 1,
      explanation:
          'Water is essential for transporting nutrients to recovering tissues, removing metabolic byproducts, and maintaining joint lubrication. Even mild dehydration can slow recovery and increase perceived fatigue.',
    ),
  ],
);
