from django.contrib import admin

from .models import (
    Badge,
    Certificate,
    Quiz,
    QuizAttempt,
    QuizQuestion,
    UserBadge,
    UserProfile,
)


class QuizQuestionInline(admin.TabularInline):
    model = QuizQuestion
    extra = 1
    ordering = ['order', 'id']


@admin.register(Quiz)
class QuizAdmin(admin.ModelAdmin):
    list_display = (
        'title',
        'story',
        'passing_score',
        'time_limit_minutes',
        'question_count',
        'is_published',
    )
    list_filter = ('is_published', 'created_at')
    search_fields = ('title', 'story__title')
    raw_id_fields = ('story',)
    inlines = [QuizQuestionInline]

    def question_count(self, obj):
        return obj.questions.count()
    question_count.short_description = 'Questions'


@admin.register(QuizAttempt)
class QuizAttemptAdmin(admin.ModelAdmin):
    list_display = (
        'id',
        'user',
        'quiz',
        'score',
        'passed',
        'xp_earned',
        'status',
        'started_at',
    )
    list_filter = ('status', 'passed', 'started_at')
    search_fields = ('user__username', 'quiz__title')
    raw_id_fields = ('user', 'quiz')
    readonly_fields = (
        'score',
        'correct_count',
        'total_questions',
        'passed',
        'xp_earned',
        'answers',
        'started_at',
        'completed_at',
        'time_taken_seconds',
    )


@admin.register(Badge)
class BadgeAdmin(admin.ModelAdmin):
    list_display = (
        'name',
        'emoji',
        'category',
        'xp_required',
        'stories_read_required',
        'quizzes_passed_required',
        'is_active',
        'is_secret',
    )
    list_filter = ('category', 'is_active', 'is_secret')
    search_fields = ('name', 'description')
    prepopulated_fields = {'slug': ('name',)}


@admin.register(UserBadge)
class UserBadgeAdmin(admin.ModelAdmin):
    list_display = ('user', 'badge', 'earned_at')
    raw_id_fields = ('user', 'badge')
    search_fields = ('user__username', 'badge__name')


@admin.register(UserProfile)
class UserProfileAdmin(admin.ModelAdmin):
    list_display = (
        'user',
        'level',
        'total_xp',
        'stories_read',
        'quizzes_passed',
        'current_streak',
    )
    list_filter = ('level',)
    search_fields = ('user__username',)
    raw_id_fields = ('user',)


@admin.register(Certificate)
class CertificateAdmin(admin.ModelAdmin):
    list_display = (
        'certificate_number',
        'user',
        'title',
        'certificate_type',
        'level_achieved',
        'issued_at',
    )
    list_filter = ('certificate_type', 'issued_at')
    search_fields = ('user__username', 'certificate_number', 'title')
    raw_id_fields = ('user',)
    readonly_fields = ('certificate_number', 'issued_at')
