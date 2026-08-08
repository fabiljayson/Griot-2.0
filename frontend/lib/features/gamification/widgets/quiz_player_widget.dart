import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../providers/gamification_provider.dart';
import '../services/gamification_api_service.dart';

/// Interactive quiz player widget with instant feedback.
///
/// Features:
///   - Progress indicator
///   - Animated question transitions
///   - Color-coded answer feedback (correct/incorrect)
///   - Explanation reveal
///   - Score summary at completion
class QuizPlayerWidget extends ConsumerStatefulWidget {
  const QuizPlayerWidget({super.key, required this.quizId, this.onCompleted});

  final int quizId;
  final void Function(int score)? onCompleted;

  @override
  ConsumerState<QuizPlayerWidget> createState() => _QuizPlayerWidgetState();
}

class _QuizPlayerWidgetState extends ConsumerState<QuizPlayerWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  String? _selectedAnswer;
  bool _showFeedback = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _animController.forward();

    // Load and start the quiz
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(quizPlayerProvider.notifier).startQuiz(widget.quizId);
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _animateTransition() {
    _animController.reset();
    _animController.forward();
  }

  void _onAnswerSelected(String answer) {
    if (_showFeedback) return;

    final state = ref.read(quizPlayerProvider);
    final currentQuestion = state.quiz?.questions[state.currentQuestionIndex];
    if (currentQuestion == null) return;

    setState(() {
      _selectedAnswer = answer;
      _showFeedback = true;
    });

    // Submit the answer
    ref
        .read(quizPlayerProvider.notifier)
        .submitAnswer(currentQuestion.id, answer);
  }

  void _nextQuestion() {
    setState(() {
      _selectedAnswer = null;
      _showFeedback = false;
    });
    _animateTransition();
    ref.read(quizPlayerProvider.notifier).nextQuestion();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(quizPlayerProvider);

    if (state.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.terracotta),
      );
    }

    if (state.isCompleted) {
      return _buildCompletionView(state);
    }

    if (state.quiz == null || state.quiz!.questions.isEmpty) {
      return const Center(child: Text('No questions available'));
    }

    final quiz = state.quiz!;
    final questionIndex = state.currentQuestionIndex;
    final question = quiz.questions[questionIndex];
    final isLastQuestion = questionIndex >= quiz.questions.length - 1;

    return Column(
      children: [
        // Progress bar
        _buildProgressBar(questionIndex, quiz.questions.length),

        // Question
        Expanded(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Question number
                  Text(
                    'Question ${questionIndex + 1} of ${quiz.questions.length}',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppColors.charcoalMuted,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Question text
                  Text(
                    question.questionText,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Answer options
                  ...question.options.asMap().entries.map((entry) {
                    final optionIndex = entry.key;
                    final option = entry.value;
                    final letter = String.fromCharCode(
                      97 + optionIndex,
                    ); // a, b, c, d
                    final isSelected = _selectedAnswer == letter;
                    final isCorrect =
                        state.lastResult?.isCorrect == true && isSelected;
                    final isWrong =
                        state.lastResult?.isCorrect == false && isSelected;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildAnswerOption(
                        letter: letter.toUpperCase(),
                        text: option,
                        isSelected: isSelected,
                        isCorrect: isCorrect,
                        isWrong: isWrong,
                        showFeedback: _showFeedback,
                        onTap: () => _onAnswerSelected(letter),
                      ),
                    );
                  }),

                  // Feedback
                  if (_showFeedback && state.lastResult != null) ...[
                    const SizedBox(height: 16),
                    _buildFeedback(state.lastResult!),
                  ],
                ],
              ),
            ),
          ),
        ),

        // Next / Finish button
        if (_showFeedback)
          Padding(
            padding: const EdgeInsets.all(20),
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: state.isSubmitting
                    ? null
                    : isLastQuestion
                    ? () => ref.read(quizPlayerProvider.notifier).finishQuiz()
                    : _nextQuestion,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.terracotta,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: isLastQuestion
                    ? const Text(
                        'See Results',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    : const Text(
                        'Next Question',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildProgressBar(int current, int total) {
    final progress = (current + 1) / total;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: AppColors.parchmentDark,
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppColors.terracotta,
              ),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnswerOption({
    required String letter,
    required String text,
    required bool isSelected,
    required bool isCorrect,
    required bool isWrong,
    required bool showFeedback,
    required VoidCallback onTap,
  }) {
    Color borderColor = AppColors.charcoalMuted.withValues(alpha: 0.2);
    Color bgColor = Colors.white;
    Color letterColor = AppColors.charcoalMuted;

    if (showFeedback) {
      if (isCorrect) {
        borderColor = AppColors.savannahGreen;
        bgColor = AppColors.savannahGreenTint;
        letterColor = AppColors.savannahGreen;
      } else if (isWrong) {
        borderColor = AppColors.error;
        bgColor = AppColors.error.withValues(alpha: 0.1);
        letterColor = AppColors.error;
      }
    } else if (isSelected) {
      borderColor = AppColors.terracotta;
      bgColor = AppColors.terracottaTint;
      letterColor = AppColors.terracotta;
    }

    return GestureDetector(
      onTap: showFeedback ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 2),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: letterColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  letter,
                  style: TextStyle(
                    color: letterColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: AppColors.charcoal,
                ),
              ),
            ),
            if (showFeedback && isCorrect)
              const Icon(
                Icons.check_circle,
                color: AppColors.savannahGreen,
                size: 24,
              )
            else if (showFeedback && isWrong)
              const Icon(Icons.cancel, color: AppColors.error, size: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildFeedback(QuizAttemptResult result) {
    final isCorrect = result.isCorrect == true;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isCorrect
            ? AppColors.savannahGreenTint
            : AppColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCorrect ? AppColors.savannahGreen : AppColors.error,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isCorrect ? Icons.check_circle : Icons.info_outline,
                color: isCorrect ? AppColors.savannahGreen : AppColors.error,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                isCorrect ? 'Correct!' : 'Incorrect',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: isCorrect ? AppColors.savannahGreen : AppColors.error,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          if (result.explanation.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              result.explanation,
              style: TextStyle(
                color: AppColors.charcoal.withValues(alpha: 0.8),
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCompletionView(QuizPlayerState state) {
    final score = state.score ?? 0;
    final passed = score >= (state.quiz?.passingScore ?? 70);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Score circle
            Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: passed
                    ? AppColors.savannahGreenTint
                    : AppColors.terracottaTint,
                border: Border.all(
                  color: passed
                      ? AppColors.savannahGreen
                      : AppColors.terracotta,
                  width: 4,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '$score%',
                    style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w700,
                      color: passed
                          ? AppColors.savannahGreen
                          : AppColors.terracotta,
                    ),
                  ),
                  Text(
                    passed ? 'Passed!' : 'Try Again',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: passed
                          ? AppColors.savannahGreen
                          : AppColors.terracotta,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            Text(
              passed ? '🎉 Congratulations!' : '📚 Keep Learning!',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),

            if (passed && state.quiz != null)
              Text(
                'You earned ${state.quiz!.xpReward} XP',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppColors.ochre,
                  fontWeight: FontWeight.w600,
                ),
              ),

            const SizedBox(height: 32),

            // Action buttons
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: () {
                  ref.read(quizPlayerProvider.notifier).reset();
                  widget.onCompleted?.call(score);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.terracotta,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Continue',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
