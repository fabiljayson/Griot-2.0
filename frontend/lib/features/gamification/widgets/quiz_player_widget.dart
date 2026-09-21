import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_components.dart';
import '../../../core/widgets/griot_loader.dart';
import '../providers/gamification_provider.dart';
import '../services/gamification_api_service.dart';

/// Interactive quiz player with instant feedback.
///
///   - Progress indicator
///   - Animated question transitions
///   - Color-coded answer feedback (correct/incorrect)
///   - Explanation reveal
///   - Score summary at completion
///
/// Every colour comes from the active [ColorScheme]. The previous version
/// painted answer text in `AppColors.charcoal` on `scheme.surface`, which in
/// dark mode meant near-black text on a dark indigo card — i.e. invisible.
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

    // Load and start the quiz.
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final state = ref.watch(quizPlayerProvider);

    if (state.isLoading) {
      return const GriotLoadingState(label: 'Loading quiz');
    }

    if (state.errorMessage != null && state.quiz == null) {
      return ErrorState(
        message: state.errorMessage!,
        title: 'Could not load this quiz',
        onRetry: () =>
            ref.read(quizPlayerProvider.notifier).startQuiz(widget.quizId),
      );
    }

    if (state.isCompleted) {
      return _buildCompletionView(state);
    }

    if (state.quiz == null || state.quiz!.questions.isEmpty) {
      return const EmptyState(
        title: 'No questions available',
        subtitle: 'This quiz has no questions yet. Please try again later.',
        icon: AppIcons.quiz_outlined,
      );
    }

    final quiz = state.quiz!;
    final questionIndex = state.currentQuestionIndex;
    final question = quiz.questions[questionIndex];
    final isLastQuestion = questionIndex >= quiz.questions.length - 1;

    return Column(
      children: [
        _buildProgressBar(questionIndex, quiz.questions.length),

        Expanded(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Question ${questionIndex + 1} of ${quiz.questions.length}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),

                  Text(
                    question.questionText,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  ...question.options.asMap().entries.map((entry) {
                    final optionIndex = entry.key;
                    final option = entry.value;
                    // a, b, c, d — the letters the API expects.
                    final letter = String.fromCharCode(97 + optionIndex);
                    final isSelected = _selectedAnswer == letter;
                    final isCorrect =
                        state.lastResult?.isCorrect == true && isSelected;
                    final isWrong =
                        state.lastResult?.isCorrect == false && isSelected;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: _AnswerOption(
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

                  if (_showFeedback && state.lastResult != null) ...[
                    const SizedBox(height: AppSpacing.lg),
                    _buildFeedback(state.lastResult!),
                  ],
                ],
              ),
            ),
          ),
        ),

        if (_showFeedback)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: SizedBox(
              width: double.infinity,
              height: AppSizes.buttonHeight,
              child: FilledButton(
                onPressed: state.isSubmitting
                    ? null
                    : isLastQuestion
                    ? () => ref.read(quizPlayerProvider.notifier).finishQuiz()
                    : _nextQuestion,
                child: state.isSubmitting
                    ? const GriotLoader.inline()
                    : Text(isLastQuestion ? 'See Results' : 'Next Question'),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildProgressBar(int current, int total) {
    final progress = total == 0 ? 0.0 : (current + 1) / total;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.xl,
        0,
      ),
      child: ProgressRow(fraction: progress, showValue: false),
    );
  }

  Widget _buildFeedback(QuizAttemptResult result) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isCorrect = result.isCorrect == true;

    final background = isCorrect
        ? scheme.tertiaryContainer
        : scheme.errorContainer;
    final foreground = isCorrect
        ? scheme.onTertiaryContainer
        : scheme.onErrorContainer;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: foreground.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FaIcon(
                isCorrect ? AppIcons.check_circle : AppIcons.info_outline,
                color: foreground,
                size: 18,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                isCorrect ? 'Correct!' : 'Incorrect',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (result.explanation.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              result.explanation,
              style: theme.textTheme.bodyMedium?.copyWith(color: foreground),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCompletionView(QuizPlayerState state) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final score = state.score ?? 0;
    final passed = score >= (state.quiz?.passingScore ?? 70);

    final background = passed
        ? scheme.tertiaryContainer
        : scheme.secondaryContainer;
    final foreground = passed
        ? scheme.onTertiaryContainer
        : scheme.onSecondaryContainer;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.section),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: background,
                border: Border.all(color: foreground, width: 4),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '$score%',
                    style: theme.textTheme.displaySmall?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    passed ? 'Passed!' : 'Try Again',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            Text(
              passed ? 'Congratulations!' : 'Keep Learning!',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),

            if (passed && state.quiz != null)
              Text(
                'You earned ${state.quiz!.xpReward} XP',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: scheme.secondary,
                  fontWeight: FontWeight.w600,
                ),
              ),

            const SizedBox(height: AppSpacing.section),

            SizedBox(
              width: double.infinity,
              height: AppSizes.buttonHeight,
              child: FilledButton(
                onPressed: () {
                  ref.read(quizPlayerProvider.notifier).reset();
                  widget.onCompleted?.call(score);
                },
                child: const Text('Continue'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One selectable answer.
///
/// The option supplies its own background in every state, so its label stays
/// legible on both themes: unselected options sit on the card surface with
/// `onSurface` ink, and the selected/correct/incorrect states use the matching
/// Material container pair.
class _AnswerOption extends StatelessWidget {
  const _AnswerOption({
    required this.letter,
    required this.text,
    required this.isSelected,
    required this.isCorrect,
    required this.isWrong,
    required this.showFeedback,
    required this.onTap,
  });

  final String letter;
  final String text;
  final bool isSelected;
  final bool isCorrect;
  final bool isWrong;
  final bool showFeedback;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Color background = scheme.surface;
    Color border = scheme.outline;
    Color ink = scheme.onSurface;

    if (showFeedback && isCorrect) {
      background = scheme.tertiaryContainer;
      border = scheme.tertiary;
      ink = scheme.onTertiaryContainer;
    } else if (showFeedback && isWrong) {
      background = scheme.errorContainer;
      border = scheme.error;
      ink = scheme.onErrorContainer;
    } else if (isSelected) {
      background = scheme.primaryContainer;
      border = scheme.primary;
      ink = scheme.onPrimaryContainer;
    }

    return GestureDetector(
      onTap: showFeedback ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(color: border, width: 2),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: ink.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(AppRadius.chip),
              ),
              child: Text(
                letter,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: ink,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            if (showFeedback && isCorrect)
              FaIcon(AppIcons.check_circle, color: scheme.tertiary, size: 22)
            else if (showFeedback && isWrong)
              FaIcon(AppIcons.cancel, color: scheme.error, size: 22),
          ],
        ),
      ),
    );
  }
}
