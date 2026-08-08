from django.conf import settings
from django.db import models
from django.utils import timezone


class Quiz(models.Model):
    """A quiz tied to a specific story.

    Quizzes test comprehension and cultural knowledge after reading a story.
    Each quiz has multiple questions with one correct answer.
    """

    story = models.OneToOneField(
        'stories.Story',
        on_delete=models.CASCADE,
        related_name='quiz',
    )
    title = models.CharField(
        max_length=200,
        blank=True,
        default='',
        help_text='Quiz title (defaults to story title).',
    )
    description = models.TextField(
        blank=True,
        default='',
        help_text='Brief description of what the quiz covers.',
    )
    passing_score = models.PositiveIntegerField(
        default=70,
        help_text='Minimum percentage to pass (0-100).',
    )
    time_limit_minutes = models.PositiveIntegerField(
        default=0,
        help_text='Time limit in minutes (0 = no limit).',
    )
    is_published = models.BooleanField(default=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return f'Quiz: {self.title or self.story.title}'

    @property
    def question_count(self):
        return self.questions.count()

    @property
    def xp_reward(self):
        """XP awarded for passing this quiz."""
        return 50 + (self.question_count * 10)


class QuizQuestion(models.Model):
    """A single question in a quiz."""

    class Difficulty(models.TextChoices):
        EASY = 'easy', 'Easy'
        MEDIUM = 'medium', 'Medium'
        HARD = 'hard', 'Hard'

    quiz = models.ForeignKey(
        Quiz,
        on_delete=models.CASCADE,
        related_name='questions',
    )
    question_text = models.TextField(
        help_text='The question text.',
    )
    option_a = models.CharField(max_length=300)
    option_b = models.CharField(max_length=300)
    option_c = models.CharField(max_length=300)
    option_d = models.CharField(max_length=300, blank=True, default='')

    correct_answer = models.CharField(
        max_length=1,
        choices=[('a', 'A'), ('b', 'B'), ('c', 'C'), ('d', 'D')],
        help_text='Which option is correct.',
    )
    explanation = models.TextField(
        blank=True,
        default='',
        help_text='Explanation shown after answering.',
    )
    difficulty = models.CharField(
        max_length=10,
        choices=Difficulty.choices,
        default=Difficulty.MEDIUM,
    )
    order = models.PositiveIntegerField(default=0)

    class Meta:
        ordering = ['order', 'id']

    def __str__(self):
        return f'{self.quiz.title}: {self.question_text[:60]}'


class QuizAttempt(models.Model):
    """A user's attempt at a quiz."""

    class Status(models.TextChoices):
        IN_PROGRESS = 'in_progress', 'In Progress'
        COMPLETED = 'completed', 'Completed'
        TIMED_OUT = 'timed_out', 'Timed Out'

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='quiz_attempts',
    )
    quiz = models.ForeignKey(
        Quiz,
        on_delete=models.CASCADE,
        related_name='attempts',
    )

    # Results
    score = models.PositiveIntegerField(
        default=0,
        help_text='Score as percentage (0-100).',
    )
    correct_count = models.PositiveIntegerField(default=0)
    total_questions = models.PositiveIntegerField(default=0)
    passed = models.BooleanField(default=False)
    xp_earned = models.PositiveIntegerField(default=0)

    # Status
    status = models.CharField(
        max_length=20,
        choices=Status.choices,
        default=Status.IN_PROGRESS,
    )

    # Answers (JSON array of {question_id, selected_answer, is_correct})
    answers = models.JSONField(
        default=list,
        blank=True,
        help_text='JSON array of answer records.',
    )

    # Timing
    started_at = models.DateTimeField(auto_now_add=True)
    completed_at = models.DateTimeField(null=True, blank=True)
    time_taken_seconds = models.PositiveIntegerField(default=0)

    class Meta:
        ordering = ['-started_at']
        indexes = [
            models.Index(fields=['user', '-started_at']),
            models.Index(fields=['quiz', '-started_at']),
        ]

    def __str__(self):
        return f'{self.user.username} - {self.quiz} ({self.score}%)'

    def calculate_score(self):
        """Calculate score from answers."""
        if not self.answers:
            return 0
        correct = sum(1 for a in self.answers if a.get('is_correct'))
        total = len(self.answers)
        self.correct_count = correct
        self.total_questions = total
        self.score = round((correct / total) * 100) if total > 0 else 0
        self.passed = self.score >= self.quiz.passing_score
        return self.score


class Badge(models.Model):
    """An achievement badge users can earn."""

    class Category(models.TextChoices):
        READING = 'reading', 'Reading'
        QUIZ = 'quiz', 'Quiz Master'
        SOCIAL = 'social', 'Social'
        EXPLORATION = 'exploration', 'Exploration'
        SPECIAL = 'special', 'Special'

    name = models.CharField(max_length=100, unique=True)
    slug = models.SlugField(max_length=120, unique=True)
    description = models.TextField()
    emoji = models.CharField(
        max_length=10,
        default='🏆',
        help_text='Emoji icon for the badge.',
    )
    category = models.CharField(
        max_length=20,
        choices=Category.choices,
        default=Category.READING,
    )

    # Requirements to earn
    xp_required = models.PositiveIntegerField(
        default=0,
        help_text='XP required to earn this badge.',
    )
    stories_read_required = models.PositiveIntegerField(
        default=0,
        help_text='Number of stories to read.',
    )
    quizzes_passed_required = models.PositiveIntegerField(
        default=0,
        help_text='Number of quizzes to pass.',
    )

    # Visual
    color = models.CharField(
        max_length=7,
        default='#C85A32',
        help_text='Badge color (hex).',
    )
    icon_url = models.URLField(
        blank=True,
        default='',
        help_text='Custom badge icon URL.',
    )

    is_active = models.BooleanField(default=True)
    is_secret = models.BooleanField(
        default=False,
        help_text='Hidden until earned.',
    )

    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['category', 'xp_required']

    def __str__(self):
        return f'{self.emoji} {self.name}'


class UserBadge(models.Model):
    """Badge earned by a user."""

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='user_badges',
    )
    badge = models.ForeignKey(
        Badge,
        on_delete=models.CASCADE,
        related_name='earned_by',
    )
    earned_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ('user', 'badge')
        ordering = ['-earned_at']

    def __str__(self):
        return f'{self.user.username} earned {self.badge.name}'


class UserProfile(models.Model):
    """Extended user profile for gamification stats."""

    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='gamification_profile',
    )

    # XP & Level
    total_xp = models.PositiveIntegerField(default=0)
    level = models.PositiveIntegerField(default=1)

    # Stats
    stories_read = models.PositiveIntegerField(default=0)
    stories_completed = models.PositiveIntegerField(default=0)
    quizzes_passed = models.PositiveIntegerField(default=0)
    total_quiz_xp = models.PositiveIntegerField(default=0)

    # Streaks
    current_streak = models.PositiveIntegerField(default=0)
    longest_streak = models.PositiveIntegerField(default=0)
    last_active_date = models.DateField(null=True, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name_plural = 'User profiles'

    def __str__(self):
        return f'{self.user.username} — Level {self.level} ({self.total_xp} XP)'

    @property
    def xp_for_next_level(self):
        """XP needed to reach the next level."""
        return self.level * 100

    @property
    def xp_progress(self):
        """Progress toward next level (0.0 to 1.0)."""
        needed = self.xp_for_next_level
        if needed == 0:
            return 1.0
        current_level_xp = (self.level - 1) * 100
        progress = (self.total_xp - current_level_xp) / needed
        return min(1.0, max(0.0, progress))

    def add_xp(self, amount):
        """Add XP and check for level up."""
        self.total_xp += amount
        # Level up calculation
        while self.total_xp >= self.level * 100:
            self.level += 1
        self.save(update_fields=['total_xp', 'level', 'updated_at'])

    def update_streak(self):
        """Update the daily reading streak."""
        today = timezone.now().date()
        if self.last_active_date == today:
            return  # Already counted today

        if self.last_active_date == today - timezone.timedelta(days=1):
            self.current_streak += 1
        elif self.last_active_date != today:
            self.current_streak = 1

        self.longest_streak = max(self.longest_streak, self.current_streak)
        self.last_active_date = today
        self.save(update_fields=[
            'current_streak', 'longest_streak', 'last_active_date', 'updated_at',
        ])


class Certificate(models.Model):
    """Heritage certificate earned by completing milestones."""

    class Type(models.TextChoices):
        READING = 'reading', 'Reading Achievement'
        QUIZ = 'quiz', 'Quiz Mastery'
        EXPLORER = 'explorer', 'Cultural Explorer'
        CONTRIBUTOR = 'contributor', 'Heritage Contributor'

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='certificates',
    )
    certificate_type = models.CharField(
        max_length=20,
        choices=Type.choices,
    )
    title = models.CharField(max_length=200)
    description = models.TextField()
    issued_at = models.DateTimeField(auto_now_add=True)

    # Certificate details
    certificate_number = models.CharField(
        max_length=50,
        unique=True,
        blank=True,
    )
    stories_read = models.PositiveIntegerField(default=0)
    quizzes_passed = models.PositiveIntegerField(default=0)
    level_achieved = models.PositiveIntegerField(default=1)

    # PDF generation
    pdf_url = models.URLField(
        blank=True,
        default='',
        help_text='URL to the generated PDF certificate.',
    )

    class Meta:
        ordering = ['-issued_at']

    def __str__(self):
        return f'{self.title} — {self.user.username}'

    def save(self, *args, **kwargs):
        if not self.certificate_number:
            import uuid
            self.certificate_number = f'AT-{uuid.uuid4().hex[:8].upper()}'
        super().save(*args, **kwargs)
