import 'package:flutter_test/flutter_test.dart';

import 'package:griot_ai/core/database/repositories/local_gamification_repository.dart';

void main() {
  group('LocalGamificationRepository.computeScore', () {
    test('scores 100 for all-correct answers', () {
      final result = LocalGamificationRepository.computeScore(
        correctAnswers: 5,
        totalQuestions: 5,
        passingScore: 70,
      );
      expect(result['score'], 100);
      expect(result['passed'], isTrue);
    });

    test('scores 0 when no answers are correct', () {
      final result = LocalGamificationRepository.computeScore(
        correctAnswers: 0,
        totalQuestions: 3,
        passingScore: 70,
      );
      expect(result['score'], 0);
      expect(result['passed'], isFalse);
    });

    test('rounds the percentage to the nearest whole number', () {
      final result = LocalGamificationRepository.computeScore(
        correctAnswers: 2,
        totalQuestions: 3,
        passingScore: 70,
      );
      expect(result['score'], 67);
      expect(result['passed'], isFalse);
    });

    test('passes only when score meets the passing threshold', () {
      expect(
        LocalGamificationRepository.computeScore(
          correctAnswers: 7,
          totalQuestions: 10,
          passingScore: 70,
        )['passed'],
        isTrue,
      );
      expect(
        LocalGamificationRepository.computeScore(
          correctAnswers: 6,
          totalQuestions: 10,
          passingScore: 70,
        )['passed'],
        isFalse,
      );
    });

    test('scores 0 and never passes with zero questions', () {
      final result = LocalGamificationRepository.computeScore(
        correctAnswers: 0,
        totalQuestions: 0,
        passingScore: 70,
      );
      expect(result['score'], 0);
      expect(result['passed'], isFalse);
    });
  });
}
