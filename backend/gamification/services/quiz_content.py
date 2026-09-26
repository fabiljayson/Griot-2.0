"""Source of quiz content for the gamification app.

Two kinds of question live here:

* :data:`CURATED_QUIZZES` — hand-written quizzes keyed by story title. These are
  the ones a heritage reviewer wrote, so they always win.
* :func:`build_generated_quiz_data` — the fallback used for any story without a
  curated quiz, so publishing a story never leaves its reader without a quiz.

Keeping both in one module lets the management commands and the
``post_save`` receiver provision quizzes through exactly the same path.
"""

from __future__ import annotations

CURATED_QUIZZES: dict[str, dict] = {
    'The Legend of Mount Mbapit\'s Crater Lake': {
        'title': 'Test Your Knowledge: Mount Mbapit',
        'description': 'How well do you know the mysterious crater lake legend?',
        'questions': [
            {
                'question_text': 'What is unique about the crater lake of Mount Mbapit?',
                'option_a': 'The water changes color throughout the day',
                'option_b': 'Stones thrown into it never touch the water',
                'option_c': 'The lake freezes every winter',
                'option_d': 'The water is poisonous to animals',
                'correct_answer': 'b',
                'explanation': 'According to legend, stones thrown into the crater lake never touch the water—they vanish before reaching the surface.',
                'difficulty': 'easy',
            },
            {
                'question_text': 'Which ethnic group is associated with the Mount Mbapit legend?',
                'option_a': 'Bamoun',
                'option_b': 'Baka',
                'option_c': 'Bamileke',
                'option_d': 'Fulani',
                'correct_answer': 'c',
                'explanation': 'The Bamileke people are the guardians of this legend and the surrounding area.',
                'difficulty': 'medium',
            },
            {
                'question_text': 'What does the lake represent for the Bamileke people?',
                'option_a': 'A source of wealth',
                'option_b': 'A test of faith and respect for nature',
                'option_c': 'A place for fishing',
                'option_d': 'A boundary between villages',
                'correct_answer': 'b',
                'explanation': 'The lake represents a test of faith—those who approach with humility receive blessings, while the arrogant face misfortune.',
                'difficulty': 'medium',
            },
            {
                'question_text': 'How tall is Mount Mbapit?',
                'option_a': '500 meters',
                'option_b': '1,200 meters',
                'option_c': '1,900 meters',
                'option_d': '2,500 meters',
                'correct_answer': 'c',
                'explanation': 'Mount Mbapit stands at 1,900 meters above sea level in the western highlands of Cameroon.',
                'difficulty': 'hard',
            },
        ],
    },
    'The Ba\'aka Pygmies: Keepers of the Forest': {
        'title': 'Forest Knowledge: The Ba\'aka People',
        'description': 'Explore your understanding of the Ba\'aka forest dwellers.',
        'questions': [
            {
                'question_text': 'What does the name "Ba\'aka" mean?',
                'option_a': 'People of the river',
                'option_b': 'People of the forest',
                'option_c': 'People of the mountain',
                'option_d': 'People of the village',
                'correct_answer': 'b',
                'explanation': 'Ba\'aka means "people of the forest," reflecting their deep connection to the woodland environment.',
                'difficulty': 'easy',
            },
            {
                'question_text': 'What is the Djengui dance?',
                'option_a': 'A harvest celebration',
                'option_b': 'A coming-of-age ceremony',
                'option_c': 'A sacred spiritual practice',
                'option_d': 'A warrior dance',
                'correct_answer': 'c',
                'explanation': 'The Djengui dance is a sacred ceremony that connects dancers with the spirit of the forest through rhythmic movement and chanting.',
                'difficulty': 'medium',
            },
            {
                'question_text': 'Where do the Ba\'aka people primarily live?',
                'option_a': 'Mount Cameroon',
                'option_b': 'Waza National Park',
                'option_c': 'Dja Reserve',
                'option_d': 'Lobéké National Park',
                'correct_answer': 'c',
                'explanation': 'The Ba\'aka are primarily found in the Dja Reserve, a UNESCO World Heritage Site in southeastern Cameroon.',
                'difficulty': 'medium',
            },
            {
                'question_text': 'Which of these is NOT a traditional Ba\'aka skill?',
                'option_a': 'Identifying medicinal plants',
                'option_b': 'Tracking animals',
                'option_c': 'Metal forging',
                'option_d': 'Weather prediction',
                'correct_answer': 'c',
                'explanation': 'Metal forging is not a traditional Ba\'aka skill. They are known for plant knowledge, tracking, and weather prediction.',
                'difficulty': 'hard',
            },
        ],
    },
    'The Bamileke: Guardians of the Highlands': {
        'title': 'Highland Heritage: The Bamileke',
        'description': 'How much do you know about the Bamileke kingdom?',
        'questions': [
            {
                'question_text': 'What is the Bamileke king called?',
                'option_a': 'Sultan',
                'option_b': 'Fô\'o',
                'option_c': 'Chief',
                'option_d': 'Emperor',
                'correct_answer': 'b',
                'explanation': 'The Fô\'o is the traditional king of the Bamileke, serving as both political leader and spiritual bridge to the ancestors.',
                'difficulty': 'easy',
            },
            {
                'question_text': 'What animal is most associated with Bamileke masks?',
                'option_a': 'Lion',
                'option_b': 'Snake',
                'option_c': 'Elephant',
                'option_d': 'Eagle',
                'correct_answer': 'c',
                'explanation': 'Elephant masks are among the most iconic Bamileke art forms, representing strength and royalty.',
                'difficulty': 'medium',
            },
            {
                'question_text': 'What shape do Bamileke round buildings represent?',
                'option_a': 'The sun',
                'option_b': 'The cycle of life',
                'option_c': 'The moon',
                'option_d': 'The river',
                'correct_answer': 'b',
                'explanation': 'Round buildings in Bamileke architecture symbolize the cycle of life—birth, growth, death, and renewal.',
                'difficulty': 'medium',
            },
            {
                'question_text': 'What is Lake Baleng known for?',
                'option_a': 'Fishing',
                'option_b': 'Swimming',
                'option_c': 'Healing properties',
                'option_d': 'Boating',
                'correct_answer': 'c',
                'explanation': 'Lake Baleng is believed to have healing properties, and pilgrims travel from across the region to bathe in its waters.',
                'difficulty': 'hard',
            },
        ],
    },
    'The Sacred Forest of Foreke-Dschang': {
        'title': 'Sacred Forest Wisdom: Foreke-Dschang',
        'description': 'Discover the spiritual significance of the sacred forest.',
        'questions': [
            {
                'question_text': 'What is the sacred forest of Foreke-Dschang primarily protected for?',
                'option_a': 'Tourism revenue',
                'option_b': 'Spiritual and cultural significance',
                'option_c': 'Scientific research',
                'option_d': 'Timber production',
                'correct_answer': 'b',
                'explanation': 'The sacred forest is protected for its profound spiritual and cultural significance to the Dschang people.',
                'difficulty': 'easy',
            },
            {
                'question_text': 'Who is traditionally allowed to enter the deepest parts of the sacred forest?',
                'option_a': 'Anyone who asks permission',
                'option_b': 'Only women during harvest',
                'option_c': 'Only initiated elders and priests',
                'option_d': 'Tourists with a guide',
                'correct_answer': 'c',
                'explanation': 'Only initiated elders and priests are allowed to enter the deepest parts of the sacred forest.',
                'difficulty': 'medium',
            },
            {
                'question_text': 'What role does the sacred forest play in community decisions?',
                'option_a': 'It has no role in modern decisions',
                'option_b': 'It serves as a neutral ground for dispute resolution',
                'option_c': 'It is used for market trading',
                'option_d': 'It is a recreational park',
                'correct_answer': 'b',
                'explanation': 'The sacred forest serves as a neutral ground for dispute resolution and important community gatherings.',
                'difficulty': 'medium',
            },
            {
                'question_text': 'What happens to someone who violates the sacred forest rules?',
                'option_a': 'They are fined by the government',
                'option_b': 'Nothing happens',
                'option_c': 'They face spiritual consequences and community sanctions',
                'option_d': 'They are exiled from the country',
                'correct_answer': 'c',
                'explanation': 'Violators face spiritual consequences believed to be passed down through generations, as well as community sanctions.',
                'difficulty': 'hard',
            },
        ],
    },
    'The Bamileke Elephant Dance': {
        'title': 'Elephant Dance Culture: The Bamileke',
        'description': 'Test your knowledge of the famous Bamileke Elephant Dance.',
        'questions': [
            {
                'question_text': 'What does the Elephant Dance symbolize?',
                'option_a': 'The end of the rainy season',
                'option_b': 'Royal power and the strength of the kingdom',
                'option_c': 'The beginning of harvest',
                'option_d': 'A welcome for visitors',
                'correct_answer': 'b',
                'explanation': 'The Elephant Dance symbolizes royal power and the enduring strength of the Bamileke kingdom.',
                'difficulty': 'easy',
            },
            {
                'question_text': 'What do the dancers wear during the Elephant Dance?',
                'option_a': 'Simple white robes',
                'option_b': 'Elaborate beaded costumes with elephant masks',
                'option_c': 'Animal skins only',
                'option_d': 'Modern clothing',
                'correct_answer': 'b',
                'explanation': 'Dancers wear elaborate beaded costumes with elephant masks featuring large circular ears and tusks.',
                'difficulty': 'medium',
            },
            {
                'question_text': 'When is the Elephant Dance traditionally performed?',
                'option_a': 'Every day at sunset',
                'option_b': 'Only during funerals',
                'option_c': 'During festivals and royal ceremonies',
                'option_d': 'Only in winter',
                'correct_answer': 'c',
                'explanation': 'The Elephant Dance is performed during festivals and royal ceremonies to celebrate and honor the kingdom.',
                'difficulty': 'medium',
            },
            {
                'question_text': 'What instrument accompanies the Elephant Dance?',
                'option_a': 'Guitar',
                'option_b': 'Royal drums and whistles',
                'option_c': 'Piano',
                'option_d': 'Flute only',
                'correct_answer': 'b',
                'explanation': 'Royal drums and whistles create the powerful rhythm that drives the Elephant Dance.',
                'difficulty': 'hard',
            },
        ],
    },
    'The Ekom-Nkam Waterfalls: Where Tarzan Was Born': {
        'title': 'Waterfall Wonders: Ekom-Nkam',
        'description': 'Explore the legendary waterfalls where Tarzan was filmed.',
        'questions': [
            {
                'question_text': 'How tall are the Ekom-Nkam Waterfalls?',
                'option_a': '50 meters',
                'option_b': '80 meters',
                'option_c': '120 meters',
                'option_d': '200 meters',
                'correct_answer': 'b',
                'explanation': 'The Ekom-Nkam Waterfalls cascade down approximately 80 meters into a lush tropical pool.',
                'difficulty': 'easy',
            },
            {
                'question_text': 'What film was famously shot at these waterfalls?',
                'option_a': 'Black Panther',
                'option_b': 'Greystoke: The Legend of Tarzan',
                'option_c': 'Indiana Jones',
                'option_d': 'Jurassic Park',
                'correct_answer': 'b',
                'explanation': 'The 1984 film "Greystoke: The Legend of Tarzan" was famously shot at the Ekom-Nkam Waterfalls.',
                'difficulty': 'medium',
            },
            {
                'question_text': 'What is the local name for the waterfalls?',
                'option_a': 'The Tears of the Mountain',
                'option_b': 'The Hair of the Forest',
                'option_c': 'The Blood of the River',
                'option_d': 'The Voice of the Earth',
                'correct_answer': 'b',
                'explanation': 'Locally, the waterfalls are called "The Hair of the Forest" because of how the cascading water resembles flowing hair.',
                'difficulty': 'medium',
            },
            {
                'question_text': 'What lives in the pool at the base of the waterfalls?',
                'option_a': 'Only small fish',
                'option_b': 'Sacred catfish believed to be spirits',
                'option_c': 'Crocodiles',
                'option_d': 'Nothing—the water is too cold',
                'correct_answer': 'b',
                'explanation': 'Sacred catfish believed to be the spirits of ancestors inhabit the pool at the base of the waterfalls.',
                'difficulty': 'hard',
            },
        ],
    },
    'The Mysterious Lakes of Manengouba': {
        'title': 'Lakes of Mystery: Manengouba',
        'description': 'Explore the twin lakes with their fascinating legends.',
        'questions': [
            {
                'question_text': 'How many lakes are at the summit of Mount Manengouba?',
                'option_a': 'One large lake',
                'option_b': 'Three small ponds',
                'option_c': 'Two twin lakes',
                'option_d': 'Seven sacred pools',
                'correct_answer': 'c',
                'explanation': 'There are two twin lakes at the summit: the Male Lake and the Female Lake.',
                'difficulty': 'easy',
            },
            {
                'question_text': 'What are the two lakes called?',
                'option_a': 'North and South',
                'option_b': 'Male and Female',
                'option_c': 'Sun and Moon',
                'option_d': 'Old and Young',
                'correct_answer': 'b',
                'explanation': 'The lakes are called the Male Lake (Malebo) and the Female Lake (Bakono).',
                'difficulty': 'easy',
            },
            {
                'question_text': 'According to legend, what happened to the two lovers?',
                'option_a': 'They married and lived happily',
                'option_b': 'They were transformed into the two lakes',
                'option_c': 'They flew away as birds',
                'option_d': 'They became the mountain itself',
                'correct_answer': 'b',
                'explanation': 'Legend says two lovers from feuding villages were transformed into the twin lakes so they could be together forever.',
                'difficulty': 'medium',
            },
            {
                'question_text': 'What is unique about the water colors of the two lakes?',
                'option_a': 'They are the same color',
                'option_b': 'One is blue and the other is green',
                'option_c': 'They change color with the seasons',
                'option_d': 'Both are crystal clear',
                'correct_answer': 'b',
                'explanation': 'The Male Lake is deep blue while the Female Lake is green, reflecting their different depths and mineral content.',
                'difficulty': 'hard',
            },
        ],
    },
    'Bimbia: Where Memory Lives': {
        'title': 'Memory & Heritage: Bimbia',
        'description': 'Test your knowledge of this important historical site.',
        'questions': [
            {
                'question_text': 'What was Bimbia historically known for?',
                'option_a': 'Gold mining',
                'option_b': 'A slave trade embarkation point',
                'option_c': 'Spice trading',
                'option_d': 'Shipbuilding',
                'correct_answer': 'b',
                'explanation': 'Bimbia was one of the major embarkation points for the transatlantic slave trade in Cameroon.',
                'difficulty': 'easy',
            },
            {
                'question_text': 'When was Bimbia rediscovered for historical preservation?',
                'option_a': '1950',
                'option_b': '1975',
                'option_c': '1987',
                'option_d': '2001',
                'correct_answer': 'c',
                'explanation': 'Bimbia was rediscovered in 1987, though its history stretches back centuries.',
                'difficulty': 'medium',
            },
            {
                'question_text': 'What is the significance of the "Door of No Return"?',
                'option_a': 'It was the entrance to the village',
                'option_b': 'It marks where enslaved people took their last look at their homeland',
                'option_c': 'It was a royal palace entrance',
                'option_d': 'It was a marketplace gate',
                'correct_answer': 'b',
                'explanation': 'The "Door of No Return" marks the point where enslaved Africans were forced onto ships, never to return to their homeland.',
                'difficulty': 'medium',
            },
            {
                'question_text': 'What does "Bimbia" mean in the local language?',
                'option_a': 'Beautiful shore',
                'option_b': 'Place of tears',
                'option_c': 'Where memory lives',
                'option_d': 'End of the world',
                'correct_answer': 'c',
                'explanation': 'Bimbia means "where memory lives," reflecting the community\'s commitment to remembering their history.',
                'difficulty': 'hard',
            },
        ],
    },
    'The Bamoun Sultanate: A Legacy of Innovation': {
        'title': 'Royal Innovation: The Bamoun',
        'description': 'Discover the remarkable legacy of the Bamoun Sultanate.',
        'questions': [
            {
                'question_text': 'Who invented the Bamoun writing system?',
                'option_a': 'A European missionary',
                'option_b': 'King Njoya',
                'option_c': 'A local teacher',
                'option_d': 'Queen Mother',
                'correct_answer': 'b',
                'explanation': 'King Njoya invented the Bamoun syllabary in the late 19th century, a writing system with over 70 characters.',
                'difficulty': 'easy',
            },
            {
                'question_text': 'What is the Royal Palace of Foumban known for?',
                'option_a': 'Its modern architecture',
                'option_b': 'Its collection of Bamoun art and artifacts',
                'option_c': 'Its gold mines',
                'option_d': 'Its military fortress',
                'correct_answer': 'b',
                'explanation': 'The Royal Palace houses the Musée du Palais, which contains a rich collection of Bamoun art and historical artifacts.',
                'difficulty': 'medium',
            },
            {
                'question_text': 'What innovation did King Njoya introduce besides writing?',
                'option_a': 'Electricity',
                'option_b': 'A clock system and calendar',
                'option_c': 'Modern farming techniques',
                'option_d': 'Railroad construction',
                'correct_answer': 'b',
                'explanation': 'King Njoya also introduced a clock system, calendar, and even designed a throne that told a story of Bamoun history.',
                'difficulty': 'medium',
            },
            {
                'question_text': 'What is the Bamoun people\'s famous brass work tradition called?',
                'option_a': 'Golden weaving',
                'option_b': 'Lost-wax casting',
                'option_c': 'Iron forging',
                'option_d': 'Pottery making',
                'correct_answer': 'b',
                'explanation': 'The Bamoun are famous for their lost-wax brass casting technique used to create intricate art and ceremonial objects.',
                'difficulty': 'hard',
            },
        ],
    },
}

# Distractors that are plausible for *some* story in any culture, used only when
# the story itself does not supply enough sibling material to build options.
_GENERIC_DISTRACTORS = (
    'A story about modern city life',
    'An account of a space expedition',
    'A guide to software installation',
    'A recipe for a modern dish',
    'A football match report',
)


def _dedupe(values, limit):
    """Return up to ``limit`` distinct, non-empty strings preserving order."""
    seen = set()
    out = []
    for value in values:
        if not value:
            continue
        key = value.strip().lower()
        if key in seen:
            continue
        seen.add(key)
        out.append(value.strip())
        if len(out) == limit:
            break
    return out


def _pack_options(correct, distractors):
    """Place ``correct`` among ``distractors`` and report which letter holds it.

    Returns the option fields and the *letter* of the correct answer, which is
    what ``QuizQuestion.correct_answer`` stores (``max_length=1``).

    Options are ordered so the correct answer is *not* always the first one — a
    quiz whose answer is always "A" teaches readers to stop reading. The
    position is derived from the correct answer's text so a regenerated quiz is
    stable for a given story.
    """
    slots = list(distractors)
    # Spread the correct answer across the slots using a cheap stable hash.
    position = sum(ord(ch) for ch in correct) % (len(slots) + 1)
    slots.insert(position, correct)
    keys = ('option_a', 'option_b', 'option_c', 'option_d')
    return (
        {key: value for key, value in zip(keys, slots)},
        'abcd'[position],
    )


_GENERIC_REGIONS = (
    'Another region of Cameroon',
    'A region outside Cameroon',
    'The coastal plains',
)


def _pad(values, fillers, size=3, fallback='A different one'):
    """Top ``values`` up to ``size`` with distinct entries from ``fillers``.

    Never repeats a value: offering the same distractor twice makes the question
    unanswerable by reasoning. ``fallback`` names the kind of thing being padded
    so a story with no peers still gets a sensible last resort.
    """
    out = list(values)
    for filler in fillers:
        if len(out) >= size:
            break
        if filler.strip().lower() not in {v.strip().lower() for v in out}:
            out.append(filler)
    while len(out) < size:
        out.append(f'{fallback} ({len(out) + 1})')
    return out[:size]


def _first_sentences(text, limit=2):
    """Return the opening sentences of ``text`` for use as quiz answers."""
    cleaned = ' '.join((text or '').split())
    if not cleaned:
        return []
    parts = []
    for chunk in cleaned.replace('!', '.').replace('?', '.').split('.'):
        chunk = chunk.strip()
        if len(chunk) > 3:
            parts.append(chunk)
        if len(parts) == limit:
            break
    return parts


_LANGUAGE_LABELS = {
    'en': 'English',
    'fr': 'French',
    'ful': 'Fula',
    'dua': 'Duala',
    'ewo': 'Ewondo',
    'bml': 'Bamileke',
    'other': 'another language',
}


def _language_label(code):
    return _LANGUAGE_LABELS.get((code or '').strip().lower(), 'Cameroonian')


def _other_labels(code):
    """Every other known language label, as distractors."""
    normalised = (code or '').strip().lower()
    labels = [label for key, label in _LANGUAGE_LABELS.items() if key != normalised]
    while len(labels) < 3:
        labels.append('a language outside this collection')
    return labels[:3]


def build_generated_quiz_data(story, peers=()):
    """Build a four-question quiz for a story that has no curated quiz.

    Questions are derived from the story's own metadata — title, region,
    categories, summary, cultural context and moral lesson — so a newly
    published story gets a quiz that is actually about that story instead of a
    placeholder the reader can answer without reading anything.
    """
    region = (getattr(story, 'region', '') or '').strip()
    language = (getattr(story, 'language', '') or '').strip()
    source = (getattr(story, 'source', '') or '').strip()
    summary = (getattr(story, 'summary', '') or '').strip()
    cultural_context = (getattr(story, 'cultural_context', '') or '').strip()
    moral_lesson = (getattr(story, 'moral_lesson', '') or '').strip()

    categories = []
    manager = getattr(story, 'categories', None)
    if manager is not None:
        try:
            categories = [c.name for c in manager.all() if c and c.name]
        except (TypeError, ValueError):
            categories = []
    category = categories[0].strip() if categories else 'Cameroonian heritage'

    peer_titles = [
        getattr(peer, 'title', '') or ''
        for peer in peers
        if getattr(peer, 'pk', None) != getattr(story, 'pk', None)
    ]
    peer_regions = [
        getattr(peer, 'region', '') or ''
        for peer in peers
        if getattr(peer, 'region', '')
    ]

    other_titles = _pad(
        _dedupe([t for t in peer_titles if t and t != story.title], 3),
        _GENERIC_DISTRACTORS,
        fallback='A different cultural story',
    )

    other_regions = _pad(
        _dedupe([r for r in peer_regions if r != region], 3),
        _GENERIC_REGIONS,
        fallback='A different region',
    )

    questions = []

    def add(correct, distractors, text, explanation, difficulty):
        options, answer = _pack_options(correct, distractors)
        questions.append({
            'question_text': text,
            **options,
            'correct_answer': answer,
            'explanation': explanation,
            'difficulty': difficulty,
        })

    # 1. Reading recall — grounded in the summary when the author wrote one.
    summary_sentences = _first_sentences(summary)
    if summary_sentences:
        add(
            summary_sentences[0],
            other_titles,
            'Which of these best describes what happens in the story?',
            summary_sentences[0],
            'easy',
        )
    else:
        add(
            story.title,
            other_titles,
            'Which story did you just read?',
            f'This quiz belongs to "{story.title}".',
            'easy',
        )

    # 2. Cultural focus — from the story's first category.
    add(
        category,
        ['Modern technology', 'International finance', 'Space exploration'],
        'What is the main cultural focus of this story?',
        f'The story is filed under {category}.',
        'easy',
    )

    # 3. Place — region when set, otherwise whatever context the story has.
    context_sentences = _first_sentences(cultural_context)
    if region:
        add(
            region,
            other_regions,
            'Which region is this story associated with?',
            f'The story is set in {region}.',
            'medium',
        )
    elif context_sentences:
        add(
            context_sentences[0],
            other_titles,
            'What does the cultural context of this story describe?',
            context_sentences[0],
            'medium',
        )
    elif language:
        add(
            _language_label(language),
            _other_labels(language),
            'In which language is this story told?',
            f'This story is written in {_language_label(language)}.',
            'medium',
        )
    else:
        add(
            story.title,
            other_titles,
            'Which story is this quiz about?',
            f'This quiz belongs to "{story.title}".',
            'medium',
        )

    # 4. Takeaway — the moral lesson when the author supplied one.
    lesson_sentences = _first_sentences(moral_lesson)
    if lesson_sentences:
        add(
            lesson_sentences[0],
            [
                'A practical guide to urban transport',
                'A list of import tariffs',
                'A technical troubleshooting manual',
            ],
            'What lesson does this story teach?',
            lesson_sentences[0],
            'medium',
        )
    elif context_sentences:
        add(
            context_sentences[0],
            other_titles,
            'Why does this story matter for cultural heritage?',
            context_sentences[0],
            'hard',
        )
    elif source:
        add(
            source,
            other_titles,
            'Where does this story come from?',
            f'This story is recorded as coming from {source}.',
            'hard',
        )
    else:
        add(
            f'{story.title} belongs to the {category} collection.',
            other_titles,
            'Which statement about this story is true?',
            f'This quiz is about "{story.title}".',
            'hard',
        )

    return {
        'title': f'Test Your Knowledge: {story.title}',
        'description': f'Check what you remember from "{story.title}".',
        'questions': questions,
    }


def quiz_data_for(story, peers=()):
    """Return the curated quiz for ``story`` when one exists, else a generated one."""
    curated = CURATED_QUIZZES.get(story.title)
    if curated:
        return curated
    return build_generated_quiz_data(story, peers=peers)
