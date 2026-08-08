import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../providers/gamification_provider.dart';
import '../services/gamification_api_service.dart';
import '../widgets/badge_card.dart';
import '../widgets/progress_bar.dart';
import '../widgets/quiz_player_widget.dart';

/// Main gamification hub showing profile, badges, quizzes, and leaderboard.
class GamificationScreen extends ConsumerWidget {
  const GamificationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(gamificationProfileProvider);
    final badgesAsync = ref.watch(badgesProvider);
    final quizzesAsync = ref.watch(quizzesProvider);

    return Scaffold(
      backgroundColor: AppColors.parchment,
      appBar: AppBar(
        title: const Text('Achievements'),
        backgroundColor: AppColors.parchment,
        elevation: 0,
        foregroundColor: AppColors.charcoal,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(gamificationProfileProvider);
          ref.invalidate(badgesProvider);
          ref.invalidate(quizzesProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Profile & Level Progress
            profileAsync.when(
              data: (profile) => LevelProgressBar(
                level: profile.level,
                totalXp: profile.totalXp,
                xpProgress: profile.xpProgress,
                xpForNextLevel: profile.xpForNextLevel,
                currentStreak: profile.currentStreak,
              ),
              loading: () => const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 24),

            // Stats Row
            profileAsync.when(
              data: (profile) => _buildStatsRow(profile),
              loading: () => const SizedBox.shrink(),
              error: (e, _) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 24),

            // Badges Section
            Text('Badges', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            badgesAsync.when(
              data: (badges) => _buildBadgesGrid(badges),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => const Text('Failed to load badges'),
            ),
            const SizedBox(height: 24),

            // Quizzes Section
            Text('Quizzes', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            quizzesAsync.when(
              data: (quizzes) => _buildQuizzesList(context, quizzes),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => const Text('Failed to load quizzes'),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow(GamificationProfileModel profile) {
    return Row(
      children: [
        _buildStatCard('📖', '${profile.storiesRead}', 'Stories'),
        const SizedBox(width: 8),
        _buildStatCard('🧠', '${profile.quizzesPassed}', 'Quizzes'),
        const SizedBox(width: 8),
        _buildStatCard('🏆', '${profile.badgesCount}', 'Badges'),
      ],
    );
  }

  Widget _buildStatCard(String emoji, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.charcoalMuted.withValues(alpha: 0.1),
          ),
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 24)),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.charcoal,
              ),
            ),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: AppColors.charcoalMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBadgesGrid(List<BadgeModel> badges) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.85,
      ),
      itemCount: badges.length,
      itemBuilder: (context, index) {
        return BadgeCard(badge: badges[index]);
      },
    );
  }

  Widget _buildQuizzesList(BuildContext context, List quizzes) {
    if (quizzes.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Text(
            'No quizzes available yet.\nRead more stories to unlock quizzes!',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.charcoalMuted),
          ),
        ),
      );
    }

    return Column(
      children: quizzes.map((quiz) {
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.charcoalMuted.withValues(alpha: 0.1),
            ),
          ),
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.terracottaTint,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Text('🧠', style: TextStyle(fontSize: 24)),
              ),
            ),
            title: Text(
              quiz.title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              '${quiz.questionCount} questions • ${quiz.xpReward} XP',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            trailing: quiz.bestScore != null
                ? Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: quiz.bestScore! >= quiz.passingScore
                          ? AppColors.savannahGreenTint
                          : AppColors.parchmentDark,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Best: ${quiz.bestScore}%',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: quiz.bestScore! >= quiz.passingScore
                            ? AppColors.savannahGreen
                            : AppColors.charcoalMuted,
                      ),
                    ),
                  )
                : const Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: AppColors.charcoalMuted,
                  ),
            onTap: () {
              _openQuiz(context, quiz.id);
            },
          ),
        );
      }).toList(),
    );
  }

  void _openQuiz(BuildContext context, int quizId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Quiz')),
          body: QuizPlayerWidget(quizId: quizId),
        ),
      ),
    );
  }
}
