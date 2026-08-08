import 'package:flutter_test/flutter_test.dart';

import 'package:african_teller/features/admin/models/analytics_models.dart';
import 'package:african_teller/features/admin/models/moderation_models.dart';

import 'support/admin_fixtures.dart';

void main() {
  group('UserStats.fromJson', () {
    test('parses a complete payload', () {
      final stats = UserStats.fromJson(adminUserStatsJson());

      expect(stats.totalUsers, 142);
      expect(stats.activeUsers30d, 58);
      expect(stats.usersByRole, {
        'visitor': 90,
        'contributor': 40,
        'institution_manager': 6,
        'admin': 6,
      });
      expect(stats.userGrowth, hasLength(3));
      expect(stats.userGrowth.first.date, '2026-07-01');
      expect(stats.userGrowth.first.count, 3);
      expect(stats.userGrowth.last.count, 0);
    });

    test('defaults when keys are missing', () {
      final stats = UserStats.fromJson(const {});

      expect(stats.totalUsers, 0);
      expect(stats.activeUsers30d, 0);
      expect(stats.usersByRole, isEmpty);
      expect(stats.userGrowth, isEmpty);
    });

    test('coerces numeric values to integers', () {
      final stats = UserStats.fromJson({
        'total_users': 142.0,
        'active_users_30d': 58.0,
        'users_by_role': {'visitor': 90.0, 'admin': 6.0},
      });

      expect(stats.totalUsers, 142);
      expect(stats.activeUsers30d, 58);
      expect(stats.usersByRole, {'visitor': 90, 'admin': 6});
    });
  });

  group('StoryStats.fromJson', () {
    test('parses stories, engagement, growth and top stories', () {
      final stats = StoryStats.fromJson(adminStoryStatsJson());

      expect(stats.totalStories, 87);
      expect(stats.storiesByStatus['published'], 74);
      expect(stats.storiesByStatus['pending'], 3);
      expect(stats.storiesByLanguage, {
        'en': 60,
        'fr': 10,
        'ful': 2,
        'dua': 1,
        'ewo': 1,
      });
      expect(stats.totalViews, 12500);
      expect(stats.totalLikes, 842);
      expect(stats.totalBookmarks, 391);
      expect(stats.totalShares, 156);
      expect(stats.pendingReview, 3);
      expect(stats.storyGrowth, hasLength(2));

      final top = stats.topStories;
      expect(top, hasLength(2));
      expect(top.first.id, 1);
      expect(top.first.title, 'The Wise Spider');
      expect(top.first.viewCount, 3200);
      expect(top.first.likeCount, 210);
      expect(top.first.bookmarkCount, 95);
      expect(top.first.shareCount, 44);
    });

    test('defaults when engagement section is missing', () {
      final stats = StoryStats.fromJson({'total_stories': 5});

      expect(stats.totalStories, 5);
      expect(stats.totalViews, 0);
      expect(stats.totalLikes, 0);
      expect(stats.topStories, isEmpty);
      expect(stats.pendingReview, 0);
    });
  });

  group('GamificationStats.fromJson', () {
    test('parses rates, leaderboard and quiz stats', () {
      final stats = GamificationStats.fromJson(adminGamificationJson());

      expect(stats.totalQuizzesTaken, 214);
      expect(stats.quizzesPassed, 168);
      expect(stats.passRate, 78.5);
      expect(stats.avgScore, 81.0);
      expect(stats.totalXpEarned, 12200);
      expect(stats.badgesEarned, 96);

      expect(stats.topUsers, hasLength(1));
      final user = stats.topUsers.first;
      expect(user.username, 'kemi');
      expect(user.totalXp, 1450);
      expect(user.level, 14);
      expect(user.storiesRead, 32);
      expect(user.quizzesPassed, 12);
      expect(user.currentStreak, 7);

      expect(stats.quizStats, hasLength(1));
      expect(stats.quizStats.first.title, 'Wise Spider Quiz');
      expect(stats.quizStats.first.attemptCount, 120);
      expect(stats.quizStats.first.passCount, 95);
    });

    test('parses integer rate values as doubles', () {
      final stats = GamificationStats.fromJson({
        'pass_rate': 80,
        'avg_score': 70,
      });

      expect(stats.passRate, 80.0);
      expect(stats.avgScore, 70.0);
      expect(stats.topUsers, isEmpty);
      expect(stats.quizStats, isEmpty);
    });
  });

  group('QRStats.fromJson', () {
    test('parses artifacts, scans and growth', () {
      final stats = QRStats.fromJson(adminQrJson());

      expect(stats.totalArtifacts, 45);
      expect(stats.publishedArtifacts, 40);
      expect(stats.totalScans, 987);
      expect(stats.uniqueScanners, 312);
      expect(stats.scanGrowth, hasLength(2));

      expect(stats.topArtifacts, hasLength(1));
      final artifact = stats.topArtifacts.first;
      expect(artifact.id, 1);
      expect(artifact.title, 'Bamoun Mask');
      expect(artifact.museumName, 'Musée du Cameroun');
      expect(artifact.scanCount, 210);
    });

    test('defaults when empty', () {
      final stats = QRStats.fromJson(const {});

      expect(stats.totalScans, 0);
      expect(stats.topArtifacts, isEmpty);
      expect(stats.scanGrowth, isEmpty);
    });
  });

  group('EngagementSummary.fromJson', () {
    test('parses totals and recent activity', () {
      final summary = EngagementSummary.fromJson(adminEngagementJson());

      expect(summary.totalReadingTime, 148200);
      expect(summary.completedReadings, 63);
      expect(summary.totalLikes, 842);
      expect(summary.totalBookmarks, 391);
      expect(summary.totalShares, 156);
      expect(summary.totalFlags, 4);
      expect(summary.unresolvedFlags, 1);

      final activity = summary.recentActivity;
      expect(activity.newUsers, 12);
      expect(activity.newStories, 4);
      expect(activity.quizAttempts, 36);
      expect(activity.qrScans, 58);
      expect(activity.shares, 19);
    });

    test('defaults when recent activity is missing', () {
      final summary = EngagementSummary.fromJson(const {});

      expect(summary.totalReadingTime, 0);
      expect(summary.unresolvedFlags, 0);
      expect(summary.recentActivity.newUsers, 0);
      expect(summary.recentActivity.qrScans, 0);
    });
  });

  group('FlaggedStory.fromJson', () {
    test('parses story and flag details', () {
      final story = FlaggedStory.fromJson(adminModerationQueueJson().first);

      expect(story.storyId, 11);
      expect(story.slug, 'the-wrong-spider');
      expect(story.title, 'The Wrong Spider');
      expect(story.status, 'published');
      expect(story.authorUsername, 'author1');
      expect(story.flags, hasLength(2));

      final flag = story.flags.first;
      expect(flag.id, 1);
      expect(flag.reason, 'cultural_inaccuracy');
      expect(flag.reasonDisplay, 'Cultural Inaccuracy');
      expect(flag.details, 'The story misrepresents traditional customs.');
      expect(flag.reporter, 'reader1');
      expect(flag.createdAt, '2026-07-01T10:00:00Z');
    });

    test('defaults when empty', () {
      final story = FlaggedStory.fromJson(const {});

      expect(story.storyId, 0);
      expect(story.title, '');
      expect(story.flags, isEmpty);
    });
  });

  group('DashboardSummary.fromJson', () {
    test('parses the complete dashboard payload', () {
      final summary = DashboardSummary.fromJson(adminDashboardJson());

      expect(summary.users.totalUsers, 142);
      expect(summary.stories.totalStories, 87);
      expect(summary.gamification.passRate, 78.5);
      expect(summary.qrCodes.totalScans, 987);
      expect(summary.engagement.completedReadings, 63);
    });

    test('defaults all sections for an empty payload', () {
      final summary = DashboardSummary.fromJson(const {});

      expect(summary.users.totalUsers, 0);
      expect(summary.stories.totalStories, 0);
      expect(summary.gamification.totalQuizzesTaken, 0);
      expect(summary.qrCodes.totalArtifacts, 0);
      expect(summary.engagement.totalLikes, 0);
    });

    test('defaults missing individual sections', () {
      final summary = DashboardSummary.fromJson({
        'users': {'total_users': 7},
      });

      expect(summary.users.totalUsers, 7);
      expect(summary.stories.totalStories, 0);
      expect(summary.engagement.totalShares, 0);
    });
  });
}
