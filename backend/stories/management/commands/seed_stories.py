"""
Management command to seed the database with cultural stories and categories.

Usage:
    python manage.py seed_stories
    python manage.py seed_stories --clear  # Clear existing data first
"""

from django.core.management.base import BaseCommand
from django.contrib.auth import get_user_model

from stories.models import Story, StoryCategory

User = get_user_model()


class Command(BaseCommand):
    help = 'Seed the database with cultural stories and categories from Cameroon'

    def add_arguments(self, parser):
        parser.add_argument(
            '--clear',
            action='store_true',
            help='Clear existing stories and categories before seeding',
        )

    def handle(self, *args, **options):
        if options['clear']:
            self.stdout.write('Clearing existing stories and categories...')
            Story.objects.all().delete()
            StoryCategory.objects.all().delete()

        # Create or get the admin user for seeding
        admin_user, _ = User.objects.get_or_create(
            username='admin',
            defaults={
                'email': 'admin@africanteller.com',
                'role': 'admin',
                'is_staff': True,
                'is_superuser': True,
            }
        )
        if not admin_user.has_usable_password():
            admin_user.set_password('admin123')
            admin_user.save()

        # Create categories
        categories = self._create_categories()
        
        # Create stories
        self._create_stories(admin_user, categories)
        
        self.stdout.write(self.style.SUCCESS('Successfully seeded database with cultural stories!'))

    def _create_categories(self):
        """Create story categories based on crawled content."""
        category_data = [
            {
                'name': 'Folktales & Oral Traditions',
                'description': 'Traditional stories passed down through generations, featuring animals, heroes, and moral lessons.',
                'icon': '📖',
                'color': '#8B4513',
            },
            {
                'name': 'Kingdoms & Chiefdoms',
                'description': 'Stories about Cameroon\'s ancient kingdoms, royal families, and traditional governance.',
                'icon': '👑',
                'color': '#DAA520',
            },
            {
                'name': 'Cultural Practices',
                'description': 'Traditional customs, ceremonies, and ways of life of Cameroon\'s diverse ethnic groups.',
                'icon': '🎭',
                'color': '#CD853F',
            },
            {
                'name': 'Historical Events',
                'description': 'Important historical events, colonial history, and the journey to independence.',
                'icon': '📜',
                'color': '#8B0000',
            },
            {
                'name': 'Nature & Ecology',
                'description': 'Stories about Cameroon\'s diverse ecosystems, wildlife, and natural wonders.',
                'icon': '🌿',
                'color': '#228B22',
            },
            {
                'name': 'Art & Craftsmanship',
                'description': 'Traditional arts, crafts, and artistic expressions of Cameroon\'s peoples.',
                'icon': '🎨',
                'color': '#4B0082',
            },
            {
                'name': 'Proverbs & Wisdom',
                'description': 'Traditional sayings and wisdom passed down through generations.',
                'icon': '💬',
                'color': '#FF8C00',
            },
            {
                'name': 'Music & Dance',
                'description': 'Traditional music, dance forms, and their cultural significance.',
                'icon': '🥁',
                'color': '#DC143C',
            },
        ]
        
        categories = {}
        for data in category_data:
            category, created = StoryCategory.objects.get_or_create(
                name=data['name'],
                defaults=data
            )
            categories[data['name']] = category
            if created:
                self.stdout.write(f'  Created category: {data["name"]}')
        
        return categories

    def _create_stories(self, author, categories):
        """Create stories based on crawled content from discover-cameroon.com."""
        
        stories = [
            # Folktales & Oral Traditions
            {
                'title': 'The Legend of Mount Mbapit\'s Crater Lake',
                'content': '''# The Legend of Mount Mbapit's Crater Lake

Deep in the western highlands of Cameroon, where the mist clings to ancient mountains and the air smells of fresh earth and wildflowers, there lies a mystery that has puzzled travelers for generations.

## The Sacred Lake

Mount Mbapit, standing at 1,900 meters above sea level, holds within its crater a lake of such strange properties that locals speak of it with reverence and awe. The lake's waters are crystal clear, reflecting the sky like a perfect mirror, but there is something extraordinary about this body of water.

## The Impossible Challenge

According to ancient legend, **stones thrown into the crater lake never touch the water**. No matter how heavy the stone, no matter how forcefully it is thrown, the water remains undisturbed. Travelers have tried for centuries to prove the legend wrong, but each time, the stone seems to vanish before reaching the surface.

## The Elder's Explanation

The elders of the surrounding villages tell a different story. They say the lake is protected by ancient spirits who guard the mountain. The spirits, they say, catch every stone before it can disturb the sacred waters. Some say the spirits are the ancestors of the Bamileke people, watching over their descendants from above.

## A Test of Faith

For the Bamileke people, the lake represents more than a natural wonder—it is a test of faith and respect for nature. Those who approach the lake with humility and reverence are said to receive blessings, while those who come with arrogance or doubt are met with misfortune.

## The Journey Today

Today, visitors can hike to the summit of Mount Mbapit and witness this phenomenon for themselves. The journey takes several hours through dense forest, but the reward is a view that takes your breath away—and a mystery that will stay with you long after you descend.

*Will you be the one to finally make a stone touch the waters of Mbapit?*''',
                'summary': 'Discover the mysterious crater lake of Mount Mbapit where stones supposedly never touch the water, protected by ancient spirits of the Bamileke people.',
                'language': 'en',
                'region': 'West Region',
                'tags': 'legend,mystery,mountain,lake,bamileke,spiritual',
                'cultural_context': 'This legend is deeply rooted in Bamileke culture, representing the spiritual connection between the people and their natural environment. The lake serves as a reminder of the sacredness of nature and the importance of humility.',
                'moral_lesson': 'True strength lies in humility and respect for nature, not in attempting to conquer or control it.',
                'source': 'Discover Cameroon Tourism Website',
                'categories': ['Folktales & Oral Traditions', 'Nature & Ecology'],
            },
            {
                'title': 'The Ba\'aka Pygmies: Keepers of the Forest',
                'content': '''# The Ba\'aka Pygmies: Keepers of the Forest

In the heart of the Dja Reserve, where ancient trees tower overhead and the forest floor is carpeted with fallen leaves, lives a people whose connection to the land stretches back thousands of years.

## The Forest People

The Ba\'aka people are among the oldest forest dwellers in Cameroon. Their name means "people of the forest," and they have earned this title through generations of living in harmony with one of Africa's most biodiverse ecosystems.

## A Way of Life

The Ba\'aka live in small encampments deep within the forest. Their life is intimately connected to the exploitation of forest resources:

- **Hunting**: Traditional hunting provides animal proteins
- **Fishing**: Rivers and streams provide sustenance
- **Gathering**: Medicinal herbs, food plants, and forest products

## The Djengui Dance

One of the most important spiritual practices of the Ba\'aka is the **Djengui dance**. This sacred ceremony connects the dancers with the spirit of the forest. Through rhythmic movement and chanting, the Ba\'aka believe they can communicate with the spirits that inhabit the trees, rivers, and mountains.

## Traditional Knowledge

The Ba\'aka possess extraordinary knowledge of:

- **Medicinal plants**: They can identify hundreds of plants with healing properties
- **Animal behavior**: Their tracking skills are legendary
- **Forest navigation**: They can navigate through dense forest without maps
- **Weather prediction**: They read natural signs to predict weather changes

## Modern Challenges

Today, the Ba\'aka face challenges from:

- Deforestation and habitat loss
- Agricultural encroachment
- Climate change affecting forest ecosystems
- Cultural assimilation pressures

## Preserving the Heritage

Conservation efforts in the Dja Reserve, a UNESCO World Heritage Site, help protect both the forest and the Ba\'aka way of life. The reserve covers nearly 526,000 hectares and is home to extraordinary biodiversity, including gorillas, chimpanzees, and forest elephants.

## The Djengui Connection

When visitors join the Ba\'aka in their traditional camps, they often participate in the Djengui dance. This experience is described as transformative—a chance to feel the ancient connection between humans and the natural world.

*The Ba\'aka teach us that true wealth lies not in material possessions, but in the richness of our relationship with the earth.*''',
                'summary': 'Learn about the Ba\'aka Pygmies, the ancient forest people of Cameroon\'s Dja Reserve, their sacred Djengui dance, and their extraordinary knowledge of the natural world.',
                'language': 'en',
                'region': 'South Region',
                'tags': 'baaka,pygmies,forest,tradition,dance,ecology,indigenous',
                'cultural_context': 'The Ba\'aka people represent one of the oldest continuous cultures in Central Africa. Their intimate knowledge of the forest ecosystem has been developed over millennia and represents an irreplaceable cultural heritage.',
                'moral_lesson': 'Harmony with nature brings wisdom and sustenance that no amount of technology can replace.',
                'source': 'Discover Cameroon Tourism Website - Dja Reserve Tour',
                'categories': ['Cultural Practices', 'Nature & Ecology'],
            },
            {
                'title': 'The Bamileke: Guardians of the Highlands',
                'content': '''# The Bamileke: Guardians of the Highlands

In the western highlands of Cameroon, where the mountains touch the clouds and the valleys stretch as far as the eye can see, the Bamileke people have built one of Africa's most remarkable civilizations.

## A Kingdom of Art and Architecture

The Bamileke are renowned for their stunning architecture and artistic traditions. Their chiefdoms, some dating back centuries, feature:

- **Magnificent palaces** with intricate carvings and decorations
- **Sacred forests** that serve as spiritual sanctuaries
- **Ceremonial buildings** that host important cultural events

## The Fô'o: The Living King

At the heart of Bamileke society is the **Fô'o**, the traditional king who governs with wisdom and authority. The Fô'o is not just a political leader but a spiritual bridge between the people and their ancestors.

### Powers of the Fô'o:
- **Spiritual authority**: The king can communicate with ancestral spirits
- **Judicial power**: He settles disputes and maintains social harmony
- **Cultural leadership**: He presides over ceremonies and festivals
- **Environmental stewardship**: He protects sacred sites and natural resources

## The Power of Masks

Bamileke masks are among the most recognized art forms in Africa. Each mask tells a story:

- **Elephant masks** represent strength and royalty
- **Bird masks** symbolize communication with the spirit world
- **Ancestor masks** honor those who came before

## Sacred Sites

The Bamileke landscape is dotted with sacred places:

### Lake Baleng
A mysterious lake with waters believed to have healing properties. Pilgrims travel from across the region to bathe in its waters and seek blessings.

### Foreke-Dschang
A sacred forest where ancient trees stand as silent witnesses to centuries of history. Entry is restricted to those who have been properly initiated.

### The Bunker
A natural site that serves as both a forest reserve and a spiritual sanctuary. The plants here are believed to possess medicinal powers.

## The Art of Bead-Making

In Bangoulap, the Pearl Making Centre of Jean Félicien Gacha preserves the ancient art of bead-making. Artisans here create intricate patterns using tiny beads, each design telling a story of Bamileke culture and history.

## Festivals and Celebrations

The Bamileke calendar is marked by numerous festivals:

- **Harvest festivals** celebrating agricultural abundance
- **Initiation ceremonies** marking the transition to adulthood
- **Royal celebrations** honoring the Fô'o
- **Dance festivals** showcasing traditional rhythms

## The Architecture of Power

Bamileke architecture is not just beautiful—it is symbolic:

- **Round buildings** represent the cycle of life
- **Elevated granaries** symbolize prosperity
- **Carved columns** tell stories of the kingdom's history
- **Thatched roofs** connect the people to the earth

## Preserving the Heritage

Today, the Bamileke work to preserve their traditions while embracing modernity:

- **Museums** protect artifacts and tell the kingdom's story
- **Cultural centers** teach traditional arts to young people
- **Tourism initiatives** share Bamileke culture with the world
- **Education programs** ensure knowledge is passed to future generations

*The Bamileke remind us that true civilization is measured not by technology alone, but by the richness of one's culture and the wisdom of one's traditions.*''',
                'summary': 'Explore the magnificent Bamileke kingdom in Cameroon\'s western highlands, their stunning architecture, sacred traditions, and the wisdom of the Fô\'o kings.',
                'language': 'en',
                'region': 'West Region',
                'tags': 'bamileke,kingdom,architecture,art,masks,festival,chieftaincy',
                'cultural_context': 'The Bamileke people have maintained one of Africa\'s most vibrant traditional kingdoms for centuries. Their cultural practices represent a living heritage that continues to evolve while maintaining its core values.',
                'moral_lesson': 'True leadership serves the people and maintains harmony between the human and spiritual worlds.',
                'source': 'Discover Cameroon Tourism Website - Kingdoms & Traditions Tour',
                'categories': ['Kingdoms & Chiefdoms', 'Art & Craftsmanship'],
            },
            {
                'title': 'The Bamoun Sultanate: A Legacy of Innovation',
                'content': '''# The Bamoun Sultanate: A Legacy of Innovation

In the heart of Cameroon's western region lies Foumban, home to one of Africa's most innovative and culturally rich kingdoms—the Bamoun Sultanate.

## The Visionary King Njoya

The story of the Bamoun Sultanate is inseparable from the story of **King Njoya**, a ruler whose vision transformed his kingdom and left a legacy that endures to this day.

### King Njoya's Achievements:

- **Invented a writing system**: Created the Bamoun script, one of the few indigenous African writing systems
- **Built the Royal Palace**: Constructed between 1918-1922, this magnificent structure stands as a testament to Bamoun artistry
- **Established the Royal Museum**: Created a repository of Bamoun history and culture
- **Promoted education**: Established schools and encouraged learning

## The Royal Palace

The Foumban Royal Palace is more than a building—it is a living museum of Bamoun culture:

### Architecture
- **Traditional design** with modern influences
- **Intricate carvings** telling the story of the Bamoun people
- **Royal chambers** that have hosted generations of sultans
- **Ceremonial halls** where important decisions are made

### The Royal Museum
Inside the palace, the Royal Museum houses:
- **Royal artifacts** dating back centuries
- **Historical documents** including King Njoya's writing system
- **Traditional clothing** and ceremonial dress
- **Musical instruments** used in royal ceremonies

## The Bamoun Script

One of King Njoya's most remarkable achievements was the creation of the **Bamoun script**. This writing system:

- **Is one of few indigenous African scripts**
- **Was designed to write the Bamoun language**
- **Features unique characters** inspired by Bamoun culture
- **Represents a triumph of African intellectual achievement**

## The Sultan Today

The current Sultan of Bamoun continues the traditions established by his predecessors:

- **Presides over Friday prayers** at the palace mosque
- **Hosts cultural events** that showcase Bamoun heritage
- **Works with the government** to preserve cultural sites
- **Engages with international organizations** to promote cultural tourism

## The Craft Village

Near the palace, the **Craft Village** is a living testament to Bamoun artistic skill:

### Traditional Crafts:
- **Brass casting**: Creating intricate sculptures and decorative objects
- **Wood carving**: Producing masks and ceremonial items
- **Textile weaving**: Creating traditional fabrics
- **Beadwork**: Producing intricate jewelry and decorations

## Festivals and Celebrations

The Bamoun calendar is marked by numerous celebrations:

- **The New Yam Festival**: Celebrating agricultural abundance
- **The Sultan's Birthday**: A national holiday in the region
- **Cultural Weeks**: Showcasing traditional arts and performances
- **Religious celebrations**: Marking important Islamic dates

## Preserving the Legacy

Today, efforts are underway to preserve the Bamoun heritage:

- **UNESCO recognition**: The Royal Palace is being considered for World Heritage status
- **Digital preservation**: Documents and artifacts are being digitized
- **Education programs**: Teaching young people about Bamoun history
- **Tourism initiatives**: Sharing Bamoun culture with the world

## The Bamoun Message

The Bamoun people have a saying: *"Knowledge is the foundation of greatness."* This belief, embodied by King Njoya and carried forward by his successors, continues to guide the Bamoun people as they navigate the challenges of the modern world while preserving their ancient heritage.

*The Bamoun Sultanate reminds us that African kingdoms were not just centers of power, but also centers of innovation, learning, and cultural achievement.*''',
                'summary': 'Discover the Bamoun Sultanate of Foumban, where King Njoya invented a writing system and built a royal palace that stands as a testament to African innovation and cultural achievement.',
                'language': 'en',
                'region': 'West Region',
                'tags': 'bamoun,foumban,njoya,sultanate,palace,museum,script,innovation',
                'cultural_context': 'The Bamoun Sultanate represents one of Africa\'s most remarkable examples of cultural innovation. King Njoya\'s invention of a writing system challenges colonial narratives about African intellectual capacity.',
                'moral_lesson': 'Innovation and knowledge are the foundations of lasting greatness, and African civilizations have always been centers of learning and achievement.',
                'source': 'Discover Cameroon Tourism Website - Kingdoms & Traditions Tour',
                'categories': ['Kingdoms & Chiefdoms', 'Art & Craftsmanship', 'Historical Events'],
            },
            {
                'title': 'Bimbia: Where Memory Lives',
                'content': '''# Bimbia: Where Memory Lives

On the shores of the Atlantic Ocean, near the city of Limbe, lies a place of profound historical significance—**Bimbia**, a former slave trade station that still bears the scars of one of humanity's darkest chapters.

## A Place of Pain

Bimbia was discovered in 1987, but its history stretches back centuries. This coastal village was one of many stations along the West African coast where enslaved people were held before being shipped across the Atlantic.

### What Remains:
- **Slave quarters**: Buildings where captives were kept in chains
- **Padlocks and chains**: Physical evidence of the brutal treatment
- **Oil mills**: Where slave labor was used to produce palm oil
- **Tattooing rooms**: Where slaves were marked according to their buyers' specifications

## The Doors of No Return

Perhaps the most haunting feature of Bimbia are the **"Doors of No Return"**—two doors through which enslaved people passed on their way to the ships that would carry them away from their homeland forever.

### First Door of No Return
The original entrance to the slave quarters, through which captives entered the holding area.

### Second Door of No Return
The final exit point, leading to the ships waiting in the harbor. For those who passed through, there was no going back.

## The Ships

From Bimbia's shores, approximately **166 slave ships** departed for foreign destinations. These ships carried thousands of enslaved Africans to the Americas and the Caribbean.

## The German Canons

Along the coastline, **German canons** still point toward Nichols' Island, where stubborn slaves were kept. These weapons of war stand as silent witnesses to the violence of the colonial era.

## Faith and Resistance

Despite the horrors of slavery, Bimbia also represents a story of faith and resistance:

### The First Baptist Church
Founded in **1843 by Joseph Merrick**, this was the first Baptist church in Cameroon. It represents the introduction of Christianity to the region and the hope it brought to many.

### The Alfred Saker Monument
Alfred Saker was a missionary who worked to end the slave trade and educate former slaves. His monument honors his contributions to Cameroon's history.

## The Nature Trail

Beyond its historical significance, Bimbia offers a remarkable natural experience:

### Virgin Forest
A real intact virgin forest with:
- **Medicinal plants** used by traditional healers
- **Fruit trees** providing sustenance
- **Diverse wildlife** including birds and small mammals

### Coastal Beauty
The shores of Bimbia offer:
- **Black sand beaches** unique to this region
- **Ocean views** that stretch to the horizon
- **Fishing villages** where traditional ways of life continue

## The Spiritual Retreat Centre

Along the seashore, near Nichols' Island, stands the **Spiritual Retreat Centre of Basel Mission**. This peaceful sanctuary offers visitors a place to reflect on the history they have witnessed and find spiritual renewal.

## Visiting Bimbia

Today, visitors can:

- **Tour the historical sites** with expert guides
- **Walk through the slave quarters** and feel the weight of history
- **Visit the Doors of No Return** and honor those who passed through
- **Explore the nature trail** and discover the forest's secrets
- **Reflect at the spiritual retreat centre** and find peace

## The Lesson of Bimbia

Bimbia teaches us that:

1. **History must be remembered**: Even painful history deserves to be preserved
2. **Resilience is real**: The human spirit can endure unimaginable suffering
3. **Hope persists**: From the darkest times, faith and community can emerge
4. **Nature endures**: Despite human cruelty, the forest continues to grow

*Bimbia is not just a place to visit—it is a place to remember, to reflect, and to commit to building a more just world.*''',
                'summary': 'Visit Bimbia, a historic slave trade port near Limbe, where the "Doors of No Return" and other remnants tell the story of Cameroon\'s colonial history and the resilience of the human spirit.',
                'language': 'en',
                'region': 'Southwest Region',
                'tags': 'bimbia,slavery,colonial,history,limbe,memory,resilience',
                'cultural_context': 'Bimbia represents a crucial chapter in Cameroon\'s history, connecting the country to the broader narrative of the African diaspora. The site serves as both a memorial and a place of healing.',
                'moral_lesson': 'Even in the darkest chapters of history, the human spirit finds ways to endure, resist, and ultimately triumph.',
                'source': 'Discover Cameroon Tourism Website - Historical Tourism Tour',
                'categories': ['Historical Events', 'Nature & Ecology'],
            },
            {
                'title': 'The Mysterious Lakes of Manengouba',
                'content': '''# The Mysterious Lakes of Manengouba

High in the Manengouba Mountains, at an altitude of 2,411 meters, lie two lakes that have captured the imagination of travelers and locals alike—the **Male Lake** and the **Female Lake**.

## The Twin Lakes

The Manengouba Mountains, located near Nkongsamba in the Littoral Region, are home to two extraordinary lakes that sit side by side, yet are strikingly different.

### The Female Lake
- **Blue waters** that shimmer in the sunlight
- **Shape**: Like an upside-down map of the African continent
- **Character**: Calm, serene, inviting

### The Male Lake
- **Green waters** that reflect the surrounding forest
- **Location**: Between two walls of stone
- **Character**: Mysterious, powerful, untamed

## The Legend

Local legend tells of a time when the lakes were one. A great conflict divided the waters, creating two separate bodies that represent the male and female principles of existence.

### The Male Principle
- Represents **strength and protection**
- Associated with **hunting and fishing**
- Connected to **the forest and its spirits**

### The Female Principle
- Represents **nurturing and fertility**
- Associated with **agriculture and family**
- Connected to **the earth and its bounty**

## The Shape of Africa

The Female Lake's most remarkable feature is its shape. When viewed from above, it clearly resembles an **upside-down map of the African continent**. This geographical coincidence has led many to believe that the lakes hold special significance for all of Africa.

## The Bororo People

Not far from the Manengouba Mountains live the **Bororo people**, a traditionally nomadic group known for:

- **Seasonal migrations** in search of pasture for their livestock
- **Rich musical traditions** featuring unique instruments
- **Elaborate hairstyles** that indicate social status
- **Deep knowledge** of the mountain ecosystem

## The Hike

Reaching the lakes requires a challenging but rewarding hike:

### The Trail
- **Duration**: Several hours
- **Difficulty**: Moderate to challenging
- **Terrain**: Forest, rocky paths, steep ascents

### What You'll See
- **Diverse vegetation** from tropical to alpine
- **Wildlife** including birds and small mammals
- **Stunning views** of the surrounding countryside
- **The lakes themselves**—a sight you'll never forget

## The Spiritual Significance

For the local communities, the lakes are more than a natural wonder:

### Sacred Waters
- The lakes are believed to have **healing properties**
- **Pilgrimages** are made to the lakes for blessings
- **Rituals** are performed at the water's edge
- **Offerings** are sometimes left for the spirits

### Environmental Importance
- The lakes help **regulate water flow** in the region
- They support **unique ecosystems** found nowhere else
- They serve as **natural laboratories** for scientific study

## The Experience

Visiting the Manengouba Lakes is described as transformative:

### Physical
- The **challenge of the hike** tests your limits
- The **beauty of the landscape** rewards your effort
- The **fresh mountain air** invigorates your body

### Emotional
- The **serenity of the lakes** calms your mind
- The **grandeur of the mountains** inspires awe
- The **connection with nature** heals your spirit

### Spiritual
- The **mystery of the lakes** opens your imagination
- The **ancient legends** connect you to the past
- The **sacred atmosphere** invites reflection

## Preserving the Mystery

Today, efforts are underway to protect the Manengouba ecosystem:

- **Conservation programs** protect the forests
- **Sustainable tourism** ensures access for future generations
- **Research initiatives** study the lakes' unique properties
- **Cultural preservation** keeps the legends alive

*The Manengouba Lakes remind us that the natural world is full of mysteries waiting to be discovered—and that some mysteries are best experienced, not explained.*''',
                'summary': 'Discover the mysterious Male and Female Lakes of Manengouba, where one lake is shaped like Africa and local legends speak of ancient spirits and divided waters.',
                'language': 'en',
                'region': 'Littoral Region',
                'tags': 'manengouba,lakes,mountain,hiking,nature,legend,spiritual',
                'cultural_context': 'The Manengouba Lakes represent the intersection of natural wonder and cultural mythology. The lakes\' shape and properties have inspired stories and spiritual practices for generations.',
                'moral_lesson': 'Nature often mirrors our own lives in unexpected ways, reminding us of the deep connections between the land and its people.',
                'source': 'Discover Cameroon Tourism Website - Kingdoms & Traditions Tour',
                'categories': ['Nature & Ecology', 'Folktales & Oral Traditions'],
            },
            {
                'title': 'The Ekom-Nkam Waterfalls: Where Tarzan Was Born',
                'content': '''# The Ekom-Nkam Waterfalls: Where Tarzan Was Born

Deep in the heart of a dense, luxurious forest, where the Nkam River plunges 80 meters into a pool of mist and spray, stand the **Ekom-Nkam Waterfalls**—one of Cameroon's most spectacular natural wonders.

## A Hollywood Connection

The Ekom-Nkam Waterfalls gained international fame when they were chosen as the filming location for **"Greystoke: The Legend of Tarzan, Lord of the Apes"** and other Tarzan films. The falls provided the perfect backdrop for the legendary tale of a man raised by apes in the African jungle.

## The Falls

### Physical Description
- **Height**: 80 meters (262 feet)
- **River**: Nkam River
- **Surroundings**: Dense tropical forest
- **Accessibility**: Via road from Nkongsamba

### The Experience
When you approach the falls, you feel them before you see them:

1. **The sound**: A thunderous roar that grows louder with each step
2. **The mist**: Fine spray that cools your skin
3. **The sight**: A curtain of white water plunging into green infinity
4. **The feeling**: A sense of awe that words cannot capture

## The Forest

The falls are surrounded by a **dense, luxurious forest** that is home to:

### Flora
- **Towering trees** that form a green canopy
- **Tropical plants** with leaves the size of tables
- **Orchids** and other flowering plants
- **Medicinal herbs** used by local healers

### Fauna
- **Primates** including monkeys and chimpanzees
- **Birds** with colorful plumage and haunting calls
- **Butterflies** that dance in the mist
- **Fish** that swim in the river's pools

## The Legend of Mami Wata

Local legend tells of **Mami Wata**, a water spirit who resides near the falls:

### Her Appearance
- **Beautiful woman** with flowing hair
- **Fish tail** that glimmers in the water
- **Enchanting voice** that calls to travelers

### Her Powers
- **Healing**: She can cure illness and injury
- **Prosperity**: She can bring wealth and fortune
- **Love**: She can capture hearts and inspire passion
- **Danger**: She can also be jealous and vengeful

### The Warning
Locals warn travelers not to swim in the falls after dark, when Mami Wata is most active. Those who ignore this warning may find themselves enchanted—or worse.

## The Hiking Trail

Reaching the falls requires a hike through the forest:

### The Journey
- **Duration**: 30-60 minutes
- **Difficulty**: Easy to moderate
- **Terrain**: Forest paths, some rocky sections

### What You'll See
- **Ancient trees** draped in moss
- **Forest streams** with crystal-clear water
- **Wildlife** going about their daily routines
- **The falls** revealed gradually through the trees

## Cultural Significance

The Ekom-Nkam Waterfalls hold deep cultural significance for the local communities:

### Spiritual Importance
- The falls are considered a **sacred site**
- **Rituals** are performed at the water's edge
- **Offerings** are made to the spirits
- **Pilgrimages** are made for healing and blessing

### Historical Connection
- The falls have been **worshipped for centuries**
- **Stories and legends** surround the site
- **Traditional practices** continue to this day
- **Cultural identity** is tied to the falls

## Visiting the Falls

### Best Time to Visit
- **Dry season** (November-February): Best visibility
- **Rainy season**: Highest water flow, most dramatic

### What to Bring
- **Comfortable shoes** for hiking
- **Rain jacket** (the mist can be heavy)
- **Camera** (but protect it from moisture)
- **Water and snacks** for the hike

### Tips for Visitors
1. **Hire a local guide** for safety and cultural context
2. **Respect the sacred nature** of the site
3. **Don't swim** in restricted areas
4. **Take only photos**, leave only footprints

## The Tarzan Experience

For fans of the Tarzan legend, visiting Ekom-Nkam is a pilgrimage:

- **Stand where Tarzan stood** in the classic films
- **Imagine the jungle** as it was a century ago
- **Feel the mist** that Tarzan felt as he swung through the trees
- **Connect with the wildness** that inspired the legend

*The Ekom-Nkam Waterfalls remind us that nature's beauty can inspire stories that captivate the world—and that some places are so magical, they become part of our collective imagination.*''',
                'summary': 'Discover the spectacular Ekom-Nkam Waterfalls, where Tarzan was filmed, and learn about the Mami Wata water spirit legend that adds mystery to this natural wonder.',
                'language': 'en',
                'region': 'Littoral Region',
                'tags': 'ekom-nkam,waterfalls,tarzan,nature,legend,mami-wata,hiking',
                'cultural_context': 'The Ekom-Nkam Waterfalls represent the intersection of natural beauty, cultural mythology, and global pop culture. The Mami Wata legend adds a layer of spiritual significance to this natural wonder.',
                'moral_lesson': 'Nature has the power to inspire stories that transcend borders and connect people across cultures and generations.',
                'source': 'Discover Cameroon Tourism Website - Kingdoms & Traditions Tour',
                'categories': ['Nature & Ecology', 'Folktales & Oral Traditions'],
            },
            {
                'title': 'The Bamileke Elephant Dance',
                'content': '''# The Bamileke Elephant Dance

In the western highlands of Cameroon, when the harvest is complete and the community gathers to celebrate, a spectacular performance takes place—the **Bamileke Elephant Dance**.

## The Dance

### What It Is
The Elephant Dance is a traditional ceremonial dance performed by the Bamileke people. Dancers wear elaborate costumes adorned with beads, feathers, and animal skins, and move with the grace and power of elephants.

### The Costumes
Each dancer's costume is a work of art:

- **Elephant masks**: Representing strength and royalty
- **Beaded garments**: Creating shimmering patterns
- **Feather headdresses**: Adding height and grandeur
- **Animal skins**: Connecting dancers to nature

### The Movements
The dance movements mimic the behavior of elephants:

1. **The charge**: Dancers rush forward with arms raised
2. **The trumpet**: Callers mimic elephant sounds
3. **The stomp**: Feet strike the ground in powerful rhythms
4. **The turn**: Dancers spin with grace and precision

## The Music

### Instruments
The dance is accompanied by traditional instruments:

- **Drums**: Creating the heartbeat of the performance
- **Horns**: Adding depth and resonance
- **Rattles**: Providing rhythm and texture
- **Voices**: Chanting and singing in harmony

### The Rhythm
The rhythm of the Elephant Dance is unique:

- **Polyrhythmic**: Multiple rhythms playing simultaneously
- **Dynamic**: Changing tempo and intensity
- **Hypnotic**: Drawing listeners into a trance-like state
- **Powerful**: Creating a sense of collective energy

## The Meaning

### Symbolism
The Elephant Dance is rich in symbolism:

- **Strength**: Elephants represent power and resilience
- **Community**: The dance brings people together
- **Tradition**: It connects present to past
- **Spirituality**: It honors the ancestors

### Purpose
The dance serves multiple purposes:

- **Celebration**: Marking important occasions
- **Initiation**: Welcoming new members into the community
- **Healing**: Bringing spiritual and physical wellness
- **Unity**: Strengthening community bonds

## The Ceremony

### Preparation
Before the dance begins:

1. **The community gathers** at the chief's compound
2. **The dancers prepare** their costumes and bodies
3. **The musicians tune** their instruments
4. **The spirits are invoked** through prayer and offerings

### The Performance
The dance unfolds in stages:

1. **The opening**: Slow, rhythmic movements
2. **The build-up**: Increasing speed and intensity
3. **The climax**: Full-power Elephant Dance
4. **The resolution**: Gradual return to calm

### The Celebration
After the dance:

1. **Feasting**: Sharing food and drink
2. **Storytelling**: Sharing tales of the ancestors
3. **Music**: Continuing the celebration
4. **Community**: Strengthening bonds

## The Cultural Significance

### For the Bamileke
The Elephant Dance is more than entertainment:

- **It preserves history**: Each performance tells a story
- **It teaches values**: Strength, community, respect
- **It heals wounds**: Bringing people together in joy
- **It honors the past**: Remembering those who came before

### For Cameroon
The dance represents:

- **Cultural diversity**: Showcasing Bamileke traditions
- **National pride**: Celebrating indigenous heritage
- **Tourism potential**: Attracting visitors to the region
- **Artistic expression**: Displaying creativity and skill

## The Experience

### Watching the Dance
When you witness the Elephant Dance:

- **Feel the rhythm** in your bones
- **See the colors** dance before your eyes
- **Hear the music** echo through the valley
- **Sense the community** united in celebration

### Participating
If invited to participate:

- **Respect the tradition**: Follow the dancers' lead
- **Embrace the rhythm**: Let the music move you
- **Connect with others**: Feel the community spirit
- **Honor the ancestors**: Remember those who came before

## Preserving the Tradition

Today, efforts are underway to ensure the Elephant Dance continues:

- **Teaching young people**: Passing down the movements
- **Documenting performances**: Recording for future generations
- **Supporting artists**: Providing resources for costumes
- **Sharing with the world**: Tourism and cultural exchange

*The Bamileke Elephant Dance reminds us that tradition is not static—it is alive, evolving, and as powerful as the elephants it honors.*''',
                'summary': 'Experience the spectacular Bamileke Elephant Dance, a traditional ceremonial performance where dancers in elaborate costumes move with the power and grace of elephants.',
                'language': 'en',
                'region': 'West Region',
                'tags': 'bamileke,elephant,dance,tradition,festival,ceremony,music',
                'cultural_context': 'The Elephant Dance is one of the most iconic cultural performances of the Bamileke people. It represents the community\'s connection to nature and their reverence for the elephant as a symbol of strength and wisdom.',
                'moral_lesson': 'True power comes not from individual strength, but from the unity and harmony of the community.',
                'source': 'Discover Cameroon Tourism Website - Kingdoms & Traditions Tour',
                'categories': ['Music & Dance', 'Cultural Practices'],
            },
            {
                'title': 'The Sacred Forest of Foreke-Dschang',
                'content': '''# The Sacred Forest of Foreke-Dschang

In the city of Dschang, in Cameroon's West Region, there exists a place where the modern world meets the ancient—a **sacred forest** that has been protected for centuries by the Bamileke people.

## A Forest Apart

### What Makes It Sacred
Foreke-Dschang is not just any forest. It is a place of profound spiritual significance:

- **Protected by tradition**: Entry is restricted to those properly initiated
- **Home to spirits**: Believed to harbor ancestral spirits
- **Source of healing**: Medicinal plants grow within its borders
- **Repository of knowledge**: Ancient wisdom is preserved here

### The Rules
Traditional rules govern the forest:

1. **No hunting**: Animals are protected
2. **No cutting**: Trees cannot be felled
3. **No littering**: The forest must remain pure
4. **No disrespectful behavior**: Sacred protocols must be observed

## The Flora

### Ancient Trees
The forest is home to trees that have stood for centuries:

- **Towering hardwoods**: Reaching toward the sky
- **Medicinal trees**: Used by traditional healers
- **Sacred species**: Believed to house spirits
- **Rare plants**: Found nowhere else in the region

### Medicinal Plants
Healers come to Foreke-Dschang to gather:

- **Fever remedies**: Plants that cure malaria and other illnesses
- **Wound treatments**: Herbs that promote healing
- **Pain relief**: Natural analgesics
- **Spiritual protection**: Plants that ward off evil spirits

## The Fauna

### Protected Animals
The forest provides sanctuary for:

- **Birds**: Including rare species
- **Primates**: Monkeys and baboons
- **Reptiles**: Snakes and lizards
- **Insects**: Butterflies and beetles

### The Spirit Animals
Some animals are believed to be spiritual messengers:

- **The leopard**: Symbol of royalty and power
- **The elephant**: Symbol of wisdom and memory
- **The python**: Symbol of fertility and renewal
- **The eagle**: Symbol of vision and connection to the divine

## The Spiritual Significance

### Ancestral Connection
The forest is believed to be:

- **A gateway to the spirit world**: Where ancestors dwell
- **A place of revelation**: Where visions are received
- **A source of power**: Where spiritual energy is concentrated
- **A repository of memory**: Where the community's history is preserved

### Rituals
Important rituals are performed in the forest:

- **Initiation ceremonies**: Welcoming new members
- **Healing rituals**: Curing illness and injury
- **Harvest celebrations**: Giving thanks for abundance
- **Crisis consultations**: Seeking guidance in difficult times

## The Dschang Connection

### The City
Dschang itself is named after the forest:

- **"Dschang"** means "place of the forest"
- The city grew around the sacred site
- Urban development respects the forest boundaries
- The forest remains the heart of the community

### The People
The people of Dschang have a special relationship with the forest:

- **Guardians**: They protect the forest from harm
- **Beneficiaries**: They receive healing and guidance
- **Custodians**: They pass down knowledge to future generations
- **Ambassadors**: They share the forest's story with the world

## Visiting the Forest

### Who Can Visit
Access to Foreke-Dschang is regulated:

- **Initiates**: Those who have undergone traditional initiation
- **Authorized visitors**: Tourists with proper guides
- **Researchers**: Scientists studying the ecosystem
- **Pilgrims**: Those seeking spiritual healing

### What to Expect
A visit to the forest includes:

1. **Guided tour**: With a knowledgeable local guide
2. **Introduction to the spirits**: Proper protocols are explained
3. **Observation of flora**: Learning about medicinal plants
4. **Spiritual experience**: Connecting with the ancient energy

### What to Bring
- **Respect**: The forest demands proper behavior
- **Openness**: Be prepared for spiritual experiences
- **Appropriate clothing**: Modest and practical
- **Offerings**: Traditional gifts for the spirits

## The Modern Challenge

### Threats
The forest faces modern challenges:

- **Urban expansion**: The city grows around it
- **Climate change**: Affecting plant and animal life
- **Cultural erosion**: Younger generations may not understand its importance
- **Tourism pressure**: Too many visitors could damage the ecosystem

### Conservation
Efforts are underway to protect the forest:

- **Legal protection**: Government regulations
- **Community management**: Local people lead conservation
- **Education programs**: Teaching young people about the forest
- **Sustainable tourism**: Balancing access with protection

## The Lesson of Foreke-Dschang

The sacred forest teaches us:

1. **Respect for nature**: Some places are too special to exploit
2. **Cultural preservation**: Traditional knowledge has value
3. **Spiritual connection**: The natural world is more than material
4. **Community responsibility**: Protecting sacred sites is everyone's duty

*Foreke-Dschang reminds us that in a world of constant change, some things remain constant—and those things deserve our deepest respect.*''',
                'summary': 'Explore the Sacred Forest of Foreke-Dschang, a protected Bamileke sanctuary where ancient trees harbor spirits and medicinal plants hold the secrets of traditional healing.',
                'language': 'en',
                'region': 'West Region',
                'tags': 'sacred-forest,dschang,bamileke,spiritual,healing,nature,tradition',
                'cultural_context': 'Sacred forests represent one of the oldest forms of environmental conservation in Africa. Foreke-Dschang demonstrates how traditional beliefs can protect ecosystems for centuries.',
                'moral_lesson': 'True conservation comes not from laws alone, but from deep cultural respect for the natural world.',
                'source': 'Discover Cameroon Tourism Website - Kingdoms & Traditions Tour',
                'categories': ['Cultural Practices', 'Nature & Ecology'],
            },
        ]
        
        for story_data in stories:
            # Get categories
            category_names = story_data.pop('categories')
            category_objects = []
            for name in category_names:
                if name in categories:
                    category_objects.append(categories[name])
            
            # Create story
            story, created = Story.objects.get_or_create(
                title=story_data['title'],
                defaults={
                    **story_data,
                    'author': author,
                    'status': 'published',
                }
            )
            
            if created:
                # Set categories
                story.categories.set(category_objects)
                self.stdout.write(f'  Created story: {story_data["title"]}')
            else:
                self.stdout.write(f'  Story already exists: {story_data["title"]}')
        
        self.stdout.write(f'\nCreated {len(stories)} stories across {len(categories)} categories')