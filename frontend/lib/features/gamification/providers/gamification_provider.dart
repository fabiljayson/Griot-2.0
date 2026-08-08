import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/gamification_api_service.dart';

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
  QuizPlayerNotifier() : _apiService = GamificationApiService.instance, super(const QuizPlayerState());

  final GamificationApiService _apiService;

  /// Load quiz details.
  Future<void> loadQuiz(int quizId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final quiz = await _apiService.getQuiz(quizId);
      state = state.copyWith(quiz: quiz, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: 'Failed to load quiz: $e');
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
      state = state.copyWith(isLoading: false, errorMessage: 'Failed to start quiz: $e');
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

    state = state.copyWith(isSubmitting: true);
    try {
      final result = await _apiService.finishQuiz(state.quiz!.id);
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

/// Quiz player provider.
final quizPlayerProvider =
    StateNotifierProvider<QuizPlayerNotifier, QuizPlayerState>((ref) {
  return QuizPlayerNotifier();
});

/// Gamification profile provider.
final gamificationProfileProvider = FutureProvider<GamificationProfileModel>((ref) async {
  final apiService = GamificationApiService.instance;
  return apiService.getProfile();
});

/// Badges provider.
final badgesProvider = FutureProvider<List<BadgeModel>>((ref) async {
  final apiService = GamificationApiService.instance;
  return apiService.listBadges();
});

/// Quizzes provider.
final quizzesProvider = FutureProvider<List<QuizModel>>((ref) async {
  final apiService = GamificationApiService.instance;
  return apiService.listQuizzes();
});
