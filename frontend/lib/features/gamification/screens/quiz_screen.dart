import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../providers/gamification_provider.dart';
import '../services/gamification_api_service.dart';
import '../widgets/quiz_player_widget.dart';

/// Full-screen quiz route.
///
/// Existed only as an inline `Scaffold` inside the Achievements tab, which is
/// why the story reader's "Take Quiz" CTA had nothing to navigate to and was
/// left as an empty callback. It is now a real, reachable route.
class QuizScreen extends ConsumerWidget {
  const QuizScreen({super.key, required this.quiz});

  final QuizModel quiz;

  /// Push the quiz route for [quiz].
  static Future<void> open(BuildContext context, QuizModel quiz) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => QuizScreen(quiz: quiz)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          quiz.title.isEmpty ? 'Quiz' : quiz.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Column(
        children: [
          if (quiz.storyTitle.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.md,
                AppSpacing.xl,
                0,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      quiz.storyTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  Text(
                    '${quiz.xpReward} XP • pass ${quiz.passingScore}%',
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          Expanded(
            child: QuizPlayerWidget(
              quizId: quiz.id,
              onCompleted: (_) {
                // Refresh the profile/badge state after a finished attempt.
                ref.invalidate(gamificationProfileProvider);
                ref.invalidate(badgesProvider);
              },
            ),
          ),
        ],
      ),
    );
  }
}
