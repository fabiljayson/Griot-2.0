"""
Analytics service: aggregated platform-wide statistics for the admin dashboard.

Provides functions to compute:
- User statistics (total, by role, growth over time)
- Story statistics (total, by status, engagement metrics)
- Gamification statistics (quizzes taken, badges earned, top users)
- QR code statistics (scans, popular artifacts)
- Engagement metrics (shares, likes, bookmarks, reading time)
"""
from datetime import timedelta
from collections import Counter

from django.contrib.auth import get_user_model
from django.db.models import Count, Avg, Sum, Q, F
from django.utils import timezone

from stories.models import (
    Story, StoryCategory, StoryBookmark, StoryLike,
    StoryShare, StoryFlag, ReadingProgress,
)
from gamification.models import (
    Quiz, QuizAttempt, Badge, UserBadge, UserProfile, Certificate,
)
from qr_codes.models import Artifact, QRCodeScan

User = get_user_model()


def daily_growth(queryset, date_field: str, days: int = 30):
    """Count rows per day for the last [days] days, in a single query.

    The four growth series on this dashboard were each written as a loop of 30
    `COUNT(*)` queries — 120 round trips to render one page, growing linearly
    with the window. Grouping once by date and filling the gaps in Python gives
    the identical series from one query per series.

    `__date` extraction is done by the database either way, so this does not
    move work out of the engine; it just stops asking it the same question 30
    times.
    """
    today = timezone.now().date()
    start = today - timedelta(days=days - 1)

    counts = {
        row[0]: row[1]
        for row in queryset.filter(
            **{f'{date_field}__date__gte': start}
        ).values_list(f'{date_field}__date').annotate(count=Count('id'))
    }

    series = []
    for offset in range(days):
        day = start + timedelta(days=offset)
        series.append({
            'date': day.isoformat(),
            'count': counts.get(day, 0),
        })
    return series


def get_user_stats():
    """Aggregate user statistics."""
    now = timezone.now()
    thirty_days_ago = now - timedelta(days=30)
    seven_days_ago = now - timedelta(days=7)

    total_users = User.objects.count()
    active_users_30d = User.objects.filter(
        last_login__gte=thirty_days_ago
    ).count()

    # Users by role
    users_by_role = dict(
        User.objects.values_list('role')
        .annotate(count=Count('id'))
        .order_by('role')
    )

    # User growth (last 30 days, daily)
    user_growth = daily_growth(User.objects.all(), 'date_joined')

    return {
        'total_users': total_users,
        'active_users_30d': active_users_30d,
        'users_by_role': users_by_role,
        'user_growth': user_growth,
    }


def get_story_stats():
    """Aggregate story statistics."""
    total_stories = Story.objects.count()

    # Stories by status
    stories_by_status = dict(
        Story.objects.values_list('status')
        .annotate(count=Count('id'))
        .order_by('status')
    )

    # Stories by language
    stories_by_language = dict(
        Story.objects.filter(status=Story.Status.PUBLISHED)
        .values_list('language')
        .annotate(count=Count('id'))
        .order_by('-count')
    )

    # Engagement totals
    engagement = Story.objects.filter(
        status=Story.Status.PUBLISHED
    ).aggregate(
        total_views=Sum('view_count'),
        total_likes=Sum('like_count'),
        total_bookmarks=Sum('bookmark_count'),
        total_shares=Sum('share_count'),
    )

    # Top stories by views
    top_stories = list(
        Story.objects.filter(status=Story.Status.PUBLISHED)
        .order_by('-view_count')[:10]
        .values('id', 'slug', 'title', 'view_count', 'like_count', 'bookmark_count', 'share_count')
    )

    # Stories published over time (last 30 days)
    story_growth = daily_growth(Story.objects.all(), 'published_at')

    # Pending stories (need review)
    pending_stories = Story.objects.filter(
        status=Story.Status.PENDING
    ).count()

    return {
        'total_stories': total_stories,
        'stories_by_status': stories_by_status,
        'stories_by_language': stories_by_language,
        'engagement': {
            'total_views': engagement['total_views'] or 0,
            'total_likes': engagement['total_likes'] or 0,
            'total_bookmarks': engagement['total_bookmarks'] or 0,
            'total_shares': engagement['total_shares'] or 0,
        },
        'top_stories': top_stories,
        'story_growth': story_growth,
        'pending_review': pending_stories,
    }


def get_gamification_stats():
    """Aggregate gamification statistics."""
    total_quizzes_taken = QuizAttempt.objects.filter(
        status=QuizAttempt.Status.COMPLETED
    ).count()

    quizzes_passed = QuizAttempt.objects.filter(
        status=QuizAttempt.Status.COMPLETED,
        passed=True,
    ).count()

    avg_score = QuizAttempt.objects.filter(
        status=QuizAttempt.Status.COMPLETED
    ).aggregate(avg=Avg('score'))['avg'] or 0

    # Platform-wide XP, read from the profiles.
    #
    # This used to sum `QuizAttempt.xp_earned` over passing attempts only,
    # which meant the "XP earned" tile sat directly above a leaderboard reading
    # `UserProfile.total_xp` and the two disagreed on the same screen — 0 against
    # ~2,000 per user. Both numbers were true about different things; only one
    # of them is what "XP earned" means to an operator. The quiz-only figure is
    # still reported, under a name that says so.
    total_xp_earned = UserProfile.objects.aggregate(
        total=Sum('total_xp')
    )['total'] or 0

    quiz_xp_earned = QuizAttempt.objects.filter(
        status=QuizAttempt.Status.COMPLETED,
        passed=True,
    ).aggregate(total=Sum('xp_earned'))['total'] or 0

    # Badges earned
    badges_earned = UserBadge.objects.count()

    # Top users by XP
    top_users = list(
        UserProfile.objects.select_related('user')
        .order_by('-total_xp')[:10]
        .values(
            'user__username', 'total_xp', 'level',
            'stories_read', 'quizzes_passed', 'current_streak',
        )
    )

    # Quiz completion rate by quiz
    quiz_stats = list(
        Quiz.objects.annotate(
            attempt_count=Count('attempts', filter=Q(attempts__status='completed')),
            pass_count=Count('attempts', filter=Q(
                attempts__status='completed', attempts__passed=True
            )),
        )
        .values('id', 'title', 'attempt_count', 'pass_count')
        .order_by('-attempt_count')[:10]
    )

    return {
        'total_quizzes_taken': total_quizzes_taken,
        'quizzes_passed': quizzes_passed,
        'pass_rate': round(quizzes_passed / total_quizzes_taken * 100, 1) if total_quizzes_taken > 0 else 0,
        'avg_score': round(avg_score, 1),
        'total_xp_earned': total_xp_earned,
        # The subset of the above that came from quizzes, kept because it is a
        # genuinely different question from "how much XP has been handed out".
        'quiz_xp_earned': quiz_xp_earned,
        'badges_earned': badges_earned,
        'top_users': top_users,
        'quiz_stats': quiz_stats,
    }


def get_qr_stats():
    """Aggregate QR code and artifact statistics."""
    total_artifacts = Artifact.objects.count()
    published_artifacts = Artifact.objects.filter(
        is_published=True
    ).count()

    total_scans = QRCodeScan.objects.count()

    # Unique scanners
    unique_scanners = QRCodeScan.objects.values('user').distinct().count()

    # Scans by day (last 30 days)
    scan_growth = daily_growth(QRCodeScan.objects.all(), 'created_at')

    # Top artifacts by scan count
    top_artifacts = list(
        Artifact.objects.filter(is_published=True)
        .annotate(scan_count=Count('scans'))
        .order_by('-scan_count')[:10]
        .values('id', 'title', 'museum_name', 'scan_count')
    )

    return {
        'total_artifacts': total_artifacts,
        'published_artifacts': published_artifacts,
        'total_scans': total_scans,
        'unique_scanners': unique_scanners,
        'scan_growth': scan_growth,
        'top_artifacts': top_artifacts,
    }


def get_engagement_summary():
    """High-level engagement summary."""
    now = timezone.now()
    thirty_days_ago = now - timedelta(days=30)
    seven_days_ago = now - timedelta(days=7)

    # Reading activity
    total_reading_time = ReadingProgress.objects.aggregate(
        total=Sum('last_read_position')
    )['total'] or 0

    completed_readings = ReadingProgress.objects.filter(
        completed=True
    ).count()

    # Social activity
    total_likes = StoryLike.objects.count()
    total_bookmarks = StoryBookmark.objects.count()
    total_shares = StoryShare.objects.count()
    total_flags = StoryFlag.objects.count()
    unresolved_flags = StoryFlag.objects.filter(resolved=False).count()

    # Activity in last 7 days
    recent_activity = {
        'new_users': User.objects.filter(date_joined__gte=seven_days_ago).count(),
        'new_stories': Story.objects.filter(created_at__gte=seven_days_ago).count(),
        'quiz_attempts': QuizAttempt.objects.filter(
            started_at__gte=seven_days_ago
        ).count(),
        'qr_scans': QRCodeScan.objects.filter(
            created_at__gte=seven_days_ago
        ).count(),
        'shares': StoryShare.objects.filter(
            created_at__gte=seven_days_ago
        ).count(),
    }

    return {
        'total_reading_time': total_reading_time,
        'completed_readings': completed_readings,
        'total_likes': total_likes,
        'total_bookmarks': total_bookmarks,
        'total_shares': total_shares,
        'total_flags': total_flags,
        'unresolved_flags': unresolved_flags,
        'recent_activity_7d': recent_activity,
    }


def get_dashboard_summary():
    """Complete dashboard summary combining all analytics."""
    return {
        'users': get_user_stats(),
        'stories': get_story_stats(),
        'gamification': get_gamification_stats(),
        'qr_codes': get_qr_stats(),
        'engagement': get_engagement_summary(),
    }
