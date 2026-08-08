"""
Management command to seed the database with quiz and badge data.

Usage:
    python manage.py seed_gamification
    python manage.py seed_gamification --clear  # Clear existing data first
"""

from django.core.management.base import BaseCommand

from gamification.models import Badge, Quiz, QuizQuestion
from stories.models import Story


class Command(BaseCommand):
    help = 'Seed the database with quizzes and badges for gamification'

    def add_arguments(self, parser):
        parser.add_argument(
            '--clear',
            action='store_true',
            help='Clear existing gamification data before seeding',
        )

    def handle(self, *args, **options):
        if options['clear']:
            self.stdout.write('Clearing existing gamification data...')
            Quiz.objects.all().delete()
            Badge.objects.all().delete()

        # Create badges
        self._create_badges()

        # Create quizzes for published stories
        self._create_quizzes()

        self.stdout.write(self.style.SUCCESS('Successfully seeded gamification data!'))

    def _create_badges(self):
        """Create achievement badges."""
        badge_data = [
            # Reading badges
            {
                'name': 'First Steps',
                'slug': 'first-steps',
                'description': 'Read your first story on African Teller',
                'emoji': '👣',
                'category': 'reading',
                'stories_read_required': 1,
                'color': '#C85A32',
            },
            {
                'name': 'Story Seeker',
                'slug': 'story-seeker',
                'description': 'Read 5 different stories',
                'emoji': '📖',
                'category': 'reading',
                'stories_read_required': 5,
                'color': '#D99B26',
            },
            {
                'name': 'Cultural Explorer',
                'slug': 'cultural-explorer',
                'description': 'Read 10 different stories',
                'emoji': '🗺️',
                'category': 'exploration',
                'stories_read_required': 10,
                'color': '#2D5A27',
            },
            {
                'name': 'Heritage Guardian',
                'slug': 'heritage-guardian',
                'description': 'Read 25 different stories',
                'emoji': '🏛️',
                'category': 'exploration',
                'stories_read_required': 25,
                'color': '#4B0082',
            },
            {
                'name': 'Wisdom Keeper',
                'slug': 'wisdom-keeper',
                'description': 'Read 50 different stories',
                'emoji': '📚',
                'category': 'reading',
                'stories_read_required': 50,
                'color': '#8B4513',
                'is_secret': True,
            },

            # Quiz badges
            {
                'name': 'Quiz Rookie',
                'slug': 'quiz-rookie',
                'description': 'Pass your first quiz',
                'emoji': '🧠',
                'category': 'quiz',
                'quizzes_passed_required': 1,
                'color': '#C85A32',
            },
            {
                'name': 'Knowledge Champion',
                'slug': 'knowledge-champion',
                'description': 'Pass 5 quizzes',
                'emoji': '🏆',
                'category': 'quiz',
                'quizzes_passed_required': 5,
                'color': '#D99B26',
            },
            {
                'name': 'Quiz Master',
                'slug': 'quiz-master',
                'description': 'Pass 10 quizzes with 100% score',
                'emoji': '🎓',
                'category': 'quiz',
                'quizzes_passed_required': 10,
                'color': '#2D5A27',
                'is_secret': True,
            },

            # XP badges
            {
                'name': 'Rising Star',
                'slug': 'rising-star',
                'description': 'Earn 100 XP',
                'emoji': '⭐',
                'category': 'reading',
                'xp_required': 100,
                'color': '#FFD700',
            },
            {
                'name': 'Heritage Hero',
                'slug': 'heritage-hero',
                'description': 'Earn 500 XP',
                'emoji': '🦸',
                'category': 'special',
                'xp_required': 500,
                'color': '#C85A32',
            },
            {
                'name': 'Legendary Explorer',
                'slug': 'legendary-explorer',
                'description': 'Earn 1000 XP',
                'emoji': '👑',
                'category': 'special',
                'xp_required': 1000,
                'color': '#DAA520',
                'is_secret': True,
            },

            # Streak badges
            {
                'name': 'Dedicated Reader',
                'slug': 'dedicated-reader',
                'description': 'Read stories 3 days in a row',
                'emoji': '🔥',
                'category': 'reading',
                'xp_required': 0,
                'color': '#FF4500',
            },
        ]

        for data in badge_data:
            badge, created = Badge.objects.get_or_create(
                slug=data['slug'],
                defaults=data,
            )
            if created:
                self.stdout.write(f'  Created badge: {data["name"]}')

    def _create_quizzes(self):
        """Create quizzes for published stories."""
        stories = Story.objects.filter(status=Story.Status.PUBLISHED)

        quiz_data = {
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

        for story in stories:
            if story.title in quiz_data:
                data = quiz_data[story.title]
                quiz, created = Quiz.objects.get_or_create(
                    story=story,
                    defaults={
                        'title': data['title'],
                        'description': data['description'],
                        'passing_score': 70,
                    },
                )

                if created:
                    for i, q in enumerate(data['questions'], 1):
                        QuizQuestion.objects.create(
                            quiz=quiz,
                            order=i,
                            **q,
                        )
                    self.stdout.write(f'  Created quiz: {data["title"]} ({len(data["questions"])} questions)')


