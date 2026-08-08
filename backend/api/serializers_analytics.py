"""
Serializers for the admin analytics API endpoints.
"""
from rest_framework import serializers


class UserStatsSerializer(serializers.Serializer):
    """User statistics."""
    total_users = serializers.IntegerField()
    active_users_30d = serializers.IntegerField()
    users_by_role = serializers.DictField()
    user_growth = serializers.ListField()


class StoryStatsSerializer(serializers.Serializer):
    """Story statistics."""
    total_stories = serializers.IntegerField()
    stories_by_status = serializers.DictField()
    stories_by_language = serializers.DictField()
    engagement = serializers.DictField()
    top_stories = serializers.ListField()
    story_growth = serializers.ListField()
    pending_review = serializers.IntegerField()


class GamificationStatsSerializer(serializers.Serializer):
    """Gamification statistics."""
    total_quizzes_taken = serializers.IntegerField()
    quizzes_passed = serializers.IntegerField()
    pass_rate = serializers.FloatField()
    avg_score = serializers.FloatField()
    total_xp_earned = serializers.IntegerField()
    badges_earned = serializers.IntegerField()
    top_users = serializers.ListField()
    quiz_stats = serializers.ListField()


class QRStatsSerializer(serializers.Serializer):
    """QR code and artifact statistics."""
    total_artifacts = serializers.IntegerField()
    published_artifacts = serializers.IntegerField()
    total_scans = serializers.IntegerField()
    unique_scanners = serializers.IntegerField()
    scan_growth = serializers.ListField()
    top_artifacts = serializers.ListField()


class EngagementSummarySerializer(serializers.Serializer):
    """High-level engagement summary."""
    total_reading_time = serializers.IntegerField()
    completed_readings = serializers.IntegerField()
    total_likes = serializers.IntegerField()
    total_bookmarks = serializers.IntegerField()
    total_shares = serializers.IntegerField()
    total_flags = serializers.IntegerField()
    unresolved_flags = serializers.IntegerField()
    recent_activity_7d = serializers.DictField()


class DashboardSummarySerializer(serializers.Serializer):
    """Complete dashboard summary."""
    users = UserStatsSerializer()
    stories = StoryStatsSerializer()
    gamification = GamificationStatsSerializer()
    qr_codes = QRStatsSerializer()
    engagement = EngagementSummarySerializer()
