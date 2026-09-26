import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_provider.dart';
import '../services/gamification_api_service.dart';
import '../services/quiz_api_service.dart';

/// State for quiz playing.
class QuizPlayerState {
  const QuizPlayerState({
    this.quiz,
    this.currentQuestionIndex = 0,
    this.answers = const {},
    this.lastResult,
    this.isLoading = false,
    this.isSubmitting = false,
    this.isCompleted = false,
    this.score,
    this.errorMessage,
  });

  final QuizModel? quiz;
  final int currentQuestionIndex;
  final Map<int, String> answers; // questionId -> selectedAnswer
  final QuizAttemptResult? lastResult;
  final bool isLoading;
  final bool isSubmitting;
  final bool isCompleted;
  final int? score;
  final String? errorMessage;

  QuizModel? get currentQuestion => quiz;

  bool get hasMoreQuestions =>
      quiz != null && currentQuestionIndex < (quiz!.questions.length - 1);

  bool get allAnswered =>
      quiz != null && answers.length >= quiz!.questions.length;

  QuizPlayerState copyWith({
    QuizModel? quiz,
    int? currentQuestionIndex,
    Map<int, String>? answers,
    QuizAttemptResult? lastResult,
    bool? isLoading,
    bool? isSubmitting,
    bool? isCompleted,
    int? score,
    String? errorMessage,
    bool clearResult = false,
    bool clearError = false,
  }) {
    return QuizPlayerState(
      quiz: quiz ?? this.quiz,
      currentQuestionIndex: currentQuestionIndex ?? this.currentQuestionIndex,
      answers: answers ?? this.answers,
      lastResult: clearResult ? null : (lastResult ?? this.lastResult),
      isLoading: isLoading ?? this.isLoading,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      isCompleted: isCompleted ?? this.isCompleted,
      score: score ?? this.score,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// Notifier for quiz player.
class QuizPlayerNotifier extends StateNotifier<QuizPlayerState> {
  QuizPlayerNotifier(this._apiService) : super(const QuizPlayerState());

  final GamificationApiService _apiService;

  /// Load quiz details.
  Future<void> loadQuiz(int quizId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final quiz = await _apiService.getQuiz(quizId);
      state = state.copyWith(quiz: quiz, isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to load quiz: $e',
      );
    }
  }

  /// Start a quiz attempt.
  Future<void> startQuiz(int quizId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _apiService.startQuiz(quizId);
      final quiz = await _apiService.getQuiz(quizId);
      state = state.copyWith(
        quiz: quiz,
        isLoading: false,
        currentQuestionIndex: 0,
        answers: {},
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to start quiz: $e',
      );
    }
  }

  /// Submit an answer for the current question.
  Future<void> submitAnswer(int questionId, String selectedAnswer) async {
    if (state.quiz == null) return;

    state = state.copyWith(isSubmitting: true, clearResult: true);
    try {
      final result = await _apiService.submitAnswer(
        quizId: state.quiz!.id,
        questionId: questionId,
        selectedAnswer: selectedAnswer,
      );

      final newAnswers = Map<int, String>.from(state.answers);
      newAnswers[questionId] = selectedAnswer;

      state = state.copyWith(
        isSubmitting: false,
        answers: newAnswers,
        lastResult: result,
      );
    } catch (e) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: 'Failed to submit answer: $e',
      );
    }
  }

  /// Move to next question.
  void nextQuestion() {
    if (state.hasMoreQuestions) {
      state = state.copyWith(
        currentQuestionIndex: state.currentQuestionIndex + 1,
        clearResult: true,
      );
    }
  }

  /// Finish the quiz.
  Future<void> finishQuiz() async {
    if (state.quiz == null) return;

    state = state.copyWith(isSubmitting: true, clearResult: true);
    try {
      final result = await _apiService.finishQuiz(
        state.quiz!.id,
        answers: state.answers,
      );
      state = state.copyWith(
        isSubmitting: false,
        isCompleted: true,
        score: result['score'] as int?,
      );
    } catch (e) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: 'Failed to finish quiz: $e',
      );
    }
  }

  /// Reset the player.
  void reset() {
    state = const QuizPlayerState();
  }
}

/// Gamification service bound to the authenticated client.
///
/// Quizzes are graded and rewarded server-side, so every quiz call needs the
/// signed-in user's token. When the API is unreachable the service transparently
/// falls back to the offline catalogue.
final gamificationApiServiceProvider = Provider<GamificationApiService>((ref) {
  final apiClient = ref.watch(authenticatedApiClientProvider);
  return GamificationApiService(
    remote: QuizApiService(dio: apiClient.dio),
  );
});

/// Quiz player provider.
final quizPlayerProvider =
    StateNotifierProvider<QuizPlayerNotifier, QuizPlayerState>((ref) {
      return QuizPlayerNotifier(ref.watch(gamificationApiServiceProvider));
    });

/// Gamification profile provider.
final gamificationProfileProvider = FutureProvider<GamificationProfileModel>((
  ref,
) async {
  return ref.watch(gamificationApiServiceProvider).getProfile();
});

/// Badges provider.
final badgesProvider = FutureProvider<List<BadgeModel>>((ref) async {
  return ref.watch(gamificationApiServiceProvider).listBadges();
});

/// Quizzes provider.
final quizzesProvider = FutureProvider<List<QuizModel>>((ref) async {
  return ref.watch(gamificationApiServiceProvider).listQuizzes();
});

/// Identifies the story a quiz must belong to.
///
/// The id alone is not enough: the offline catalogue numbers its own stories
/// from 1, so an id-only match pairs the API's story 1 with an unrelated bundled
/// quiz. [slug] and [title] are unique across both data sources, so one of them
/// has to agree before a quiz is offered.
typedef StoryQuizKey = ({int id, String slug, String title});

/// Whether [quiz] was authored for [story].
///
/// The slug is the strongest signal and is preferred when both sides have one.
/// The title is the fallback, which keeps the reader working against a backend
/// that predates `story_slug` while the two deploys are in flight.
///
/// When neither can confirm the pairing the answer is no: offering a quiz we
/// cannot attribute to the story is exactly the bug this guards against.
bool _belongsToStory(QuizModel quiz, StoryQuizKey story) {
  if (quiz.storyId != story.id) return false;
  if (quiz.storySlug.isNotEmpty && story.slug.isNotEmpty) {
    return quiz.storySlug == story.slug;
  }
  if (quiz.storyTitle.isNotEmpty && story.title.isNotEmpty) {
    return quiz.storyTitle == story.title;
  }
  return false;
}

/// Quizzes belonging to one story, used by the story reader's "Take Quiz" CTA.
final quizzesByStoryProvider =
    Provider.autoDispose.family<List<QuizModel>, StoryQuizKey>((ref, story) {
      final quizzes = ref.watch(quizzesProvider).value ?? const <QuizModel>[];
      return quizzes.where((quiz) => _belongsToStory(quiz, story)).toList();
    });
