import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:griot_ai/features/gamification/providers/gamification_provider.dart';
import 'package:griot_ai/features/gamification/services/gamification_api_service.dart';

/// Quizzes the API returned for the published catalogue.
final _catalogue = <QuizModel>[
  QuizModel(
    id: 9,
    title: 'Sacred Forest Wisdom: Foreke-Dschang',
    storyId: 1,
    storySlug: 'the-sacred-forest-of-foreke-dschang',
    storyTitle: 'The Sacred Forest of Foreke-Dschang',
    questionCount: 4,
  ),
  QuizModel(
    id: 8,
    title: 'Elephant Dance Culture: The Bamileke',
    storyId: 2,
    storySlug: 'the-baaka-pygmies-keepers-of-the-forest',
    storyTitle: 'The Ba\'aka Pygmies: Keepers of the Forest',
    questionCount: 4,
  ),
];

/// The story reader awaits the catalogue before resolving, so the tests do too.
Future<List<QuizModel>> _resolve(
  ProviderContainer container,
  int id,
  String slug, {
  String title = '',
}) async {
  await container.read(quizzesProvider.future);
  return container.read(
    quizzesByStoryProvider((id: id, slug: slug, title: title)),
  );
}

/// Regression cover for the bug that made quizzes unusable in production.
///
/// The reader resolved a quiz by comparing `quiz.storyId` with the story's id.
/// Those ids come from two different catalogues: the API numbers the published
/// stories 1..9, while the bundled offline catalogue independently numbers its
/// own stories from 1. The numbers therefore line up by coincidence, and the
/// story reader handed readers a quiz written for a completely different story
/// — story 1 was offered the Anansi quiz — while the other stories reported
/// "Quiz coming soon".
///
/// The slug is unique across both catalogues, so requiring it alongside the id
/// is what makes the match trustworthy.
void main() {
  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [quizzesProvider.overrideWith((ref) async => _catalogue)],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('quizzesByStoryProvider', () {
    test('returns the quiz that belongs to the story', () async {
      final quizzes = await _resolve(
        makeContainer(),
        1,
        'the-sacred-forest-of-foreke-dschang',
      );

      expect(quizzes, hasLength(1));
      expect(quizzes.single.id, 9);
    });

    test('does not offer a quiz written for a different story', () async {
      // Story 2's id collides with a bundled offline quiz's id, but the slug
      // shows the quiz belongs to the Ba'aka story, not this one.
      final quizzes = await _resolve(
        makeContainer(),
        2,
        'the-bamoun-sultanate-a-legacy-of-innovation',
      );

      expect(quizzes, isEmpty);
    });

    test(
      'reports no quiz rather than guessing when the slug disagrees',
      () async {
        // Every published story id in the catalogue is claimed by some quiz, so a
        // naive id match would return a quiz for all of them. Matching the slug
        // is what leaves a story honestly without a quiz.
        final container = makeContainer();
        for (final quiz in _catalogue) {
          expect(
            await _resolve(
              container,
              quiz.storyId,
              'a-totally-different-story',
            ),
            isEmpty,
          );
        }
      },
    );

    test('falls back to the title for a quiz with no slug', () async {
      // A backend predating `story_slug` sends no slug at all. The title is
      // then the only way to attribute a quiz, and it is unique per story.
      final container = ProviderContainer(
        overrides: [
          quizzesProvider.overrideWith(
            (ref) async => [
              QuizModel(
                id: 9,
                title: 'Sacred Forest Wisdom: Foreke-Dschang',
                storyId: 1,
                storyTitle: 'The Sacred Forest of Foreke-Dschang',
                questionCount: 4,
              ),
            ],
          ),
        ],
      );
      addTearDown(container.dispose);

      final quizzes = await _resolve(
        container,
        1,
        'the-sacred-forest-of-foreke-dschang',
        title: 'The Sacred Forest of Foreke-Dschang',
      );

      expect(quizzes, hasLength(1));
      expect(quizzes.single.id, 9);
    });

    test('refuses to match when neither slug nor title can confirm', () async {
      // Nothing identifies the quiz's story, so offering it would be the
      // original bug: a quiz attributed to a story it was never written for.
      final quizzes = await _resolve(makeContainer(), 1, '');

      expect(quizzes, isEmpty);
    });

    test('refuses to match when the titles disagree', () async {
      final container = ProviderContainer(
        overrides: [
          quizzesProvider.overrideWith(
            (ref) async => [
              QuizModel(
                id: 9,
                title: 'Sacred Forest Wisdom: Foreke-Dschang',
                storyId: 1,
                storyTitle: 'The Sacred Forest of Foreke-Dschang',
                questionCount: 4,
              ),
            ],
          ),
        ],
      );
      addTearDown(container.dispose);

      final quizzes = await _resolve(
        container,
        1,
        '',
        title: 'The Baobab of the Savanna',
      );

      expect(quizzes, isEmpty);
    });
  });
}
