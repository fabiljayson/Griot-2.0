// Bundled quiz seed content for the offline gamification layer.

/// A quiz plus the questions it owns, ready for the seeding pass.
class SeedQuizData {
  const SeedQuizData({
    required this.quiz,
    this.storySlug,
    required this.questions,
  });

  /// Row for `local_quizzes` (inserted as-is).
  final Map<String, Object?> quiz;

  /// Slug of the story this quiz belongs to, if any.
  final String? storySlug;

  /// Rows for `local_quiz_questions`; `quiz_id` is stamped at insert time.
  final List<Map<String, Object?>> questions;
}

/// Quizzes seeded into `local_quizzes` (and their questions).
final List<SeedQuizData> kSeedQuizzes = [
  SeedQuizData(
    quiz: {
      'title': 'Anansi and the Wisdom Pot',
      'description': 'Test your knowledge of the Anansi story.',
      'story_title': "The Spider's Gift: Anansi and the Wisdom Pot",
      'passing_score': 70,
      'question_count': 4,
      'xp_reward': 40,
      'language': 'en',
    },
    storySlug: 'anansi-wisdom-pot',
    questions: [
      {
        'question_text': 'Who wanted to hoard all the wisdom?',
        'option_a': 'Anansi the spider',
        'option_b': 'Nyame the Sky God',
        'option_c': 'Anansi\'s son',
        'correct_answer': 'a',
        'explanation':
            'Anansi was known for his greed and wanted all wisdom for himself.',
        'difficulty': 'easy',
      },
      {
        'question_text': 'Where was the pot of wisdom hidden?',
        'option_a': 'At the bottom of the river',
        'option_b': 'In the heavens',
        'option_c': 'Inside a tree',
        'correct_answer': 'b',
        'explanation': 'Nyame kept the pot of wisdom hidden in the heavens.',
        'difficulty': 'easy',
      },
      {
        'question_text': 'How did Anansi\'s son solve the problem?',
        'option_a': 'He called his friends',
        'option_b': 'He used a vine to tie the pot',
        'option_c': 'He rolled the pot',
        'correct_answer': 'b',
        'explanation':
            'The young son suggested tying the pot to the back with a vine.',
        'difficulty': 'medium',
      },
      {
        'question_text': 'What did Anansi do with the pot in the end?',
        'option_a': 'Kept it for himself',
        'option_b': 'Threw it into the sea',
        'option_c': 'Opened it and let wisdom scatter across the world',
        'correct_answer': 'c',
        'explanation': 'Anansi released the wisdom for all creatures to share.',
        'difficulty': 'medium',
      },
    ],
  ),
  SeedQuizData(
    quiz: {
      'title': "The Lion's Bath",
      'description': 'How well do you know this Bamoun tale?',
      'story_title': "The Lion's Bath: A Tale from the Bamoun Kingdom",
      'passing_score': 70,
      'question_count': 4,
      'xp_reward': 40,
      'language': 'en',
    },
    storySlug: 'lions-bath',
    questions: [
      {
        'question_text': 'What was King Tabondo afraid of?',
        'option_a': 'Fire',
        'option_b': 'Water',
        'option_c': 'The dark',
        'correct_answer': 'b',
        'explanation': 'King Tabondo had a secret — he was afraid of water.',
        'difficulty': 'easy',
      },
      {
        'question_text':
            'What did the king demand in exchange for sharing his spring?',
        'option_a': 'Gold',
        'option_b': 'Someone to make him laugh',
        'option_c': 'A new kingdom',
        'correct_answer': 'b',
        'explanation':
            'He wanted someone to make him laugh — he had not laughed in ten years.',
        'difficulty': 'easy',
      },
      {
        'question_text': 'Who finally made the king laugh?',
        'option_a': 'The elephant',
        'option_b': 'The monkey',
        'option_c': 'Tama the rabbit',
        'correct_answer': 'c',
        'explanation': 'Tama the rabbit told a clever riddle about water.',
        'difficulty': 'medium',
      },
      {
        'question_text': 'What was Tama\'s riddle answer?',
        'option_a': 'Strength',
        'option_b': 'Water',
        'option_c': 'Wisdom',
        'correct_answer': 'b',
        'explanation':
            'The answer was water — even the mighty lion avoids the bath!',
        'difficulty': 'medium',
      },
    ],
  ),
  SeedQuizData(
    quiz: {
      'title': 'The Talking Drum of Foumban',
      'description': 'Discover what you remember about this legend.',
      'story_title': 'The Talking Drum of Foumban',
      'passing_score': 70,
      'question_count': 4,
      'xp_reward': 40,
      'language': 'en',
    },
    storySlug: 'talking-drum-foumban',
    questions: [
      {
        'question_text': 'Who carved the talking drum?',
        'option_a': 'Kwame',
        'option_b': 'Nji Kuma',
        'option_c': 'The king of Foumban',
        'correct_answer': 'b',
        'explanation':
            'Nji Kuma, the grandfather of rhythm, carved the drum from iroko wood.',
        'difficulty': 'easy',
      },
      {
        'question_text': 'What made the drum special?',
        'option_a': 'It was made of gold',
        'option_b': 'It could speak the truth',
        'option_c': 'It played itself',
        'correct_answer': 'b',
        'explanation': 'The drum had a true voice — the voice of truth.',
        'difficulty': 'easy',
      },
      {
        'question_text': 'Why could Kwame initially not make the drum speak?',
        'option_a': 'He was too young',
        'option_b': 'He did not carry truth in his soul',
        'option_c': 'The drum was broken',
        'correct_answer': 'b',
        'explanation':
            'The drum speaks only to those who carry truth in their souls.',
        'difficulty': 'medium',
      },
      {
        'question_text': 'What qualities did Kwame develop over the years?',
        'option_a': 'Strength and speed',
        'option_b': 'Honesty and integrity',
        'option_c': 'Wealth and power',
        'correct_answer': 'b',
        'explanation':
            'Kwame learned to live with honesty and integrity before the drum would speak.',
        'difficulty': 'medium',
      },
    ],
  ),
  SeedQuizData(
    quiz: {
      'title': 'Cameroon Cultural Heritage',
      'description': 'Test your general knowledge of Cameroonian culture.',
      'passing_score': 60,
      'question_count': 5,
      'xp_reward': 50,
      'language': 'en',
    },
    storySlug: null,
    questions: [
      {
        'question_text': 'What is a griot?',
        'option_a': 'A type of drum',
        'option_b': 'A traditional storyteller and oral historian',
        'option_c': 'A Cameroonian dance',
        'correct_answer': 'b',
        'explanation':
            'Griots are West African storytellers, musicians, and oral historians who preserve cultural traditions.',
        'difficulty': 'easy',
      },
      {
        'question_text': 'Which kingdom is Foumban the capital of?',
        'option_a': 'The Bamileke Kingdom',
        'option_b': 'The Bamoun Kingdom',
        'option_c': 'The Fulani Empire',
        'correct_answer': 'b',
        'explanation':
            'Foumban is the historic capital of the Bamoun Kingdom in western Cameroon.',
        'difficulty': 'easy',
      },
      {
        'question_text': 'What is Mami Wata?',
        'option_a': 'A type of food',
        'option_b': 'A water goddess in African spiritual traditions',
        'option_c': 'A traditional instrument',
        'correct_answer': 'b',
        'explanation':
            'Mami Wata (Water Mother) is a widespread figure associated with water, fertility, and fortune.',
        'difficulty': 'medium',
      },
      {
        'question_text': 'What is the longest river in Cameroon?',
        'option_a': 'The Congo',
        'option_b': 'The Sanaga',
        'option_c': 'The Niger',
        'correct_answer': 'b',
        'explanation':
            'The Sanaga is the longest river in Cameroon, flowing from the Adamawa Plateau to the Atlantic.',
        'difficulty': 'medium',
      },
      {
        'question_text': 'What animal is Anansi in West African folklore?',
        'option_a': 'A lion',
        'option_b': 'A spider',
        'option_c': 'A bird',
        'correct_answer': 'b',
        'explanation':
            'Anansi is a trickster spider figure in Akan and wider West African folklore.',
        'difficulty': 'easy',
      },
    ],
  ),
  SeedQuizData(
    quiz: {
      'title': 'Anansi et la Pot de Sagesse',
      'description': 'Testez vos connaissances sur l\'histoire d\'Anansi.',
      'story_title': 'Le Don de l\'Araignée : Anansi et le Pot de Sagesse',
      'passing_score': 70,
      'question_count': 4,
      'xp_reward': 40,
      'language': 'fr',
    },
    storySlug: null,
    questions: [
      {
        'question_text': 'Qui voulait accaparer toute la sagesse ?',
        'option_a': 'Anansi l\'araignée',
        'option_b': 'Nyame le Dieu du Ciel',
        'option_c': 'Le fils d\'Anansi',
        'correct_answer': 'a',
        'explanation':
            'Anansi était connu pour sa cupidité et voulait toute la sagesse pour lui seul.',
        'difficulty': 'easy',
      },
      {
        'question_text': 'Où était caché le pot de sagesse ?',
        'option_a': 'Au fond de la rivière',
        'option_b': 'Dans les cieux',
        'option_c': 'Dans un arbre',
        'correct_answer': 'b',
        'explanation': 'Nyame gardait le pot de sagesse caché dans les cieux.',
        'difficulty': 'easy',
      },
      {
        'question_text':
            'Comment le fils d\'Anansi a-t-il résolu le problème ?',
        'option_a': 'Il a appelé ses amis',
        'option_b': 'Il a attaché le pot avec une liane',
        'option_c': 'Il a fait rouler le pot',
        'correct_answer': 'b',
        'explanation':
            'Le jeune fils a suggéré d\'attacher le pot dans le dos avec une liane.',
        'difficulty': 'medium',
      },
      {
        'question_text': 'Qu\'a fait Anansi du pot à la fin ?',
        'option_a': 'Il l\'a gardé pour lui',
        'option_b': 'Il l\'a jeté à la mer',
        'option_c': 'Il l\'a ouvert pour que la sagesse se répande',
        'correct_answer': 'c',
        'explanation':
            'Anansi a libéré la sagesse pour que toutes les créatures puissent en profiter.',
        'difficulty': 'medium',
      },
    ],
  ),
];
