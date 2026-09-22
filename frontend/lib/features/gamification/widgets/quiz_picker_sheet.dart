import 'package:flutter/material.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_spacing.dart';
import '../services/gamification_api_service.dart';

/// Bottom sheet offering the quizzes linked to a story.
///
/// Only shown when a story has more than one quiz (e.g. an English and a French
/// edition), so the reader's "Take Quiz" CTA always resolves to something
/// unambiguous.
class QuizPickerSheet extends StatelessWidget {
  const QuizPickerSheet({super.key, required this.quizzes});

  final List<QuizModel> quizzes;

  /// Show the picker; resolves to the chosen quiz or null.
  static Future<QuizModel?> show(BuildContext context, List<QuizModel> quizzes) {
    return showModalBottomSheet<QuizModel>(
      context: context,
      showDragHandle: true,
      builder: (_) => QuizPickerSheet(quizzes: quizzes),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              0,
              AppSpacing.xl,
              AppSpacing.sm,
            ),
            child: Text('Choose a quiz', style: theme.textTheme.titleLarge),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: quizzes.length,
              itemBuilder: (context, index) {
                final quiz = quizzes[index];
                return ListTile(
                  leading: const Icon(AppIcons.quiz_outlined),
                  title: Text(quiz.title),
                  subtitle: Text(
                    '${quiz.questionCount} questions • ${quiz.xpReward} XP',
                  ),
                  trailing: const Icon(AppIcons.chevron_right, size: 14),
                  onTap: () => Navigator.of(context).pop(quiz),
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
      ),
    );
  }
}
