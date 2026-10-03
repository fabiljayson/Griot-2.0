"""
One-off helper: fill the French catalogue from a literal translation table.

Run from `backend/`:

    DJANGO_SETTINGS_MODULE=config.settings.dev \
        ./.venv-linux/bin/python scripts/translate_fr.py locale/fr/LC_MESSAGES/django.po

Kept in the repository for two reasons. It is the record of *why* a given string
is translated the way it is — a translator editing the `.po` in isolation cannot
see the constraint that produced "Révisez" over "Corrigez". And it makes
re-running `makemessages` after adding strings cheap: the table is the source of
truth, the `.po` is generated from it, and a msgid with no table entry is
reported as untranslated rather than silently left blank.

Plurals use the French rule already written into the catalogue header
(`nplurals=2; plural=(n > 1)`), so singular covers 0 and 1 and plural covers
everything above. French uses the singular form for zero — "0 histoire" — so
the singular entry is what a zero count renders.
"""

import re
import sys

# msgid -> (singular, plural) or msgid -> singular
TRANSLATIONS = {
    # --- Artifact category / content type (museum vocabulary) ---
    'Sculpture': 'Sculpture',
    'Textile': 'Tissu',
    'Musical Instrument': 'Instrument de musique',
    'Jewelry': 'Bijou',
    'Pottery': 'Poterie',
    'Mask': 'Masque',
    'Weapon': 'Arme',
    'Woven Fabric': 'Tissage',
    'Tool': 'Outil',
    'Other': 'Autre',
    'All': 'Tous',
    'Kingdom': 'Royaume',
    'Landmark': 'Site',
    'Artifact': 'Objet d\'art',
    'Legend': 'Légende',

    # --- Story status. "Pending Review" is a queue state, so it keeps the
    #     noun; a bare "En attente" would read as a loading state. ---
    'Draft': 'Brouillon',
    'Pending Review': 'En attente de révision',
    'Published': 'Publié',
    'Rejected': 'Rejeté',
    'Archived': 'Archivé',

    # --- Provenance / origin ---
    'Recorded from a community member': 'Enregistré auprès d\'un membre de la communauté',
    'Transcribed from an oral telling': 'Transcrit à partir d\'un récit oral',
    'From a published collection': 'Issu d\'une collection publiée',
    'Original contribution': 'Contribution originale',
    'Seeded demonstration content': 'Contenu de démonstration prérempli',
    'Unknown': 'Inconnu',

    # --- Consent. These are the labels on a legal record, so they are
    #     deliberately formal and never abbreviated. ---
    'Consent not yet requested': 'Consentement non encore demandé',
    'Consent pending': 'Consentement en attente',
    'Consent granted': 'Consentement accordé',
    'Consent granted with restrictions': 'Consentement accordé avec restrictions',
    'Consent withheld': 'Consentement refusé',

    # --- Rights ---
    'All rights reserved': 'Tous droits réservés',
    'Public domain': 'Domaine public',
    'Undetermined': 'Indéterminé',

    # --- Flag reasons. The flag-form options in story_detail.html title-case
    #     differently from the model choices; both are translated. ---
    'Cultural Inaccuracy': 'Inexactitude culturelle',
    'Inappropriate Content': 'Contenu inapproprié',
    'Copyright Violation': 'Violation de droits d\'auteur',
    'Wrong Category': 'Mauvaise catégorie',
    'Cultural inaccuracy': 'Inexactitude culturelle',
    'Inappropriate content': 'Contenu inapproprié',
    'Copyright violation': 'Violation de droits d\'auteur',
    'Wrong category': 'Mauvaise catégorie',

    # --- Notifications admin ---
    'This message will be delivered to every active reader in their notification inbox. There is no undo: use the notifications list to review what has already been sent.':
        'Ce message sera remis à tous les lecteurs actifs dans leur boîte de notifications. '
        'Aucune annulation n\'est possible : utilisez la liste des notifications pour '
        'voir ce qui a déjà été envoyé.',
    'Send to all readers': 'Envoyer à tous les lecteurs',
    'Send an announcement': 'Envoyer une annonce',

    # --- Admin dashboard ---
    'Admin Dashboard': 'Tableau de bord',
    'Platform overview and moderation tools.': 'Vue d\'ensemble de la plateforme et outils de modération.',
    'Users': 'Utilisateurs',
    '%(counter)s active (30d)': ('%(counter)s actif sur 30 jours', '%(counter)s actifs sur 30 jours'),
    'Stories': 'Récits',
    '%(counter)s pending review': ('%(counter)s en attente de révision', '%(counter)s en attente de révision'),
    'Quizzes': 'Quiz',
    '%(rate)s%% pass rate': '%(rate)s %% de réussite',
    'QR Scans': 'Scans QR',
    '%(counter)s published artifact': ('%(counter)s objet publié', '%(counter)s objets publiés'),
    'New users': 'Nouveaux utilisateurs',
    'New stories': 'Nouveaux récits',
    'Quiz attempts': 'Tentatives de quiz',
    'QR scans': 'Scans QR',
    'Shares': 'Partages',
    'Open flags': 'Signalements ouverts',
    'User Growth (30 days)': 'Croissance des utilisateurs (30 jours)',
    'Stories by Status': 'Récits par statut',
    'Top Storytellers': 'Meilleurs conteurs',
    'Lvl %(level)s': 'Niv. %(level)s',
    'No gamification activity yet.': 'Aucune activité de jeu pour l\'instant.',
    'Top Stories': 'Récits les plus lus',
    'No published stories yet.': 'Aucun récit publié pour l\'instant.',
    'Moderation Queue': 'File de modération',
    'by %(name)s • status: %(status)s': 'par %(name)s • statut : %(status)s',
    '%(counter)s flag': ('%(counter)s signalement', '%(counter)s signalements'),
    '%(counter)s flags': ('%(counter)s signalement', '%(counter)s signalements'),
    'Dismiss flags': 'Classer sans suite',
    'Archive this story and resolve all flags?': 'Archiver ce récit et résoudre tous les signalements ?',
    'Archive story': 'Archiver le récit',
    'Queue is clear — no unresolved flags.': 'File vide — aucun signalement en attente.',

    # --- Artifacts ---
    'Culture': 'Culture',
    'Region': 'Région',
    'Estimated Date': 'Datation estimée',
    'Materials': 'Matériaux',
    'Dimensions': 'Dimensions',
    'Location': 'Emplacement',
    'More views of %(title)s': 'Autres vues de %(title)s',
    'More views': 'Autres vues',
    'Play audio guide': 'Lire le guide audio',
    'Audio guide': 'Guide audio',
    'Listen to the story of this artifact': 'Écoutez l\'histoire de cet objet',
    '%(seconds)ss': '%(seconds) s',
    'No audio guide yet': 'Pas encore de guide audio',
    'Generate a narrated guide so visitors can listen to this artifact\'s story.':
        'Générez un guide narré pour que les visiteurs puissent écouter l\'histoire de cet objet.',
    'Generate audio guide': 'Générer le guide audio',
    'Found this in a museum?': 'Vu dans un musée ?',
    'Scan the QR code beside the artifact to open this page instantly.':
        'Scannez le code QR placé à côté de l\'objet pour ouvrir cette page immédiatement.',
    'Related Stories': 'Récits liés',
    'Museum Artifacts': 'Objets de musées',
    'Cultural objects from Cameroon\'s museums — scan their QR codes on site or explore here.':
        'Des objets culturels des musées camerounais — scannez leurs codes QR sur place ou parcourez-les ici.',
    'No artifacts published yet.': 'Aucun objet publié pour l\'instant.',

    # --- Auth ---
    'DIGITAL HERITAGE PLATFORM': 'PLATEFORME DU PATRIMOINE VIVANT',
    '“Until the lion learns to write, every story will glorify the hunter.”':
        '« Tant que le lion n\'aura pas appris à écrire, chaque histoire glorifiera le chasseur. »',
    '— African Proverb': '— Proverbe africain',
    'Museums': 'Musées',
    'Free': 'Gratuit',
    'Always': 'Toujours',
    'Sign in': 'Se connecter',
    'Welcome back': 'Bon retour',
    'Sign in to continue your journey through living heritage.':
        'Connectez-vous pour poursuivre votre voyage dans le patrimoine vivant.',
    'Your username or password is incorrect. Please try again.':
        'Votre nom d\'utilisateur ou votre mot de passe est incorrect. Veuillez réessayer.',
    'Username': 'Nom d\'utilisateur',
    'your username': 'votre nom d\'utilisateur',
    'Password': 'Mot de passe',
    'New to Griot AI?': 'Nouveau sur Griot AI ?',
    'Create an account': 'Créer un compte',
    'Signed out': 'Déconnecté',
    'You\'re signed out': 'Vous êtes déconnecté',
    'Thanks for visiting. Your reading progress and badges are safe.':
        'Merci de votre visite. Votre progression de lecture et vos badges sont conservés.',
    'Sign in again': 'Se reconnecter',
    'Browse stories': 'Parcourir les récits',
    'Create account': 'Créer un compte',
    'Create your account': 'Créez votre compte',
    'Join the platform keeping Cameroon\'s oral traditions alive.':
        'Rejoignez la plateforme qui garde vivantes les traditions orales du Cameroun.',
    'Email': 'Adresse e-mail',
    'First name': 'Prénom',
    'Last name': 'Nom',
    'At least 8 characters.': 'Au moins 8 caractères.',
    'Confirm password': 'Confirmer le mot de passe',
    'I want to…': 'Je souhaite…',
    'Explore': 'Découvrir',
    'Read, listen & earn badges (Visitor)': 'Lire, écouter et gagner des badges (Visiteur)',
    'Share stories': 'Partager des récits',
    'Submit tales & generate media (Contributor)': 'Proposer des récits et générer des médias (Contributeur)',
    'Already have an account?': 'Vous avez déjà un compte ?',

    # --- Chrome ---
    'Griot AI': 'Griot AI',
    'Digital Heritage Platform': 'Plateforme du patrimoine vivant',
    'Main': 'Principal',
    'Sign out': 'Se déconnecter',
    'Library': 'Bibliothèque',
    'Rewards': 'Récompenses',
    'Profile': 'Profil',
    'Dashboard': 'Tableau de bord',
    'Bottom navigation': 'Navigation inférieure',
    'Interface language': 'Langue de l\'interface',
    'Read this page in %(name)s': 'Lire cette page en %(name)s',
    'Home': 'Accueil',
    'Artifacts': 'Objets',
    'Write a Story': 'Écrire un récit',
    'Story': 'Récit',

    # --- Story card ---
    'Unlike': 'Ne plus aimer',
    'Like': 'J\'aime',
    'Remove bookmark': 'Retirer des favoris',
    'Bookmark': 'Ajouter aux favoris',
    'Read': 'Lire',

    # --- Gamification ---
    'Heritage Rewards': 'Récompenses du patrimoine',
    'Earn XP, unlock badges, and climb the storyteller ranks.':
        'Gagnez de l\'XP, débloquez des badges et montez dans le classement des conteurs.',
    'Level': 'Niveau',
    'Rank #%(rank)s': 'Rang n° %(rank)s',
    '%(xp)s XP to next level': '%(xp)s XP avant le niveau suivant',
    'Stories read': 'Récits lus',
    'Completed': 'Terminés',
    'Quizzes passed': 'Quiz réussis',
    'Day streak': 'Jours consécutifs',
    'Track your heritage journey': 'Suivez votre parcours patrimonial',
    'Sign in to earn XP, collect badges, and appear on the leaderboard.':
        'Connectez-vous pour gagner de l\'XP, collectionner des badges et apparaître au classement.',
    'Badges': 'Badges',
    'All quizzes': 'Tous les quiz',
    'Earned': 'Obtenu',
    '%(xp)s XP': '%(xp)s XP',
    '%(counter)s quiz': ('%(counter)s quiz', '%(counter)s quiz'),
    '%(counter)s read': ('%(counter)s lecture', '%(counter)s lectures'),
    '%(counter)s days': ('%(counter)s jour', '%(counter)s jours'),
    'Locked': 'Verrouillé',
    'Certificates': 'Certificats',
    'Leaderboard': 'Classement',
    'Level %(level)s • %(stories)s read • %(quizzes)s quizzes':
        'Niveau %(level)s • %(stories)s lectures • %(quizzes)s quiz',
    'No XP earned yet — be the first on the board!':
        'Aucun XP gagné pour l\'instant — soyez le premier au classement !',

    # --- Home ---
    'Journey through Cameroon\'s living heritage': 'Voyage à travers le patrimoine vivant du Cameroun',
    '%(name)s\'s Heritage Feed': 'Le fil patrimonial de %(name)s',
    'Journey through Cameroon\'s Living Heritage': 'Voyage à travers le patrimoine vivant du Cameroun',
    'Tales carried by griots, preserved for generations.':
        'Des contes transmis par les griots, préservés de génération en génération.',
    'Explore cultural tales, scan museum artifact QR codes, and earn heritage badges — all in one place.':
        'Explorez des récits culturels, scannez les codes QR des objets de musées et gagnez des badges du patrimoine — au même endroit.',
    '%(counter)s story': ('%(counter)s récit', '%(counter)s récits'),
    '%(counter)s artifact': ('%(counter)s objet', '%(counter)s objets'),
    '%(counter)s languages': ('%(counter)s langue', '%(counter)s langues'),
    'Start Reading': 'Commencer à lire',
    'Tales carried by griots, preserved for generations. Read, listen, and explore the voices of the motherland.':
        'Des contes transmis par les griots, préservés de génération en génération. Lisez, écoutez et explorez les voix de la mère patrie.',
    'Trending Now': 'Tendances',
    'Popular Stories': 'Récits populaires',
    'See all': 'Tout voir',
    'Browse by Category': 'Parcourir par catégorie',
    'Discover Regions': 'Découvrir les régions',
    'What awaits you': 'Ce qui vous attend',
    'Cultural Stories': 'Récits culturels',
    'Explore tales from every corner of Cameroon — from the highlands to the coast.':
        'Explorez des récits de tous les coins du Cameroun — des hautes terres jusqu\'au littoral.',
    'Museum QR Codes': 'Codes QR de musées',
    'Scan artifact codes for immersive digital experiences and hidden histories.':
        'Scannez les codes des objets pour des expériences numériques et des histoires cachées.',
    'Earn Badges': 'Gagnez des badges',
    'Test your knowledge with quizzes, earn XP, and collect heritage certificates.':
        'Testez vos connaissances avec des quiz, gagnez de l\'XP et collectionnez des certificats du patrimoine.',
    'Ready to explore?': 'Prêt à explorer ?',
    'Join thousands discovering Cameroon\'s rich oral traditions.':
        'Rejoignez des milliers de personnes qui découvrent les riches traditions orales du Cameroun.',
    'Get started — it\'s free': 'Commencez — c\'est gratuit',

    # --- Library ---
    'Your Library': 'Votre bibliothèque',
    'Everything you\'ve read, saved, and created.':
        'Tout ce que vous avez lu, enregistré et créé.',
    'Continue Reading': 'Poursuivre la lecture',
    '%(minutes)s min': '%(minutes)s min',
    'Nothing in progress — start a story and it will appear here.':
        'Rien en cours — commencez un récit et il apparaîtra ici.',
    'Bookmarked': 'En favoris',
    'No saved stories yet. Tap the bookmark icon on any story.':
        'Aucun récit enregistré. Touchez l\'icône de favori sur n\'importe quel récit.',
    'Recently Read': 'Lus récemment',
    '%(percent)s%% read': '%(percent)s %% lu',
    'My Stories': 'Mes récits',
    '%(counter)s view': ('%(counter)s vue', '%(counter)s vues'),
    'Edit story': 'Modifier le récit',
    'Edit %(title)s': 'Modifier %(title)s',
    'You haven\'t submitted any stories yet.': 'Vous n\'avez encore proposé aucun récit.',
    'Write your first story': 'Écrire votre premier récit',

    # --- Profile ---
    'Your account, role and heritage journey.':
        'Votre compte, votre rôle et votre parcours patrimonial.',
    '%(counter)s day streak': ('%(counter)s jour consécutif', '%(counter)s jours consécutifs'),
    'Account details': 'Informations du compte',
    'Institution': 'Institution',
    'Museum or archive name': 'Nom du musée ou des archives',
    'Save changes': 'Enregistrer les modifications',
    'Roles are granted by administrators and cannot be changed here.':
        'Les rôles sont attribués par les administrateurs et ne peuvent pas être modifiés ici.',
    'My library': 'Ma bibliothèque',
    'Write a story': 'Écrire un récit',
    'Rewards & badges': 'Récompenses et badges',
    'Admin dashboard': 'Tableau de bord d\'administration',
    'Permanently delete your account and all associated data? This cannot be undone.':
        'Supprimer définitivement votre compte et toutes les données associées ? Cette action est irréversible.',
    'Delete account': 'Supprimer le compte',

    # --- Quizzes ---
    'Quiz': 'Quiz',
    'Back to story': 'Retour au récit',
    'Knowledge Quiz': 'Quiz de connaissances',
    '%(counter)s question': ('%(counter)s question', '%(counter)s questions'),
    'pass at %(score)s%%': 'réussi à partir de %(score)s %%',
    'earn %(xp)s XP': 'gagnez %(xp)s XP',
    '%(minutes)s min limit': 'limite de %(minutes)s min',
    'Ready to test your knowledge?': 'Prêt à tester vos connaissances ?',
    'Answer %(counter)s question about this story.': (
        'Répondez à %(counter)s question sur ce récit.',
        'Répondez à %(counter)s questions sur ce récit.',
    ),
    'Score %(score)s%% or higher to earn %(xp)s XP and level up.':
        'Obtenez %(score)s %% ou plus pour gagner %(xp)s XP et monter de niveau.',
    'Start quiz': 'Commencer le quiz',
    'Question %(number)s of %(total)s': 'Question %(number)s sur %(total)s',
    '%(counter)s answered': ('%(counter)s réponse', '%(counter)s réponses'),
    'Submit answer': 'Valider la réponse',
    'All questions answered!': 'Toutes les questions ont une réponse !',
    'Submit your answers to see your score.': 'Validez vos réponses pour voir votre score.',
    'See results': 'Voir les résultats',
    'Passed': 'Réussi',
    'Try again': 'Réessayer',
    'Congratulations!': 'Félicitations !',
    'Keep learning!': 'Continuez à apprendre !',
    '%(correct)s of %(total)s correct in %(seconds)ss':
        '%(correct)s bonnes réponses sur %(total)s en %(seconds) s',
    '+%(xp)s XP earned': '+%(xp)s XP gagnés',
    'Review answers': 'Revoir les réponses',
    'Correct': 'Correcte',
    'Incorrect (answer: %(letter)s)': 'Incorrecte (réponse : %(letter)s)',
    'Retake quiz': 'Refaire le quiz',
    'View rewards': 'Voir les récompenses',
    'Knowledge Quizzes': 'Quiz de connaissances',
    'Test what the stories taught you — pass to earn XP.':
        'Vérifiez ce que les récits vous ont appris — réussissez pour gagner de l\'XP.',
    'Passed with %(score)s%%': 'Réussi avec %(score)s %%',
    'Last try: %(score)s%%': 'Dernier essai : %(score)s %%',
    'Take quiz': 'Faire le quiz',
    'Read story': 'Lire le récit',
    'No quizzes published yet — read a story and check back soon.':
        'Aucun quiz publié pour l\'instant — lisez un récit et revenez bientôt.',

    # --- Stories discovery ---
    'Search stories…': 'Rechercher des récits…',
    'Clear search': 'Effacer la recherche',
    'Filters': 'Filtres',
    'Toggle filters': 'Afficher les filtres',
    'Language': 'Langue',
    'Category': 'Catégorie',
    'Sort by': 'Trier par',
    'Clear all': 'Tout effacer',
    'Results for "%(term)s"': 'Résultats pour « %(term)s »',
    'Discover Stories': 'Découvrir les récits',
    'No stories found for "%(term)s"': 'Aucun récit trouvé pour « %(term)s »',
    'No stories yet. Be the first to share!': 'Aucun récit pour l\'instant. Soyez le premier à partager !',
    'Browse all stories': 'Parcourir tous les récits',

    # --- Consent (legal record — deliberately formal) ---
    'Reviewer\'s note': 'Note du modérateur',
    'Consent on record: %(status)s': 'Consentement enregistré : %(status)s',
    'Basis:': 'Base :',
    'Recorded by %(name)s': 'Enregistré par %(name)s',
    'on %(date)s': 'le %(date)s',
    'Decision': 'Décision',
    'Basis': 'Base',
    'required': 'obligatoire',
    'Who you spoke to, and what they said. This is what defends the decision later.':
        'À qui vous avez parlé, et ce qu\'il ou elle a dit. C\'est ce qui défendra la décision plus tard.',
    'Rights holder': 'Détenteur des droits',
    'Leave unchanged to keep the current value': 'Laisser vide pour conserver la valeur actuelle',
    'Licence': 'Licence',
    'Record consent decision': 'Enregistrer la décision de consentement',
    'Recording “withheld” on a published story archives it. The record is kept, never deleted.':
        'Enregistrer « refusé » sur un récit publié l\'archive. L\'enregistrement est conservé, jamais supprimé.',
    'I have asked the community about this story': 'J\'ai interrogé la communauté au sujet de ce récit',
    'Records that you asked. What the community answered is recorded by a moderator, who has to record who they spoke to and on what basis.':
        'Enregistre que vous avez posé la question. Ce que la communauté a répondu est enregistré par un modérateur, qui doit indiquer à qui il a parlé et sur quelle base.',
    'Consent on record:': 'Consentement enregistré :',
    '%(status)s.': '%(status)s.',
    'Only a moderator can change this — ask one to update it if it is wrong.':
        'Seul un modérateur peut le modifier — demandez à l\'un d\'eux de le corriger si c\'est inexact.',

    # --- Story detail ---
    '%(minutes)s min read': '%(minutes)s min de lecture',
    'You\'re %(percent)s%% through this story.': 'Vous avez lu %(percent)s %% de ce récit.',
    'Play narration': 'Lire la narration',
    'Listen to this story': 'Écouter ce récit',
    'No narration yet': 'Pas encore de narration',
    'Generate an AI voice-over so visitors can listen to this tale.':
        'Générez une voix off par IA pour que les visiteurs puissent écouter ce récit.',
    'Generate narration': 'Générer la narration',
    'Your browser does not support video playback.':
        'Votre navigateur ne prend pas en charge la lecture vidéo.',
    'Generating video…': 'Génération de la vidéo…',
    'Luma AI is bringing this tale to life — this page updates automatically.':
        'Luma AI donne vie à ce récit — cette page se met à jour automatiquement.',
    'Make it move': 'Animez-le',
    'Generate an AI video of this story with Luma Dream Machine.':
        'Générez une vidéo IA de ce récit avec Luma Dream Machine.',
    'Generate video': 'Générer la vidéo',
    'Cultural Context': 'Contexte culturel',
    'Moral Lesson': 'Enseignement moral',
    'Test your knowledge': 'Testez vos connaissances',
    'earn %(xp)s XP if you pass': 'gagnez %(xp)s XP si vous réussissez',
    'Take the quiz': 'Faire le quiz',
    'Sign in to take quiz': 'Connectez-vous pour faire le quiz',
    'Saved': 'Enregistré',
    'Save': 'Enregistrer',
    'Share': 'Partager',
    'Report': 'Signaler',
    'Reading progress is saved automatically': 'La progression de lecture est enregistrée automatiquement',
    'Edit': 'Modifier',
    'Share story': 'Partager le récit',
    'Share this story': 'Partager ce récit',
    'Report story': 'Signaler le récit',
    'Report this story': 'Signaler ce récit',
    'Reason': 'Motif',
    'Details': 'Détails',
    'Tell us more…': 'Dites-nous en plus…',
    'Submit report': 'Envoyer le signalement',

    # --- Video sheet ---
    'Generate AI video': 'Générer une vidéo IA',
    'Scene prompt': 'Description des scènes',
    'Describe the scenes: village square at dusk, talking drum circle, baobab silhouette…':
        'Décrivez les scènes : place du village au crépuscule, cercle de tambours parlants, silhouette de baobab…',
    'Leave empty to auto-generate a prompt from the story.':
        'Laissez vide pour générer automatiquement une description à partir du récit.',
    'Start generation': 'Lancer la génération',

    # --- Story form ---
    'New Story': 'Nouveau récit',
    'Back to library': 'Retour à la bibliothèque',
    'Edit Story': 'Modifier le récit',
    'Tell a New Story': 'Racontez un nouveau récit',
    'Update your tale — you can save a draft or resubmit for review.':
        'Mettez à jour votre récit — vous pouvez enregistrer un brouillon ou le soumettre à nouveau pour révision.',
    'Share a tale carried by your community. Save as a draft or submit for review.':
        'Partagez un récit transmis par votre communauté. Enregistrez-le comme brouillon ou soumettez-le pour révision.',
    'Story Title': 'Titre du récit',
    'e.g. The Tortoise and the Clever Antelope': 'ex. La Tortue et l\'Antelope rusée',
    'Summary': 'Résumé',
    'A short teaser shown on story cards (max 500 characters)':
        'Une courte accroche affichée sur les cartes de récit (500 caractères max.)',
    'Story Content (Markdown)': 'Contenu du récit (Markdown)',
    'Preview': 'Aperçu',
    'Estimated read time is calculated automatically when you save.':
        'Le temps de lecture estimé est calculé automatiquement à l\'enregistrement.',
    'Region of Origin': 'Région d\'origine',
    'e.g. Northwest Region': 'ex. Région du Nord-Ouest',
    'Tags': 'Étiquettes',
    'folklore, animals, wisdom — comma separated': 'folklore, animaux, sagesse — séparées par des virgules',
    'Categories': 'Catégories',
    'Historical and cultural background for this tale':
        'Contexte historique et culturel de ce récit',
    'The teaching this story carries': 'L\'enseignement que porte ce récit',
    'Source': 'Source',
    'Original teller, village, or publication': 'Conteur d\'origine, village ou publication',
    'Where this story comes from': 'D\'où vient ce récit',
    'This is a rendering of someone\'s tradition, not our property. Readers see this information, so please be accurate — “I don\'t know yet” is a better answer than a guess. A moderator records consent separately, after checking with the community.':
        'Il s\'agit d\'une restitution de la tradition de quelqu\'un, pas de notre propriété. Les lecteurs voient ces informations : soyez donc précis — « je ne sais pas encore » vaut mieux qu\'une supposition. Un modérateur enregistre le consentement séparément, après avoir consulté la communauté.',
    'Origin': 'Origine',
    'Rights Holder': 'Détenteur des droits',
    'Person or community who holds the rights': 'Personne ou communauté détenant les droits',
    'Recorded On': 'Enregistré le',
    'How This Version Was Obtained': 'Comment cette version a été obtenue',
    'e.g. Recorded in Bafoussam in 2019 with the village elder\'s permission; translated from the Lamnso original.':
        'ex. Enregistré à Bafoussam en 2019 avec l\'autorisation du notable du village ; traduit à partir de l\'original en lamnso.',
    'Save Draft': 'Enregistrer le brouillon',
    'Submit for Review': 'Soumettre pour révision',
    'Permanently delete “%(title)s”? This cannot be undone.':
        'Supprimer définitivement « %(title)s » ? Cette action est irréversible.',
    'Delete story': 'Supprimer le récit',

    # --- Roles ---
    'Visitor': 'Visiteur',
    'Contributor': 'Contributeur',
    'Institution Manager': 'Responsable d\'institution',
    'Admin': 'Administrateur',

    # --- Flash messages ---
    'Thanks — our moderators will review this story.':
        'Merci — nos modérateurs examineront ce récit.',
    'Check out "%(title)s" on Griot AI! 🌍📖':
        'Découvrez « %(title)s » sur Griot AI ! 🌍📖',
    'No active attempt.': 'Aucune tentative en cours.',
    '🎉 You passed and earned %(xp)s XP!': '🎉 Vous avez réussi et gagné %(xp)s XP !',
    'Scored %(score)s%% — try again at %(passing)s%% to pass.':
        'Score de %(score)s %% — réessayez pour atteindre les %(passing)s %% requis.',
    'action must be "remove" or "dismiss".': 'l\'action doit être « remove » ou « dismiss ».',
    'Story "%(title)s" archived and flags resolved.':
        'Récit « %(title)s » archivé et signalements traités.',
    'Flags on "%(title)s" dismissed.':
        'Signalements sur « %(title)s » classés sans suite.',
    'Consent request recorded — awaiting the community\'s answer.':
        'Demande de consentement enregistrée — en attente de la réponse de la communauté.',
    'Consent withheld — the story has been archived.':
        'Consentement refusé — le récit a été archivé.',
    'Consent recorded for "%(title)s".': 'Consentement enregistré pour « %(title)s ».',
    'Title and content are required.': 'Le titre et le contenu sont obligatoires.',
    'Story "%(title)s" deleted.': 'Récit « %(title)s » supprimé.',
    'Profile updated.': 'Profil mis à jour.',
    'Account "%(username)s" and associated data deleted.':
        'Compte « %(username)s » et données associées supprimés.',
    'Welcome to Griot AI, %(username)s!': 'Bienvenue sur Griot AI, %(username)s !',

    # --- Sort options ---
    'Newest': 'Plus récents',
    'Oldest': 'Plus anciens',
    'Most Viewed': 'Plus consultés',
    'Most Liked': 'Plus aimés',

    # --- Service errors ---
    'Invalid answer.': 'Réponse invalide.',
    'No active attempt — start the quiz first.':
        'Aucune tentative en cours — commencez d\'abord le quiz.',
    'Question already answered.': 'Question déjà répondue.',
    'Story saved as draft.': 'Récit enregistré comme brouillon.',
    'Story submitted for review.': 'Récit soumis pour révision.',
    'A user with this email already exists.': 'Un utilisateur avec cette adresse e-mail existe déjà.',
    'Username is required.': 'Le nom d\'utilisateur est obligatoire.',
    'An account with those details already exists. Try a different username or email.':
        'Un compte avec ces informations existe déjà. Essayez un autre nom d\'utilisateur ou une autre adresse e-mail.',
    'Password must be at least 8 characters.':
        'Le mot de passe doit contenir au moins 8 caractères.',
    'Passwords do not match.': 'Les mots de passe ne correspondent pas.',
}


def po_escape(value):
    return value.replace('\\', '\\\\').replace('"', '\\"')


# One or more consecutive `msgstr` / `msgstr[N]` lines, each possibly wrapped
# across several quoted lines. The trailing newline is optional because the last
# block in a split file has none — requiring it made the run stop after
# `msgstr[0]` and leave a duplicate `msgstr[1]` behind, which msgfmt rejects.
MSGSTR_RUN = re.compile(
    r'^(?:msgstr(?:\[\d+\])? (?:(?:"(?:[^"\\]|\\.)*"\s*)+)\n?)+', re.M,
)


def po_unquote(block):
    """Concatenate a (possibly multi-line) quoted value and decode its escapes.

    The msgid on disk is escaped, so `\"` has to become `"` before it can be
    looked up in the table; leaving it escaped silently matched nothing and
    every string containing a quote came back untranslated.
    """
    raw = ''.join(re.findall(r'"((?:[^"\\]|\\.)*)"', block))
    return raw.replace('\\"', '"').replace('\\\\', '\\')


def main(path):
    with open(path, encoding='utf-8') as handle:
        content = handle.read()

    header, _, body = content.partition('\n\n')
    # The header carries the metadata block; give it a real identity so
    # msgfmt and translators are not looking at "PACKAGE VERSION".
    header = header.replace(
        '# SOME DESCRIPTIVE TITLE.\n# Copyright (C) YEAR THE PACKAGE\'S COPYRIGHT HOLDER',
        '# French translation of the Griot AI web interface.\n'
        '# Copyright (C) 2026 the Griot AI contributors',
    ).replace(
        '# FIRST AUTHOR <EMAIL@ADDRESS>, YEAR.',
        '# Track A — see docs/ROADMAP.md, Phase 5.',
    ).replace(
        '#, fuzzy\n', '', 1,
    ).replace(
        '"PO-Revision-Date: YEAR-MO-DA HO:MI+ZONE\\n"',
        f'"PO-Revision-Date: {__import__("datetime").date.today()} 00:00+0000\\n"',
    ).replace(
        '"Last-Translator: FULL NAME <EMAIL@ADDRESS>\\n"',
        '"Last-Translator: Track A translation table (backend/scripts/translate_fr.py)\\n"',
    ).replace(
        '"Language-Team: LANGUAGE <LL@li.org>\\n"',
        '"Language-Team: French\\n"',
    ).replace(
        '"Project-Id-Version: PACKAGE VERSION\\n"',
        '"Project-Id-Version: Griot AI 0.2.0\\n"',
    ).replace(
        '"Language: \\n"', '"Language: fr\\n"',
    )

    entries = body.split('\n\n')
    missing = []
    translated = 0
    out = []
    for entry in entries:
        if not entry.strip():
            continue
        msgid_match = re.search(
            r'^msgid ((?:"(?:[^"\\]|\\.)*"\s*)+)', entry, re.M,
        )
        if not msgid_match:
            out.append(entry)
            continue
        msgid = po_unquote(msgid_match.group(1))
        if not msgid:
            out.append(entry)
            continue

        plural_match = re.search(
            r'^msgid_plural ((?:"(?:[^"\\]|\\.)*"\s*)+)', entry, re.M,
        )
        value = TRANSLATIONS.get(msgid)
        if value is None:
            missing.append(msgid)
            out.append(entry)
            continue

        if plural_match:
            singular, plural = value if isinstance(value, tuple) else (value, value)
            # Replace the whole run of msgstr[N] lines, not just the first —
            # `msgstr[0]` alone left the old `msgstr[1]` behind and msgfmt
            # rejected the file with "plural form has wrong index".
            entry = MSGSTR_RUN.sub(
                lambda _m: (
                    f'msgstr[0] "{po_escape(singular)}"\n'
                    f'msgstr[1] "{po_escape(plural)}"\n'
                ),
                entry, count=1,
            )
        else:
            entry = MSGSTR_RUN.sub(
                lambda _m: f'msgstr "{po_escape(value)}"\n', entry, count=1,
            )
        translated += 1
        out.append(entry)

    with open(path, 'w', encoding='utf-8') as handle:
        handle.write(header + '\n\n' + '\n\n'.join(out))

    print(f'translated {translated} entries')
    if missing:
        print(f'untranslated ({len(missing)}):')
        for msgid in missing:
            print(f'  - {msgid!r}')


if __name__ == '__main__':
    main(sys.argv[1])