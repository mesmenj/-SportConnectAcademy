import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLanguage { french, english }

abstract final class AppLanguageController {
  static const _preferenceKey = 'classcard_language';
  static bool _followsSystem = true;
  static final language = ValueNotifier(_systemLanguage());
  static bool get isEnglish => language.value == AppLanguage.english;
  static AppLanguage _systemLanguage() =>
      WidgetsBinding.instance.platformDispatcher.locale.languageCode
              .toLowerCase() ==
          'fr'
      ? AppLanguage.french
      : AppLanguage.english;

  static Future<void> initialize() async {
    final saved = (await SharedPreferences.getInstance()).getString(
      _preferenceKey,
    );
    _followsSystem = saved == null;
    language.value = switch (saved) {
      'fr' => AppLanguage.french,
      'en' => AppLanguage.english,
      _ => _systemLanguage(),
    };
  }

  static Future<void> setLanguage(AppLanguage value) async {
    _followsSystem = false;
    language.value = value;
    await (await SharedPreferences.getInstance()).setString(
      _preferenceKey,
      value == AppLanguage.english ? 'en' : 'fr',
    );
  }

  static void refreshFromSystem() {
    if (_followsSystem) language.value = _systemLanguage();
  }
}

String tr(String value) {
  if (!AppLanguageController.isEnglish) {
    return value;
  }
  final exact = _english[value];
  if (exact != null) return exact;
  var result = value;
  if (value.startsWith('Jeudi ') && value.endsWith(' août')) {
    return value
        .replaceFirst('Jeudi', 'Thursday')
        .replaceFirst('août', 'August');
  }
  if (value.contains(' joueurs')) {
    result = result.replaceAll(' joueurs', ' players');
  }
  if (value.contains(' séances')) {
    result = result.replaceAll(' séances', ' sessions');
  }
  if (value.startsWith('Bonjour ') && value.endsWith(' 👋')) {
    return value.replaceFirst('Bonjour', 'Hello');
  }
  if (value.startsWith('Enfant ')) {
    return value.replaceFirst('Enfant', 'Child');
  }
  if (value.startsWith('Présence de ')) {
    return value.replaceFirst('Présence de', 'Attendance for');
  }
  if (value.startsWith('Statistiques de ')) {
    return value.replaceFirst('Statistiques de', 'Statistics for');
  }
  final entries = _english.entries.toList()
    ..sort((a, b) => b.key.length.compareTo(a.key.length));
  for (final entry in entries) {
    result = result.replaceAll(entry.key, entry.value);
  }
  return result;
}

String localizedSessionTitle(String value) {
  if (AppLanguageController.isEnglish) return tr(value);
  return value
      .replaceAll('Tennis session', 'Séance de tennis')
      .replaceAll('Paddle session', 'Séance de padel');
}

String remainingSessionsText(int remaining, int total) {
  if (AppLanguageController.isEnglish) {
    if (remaining <= 0) {
      return 'No lessons are currently available for this player.';
    }
    if (remaining <= 3) {
      return 'Only $remaining ${remaining == 1 ? 'lesson is' : 'lessons are'} available for this player.';
    }
    return '$remaining ${remaining == 1 ? 'lesson is' : 'lessons are'} available for this player. Package: $total.';
  }
  if (remaining <= 0) {
    return 'Aucun cours n’est actuellement disponible pour ce joueur.';
  }
  if (remaining <= 3) {
    return 'Il ne reste que $remaining ${remaining == 1 ? 'cours disponible' : 'cours disponibles'} pour ce joueur.';
  }
  return '$remaining ${remaining == 1 ? 'cours disponible' : 'cours disponibles'} pour ce joueur. Forfait : $total.';
}

String playerPackageSummaryText({
  required int total,
  required int remaining,
  required bool activationPending,
}) {
  if (AppLanguageController.isEnglish) {
    return activationPending
        ? 'Package: $total sessions · Activation pending'
        : 'Package: $total sessions · Player lessons: $remaining';
  }
  return activationPending
      ? 'Forfait : $total séances · Activation en attente'
      : 'Forfait : $total séances · Cours du joueur : $remaining';
}

String remainingPlacesText(int remaining) => AppLanguageController.isEnglish
    ? '$remaining ${remaining == 1 ? 'spot' : 'spots'}'
    : '$remaining ${remaining == 1 ? 'place' : 'places'}';

const _english = <String, String>{
  'Ajouter le joueur': 'Add player',
  'Prénom du joueur': "Player's first name",
  'Nom du joueur': "Player's last name",
  'Impossible d’ajouter ce joueur. Réessayez.':
      'Unable to add this player. Try again.',
  'Profils joueurs': 'Player profiles',
  'Facultatif : vous pourrez aussi ajouter d’autres joueurs depuis votre profil.':
      'Optional: you can also add other players from your profile.',
  'Choisissez une séance et un mode de paiement pour chaque joueur.':
      'Choose a session and payment method for each player.',
  'Participants confirmés': 'Confirmed participants',
  'Aucun participant confirmé.': 'No confirmed participants.',
  'Ce joueur possède déjà une réservation pendant cette tranche horaire.':
      'This player already has a booking during this time slot.',
  'La tranche horaire de cette séance est invalide.':
      'This session time slot is invalid.',
  'Accueil': 'Home',
  'Réserver': 'Book',
  'Calendrier': 'Calendar',
  'Tournois': 'Tournaments',
  'Découvrez les prochains tournois.': 'Discover upcoming tournaments.',
  'Profil': 'Profile',
  'Passer': 'Skip',
  'Continuer': 'Continue',
  'Commencer l’aventure': 'Start the adventure',
  'Comment utilisez-vous SportA ?':
      'How do you use SportA?',
  'Choisissez votre espace pour continuer.': 'Choose your space to continue.',
  'Je suis parent ou élève': 'I am a parent or student',
  'Je suis coach': 'I am a coach',
  'Connexion coach': 'Coach sign in',
  'Ce compte n’est pas un compte coach actif. Contactez votre administrateur.':
      'This is not an active coach account. Contact your administrator.',
  'Ce compte est réservé à un autre espace SportA.':
      'This account belongs to another SportA area.',
  'Se connecter pour réserver': 'Sign in to book',
  'Créer mon profil': 'Create my profile',
  'Créer un nouveau profil': 'Create a new profile',
  'J’ai déjà un compte': 'I already have an account',
  'Utilisez votre adresse e-mail et votre mot de passe.':
      'Use your email address and password.',
  'Votre profil protège et personnalise vos réservations.':
      'Your profile protects and personalizes your bookings.',
  'Nom complet': 'Full name',
  'Adresse e-mail': 'Email address',
  'Mot de passe': 'Password',
  'Afficher le mot de passe': 'Show password',
  'Masquer le mot de passe': 'Hide password',
  'Se connecter': 'Sign in',
  'Veuillez patienter...': 'Please wait...',
  'Créer mon profil ou me connecter': 'Create my profile or sign in',
  'Prêt à réserver ?': 'Ready to book?',
  'Découvrez librement SportA. Un profil est nécessaire uniquement pour envoyer une réservation.':
      'Explore SportA freely. A profile is only required when you make a booking.',
  'Créez votre profil ou connectez-vous pour rattacher vos enfants et sécuriser vos réservations.':
      'Create your profile or sign in to link your children and secure your bookings.',
  'Affiche du stage de tennis et padel d’octobre':
      'October tennis and padel camp poster',
  'Voir l’affiche': 'View poster',
  'Affiche de la journée portes ouvertes tennis et padel':
      'Tennis and padel open day poster',
  'Chaque point raconte une histoire.': 'Every point tells a story.',
  'Suivez les progrès, célébrez les efforts et gardez chaque beau souvenir.':
      'Track progress, celebrate effort and keep every great memory.',
  'Son équipe, toujours à portée.': 'Their team, always close.',
  'Coachs, parents et académie réunis autour de ce qui compte : son épanouissement.':
      'Coaches, parents and academy united around what matters: their growth.',
  'Des rêves aux premiers trophées.': 'From dreams to first trophies.',
  'Cours, défis et tournois : un parcours motivant, construit à son rythme.':
      'Lessons, challenges and tournaments: a motivating journey at their own pace.',
  'Heureux de vous revoir': 'Welcome back',
  'Retrouvez le parcours de Lucas en un instant.':
      'Pick up Lucas’s journey in an instant.',
  'Continuer avec Google': 'Continue with Google',
  'Continuer avec Apple': 'Continue with Apple',
  'Continuer avec mon e-mail': 'Continue with email',
  'En continuant, vous acceptez nos Conditions d’utilisation.':
      'By continuing, you agree to our Terms of Use.',
  'Bonjour Sophie 👋': 'Hello Sophie 👋',
  'Bonjour': 'Hello',
  'Lucas en ce moment': 'Lucas right now',
  'Voir le profil': 'View profile',
  'Actions rapides': 'Quick actions',
  'Coach': 'Coach',
  'Espace coach': 'Coach area',
  'Voici vos prochaines séances planifiées.':
      'Here are your upcoming scheduled sessions.',
  'Impossible de charger vos séances.': 'Unable to load your sessions.',
  'Aucune séance à venir.': 'No upcoming sessions.',
  'Lieu à définir': 'Location to be confirmed',
  'À définir': 'To be confirmed',
  'Terrain à définir': 'Court to be confirmed',
  'Stade à définir': 'Venue to be confirmed',
  'Joueurs assignés': 'Assigned players',
  'Aucun joueur assigné pour le moment.': 'No assigned players yet.',
  'Date à définir': 'Date to be confirmed',
  'Noter': 'Evaluate',
  'À venir': 'Upcoming',
  'Évaluer': 'Evaluate',
  'Technique': 'Technique',
  'Tactique': 'Tactics',
  'Physique': 'Fitness',
  'Comportement': 'Behaviour',
  'Commentaire du coach': 'Coach comment',
  'Évaluation impossible.': 'Unable to save the evaluation.',
  'Aucune notification pour le moment.': 'No notifications yet.',
  'Connectez-vous pour afficher vos joueurs et leur suivi.':
      'Sign in to view your players and their progress.',
  'Ouvrir mon profil': 'Open my profile',
  'Ajoutez un joueur pour afficher son suivi réel.':
      'Add a player to view their real progress.',
  'Ajouter un joueur': 'Add a player',
  'Aucun joueur ajouté.': 'No player added.',
  'Impossible de charger les profils joueurs.':
      'Unable to load player profiles.',
  'Ajoutez un joueur pour pouvoir ensuite le rattacher à une académie et réserver ses séances.':
      'Add a player so you can assign them to an academy and book their sessions.',
  'Connectez-vous pour gérer votre profil et vos joueurs.':
      'Sign in to manage your profile and players.',
  'Modifier ce joueur': 'Edit this player',
  'Sélectionnez un joueur pour afficher ses statistiques.':
      'Select a player to view their statistics.',
  'en ce moment': 'right now',
  'ans': 'years old',
  'terminées': 'completed',
  'Dernière évaluation du coach': 'Latest coach evaluation',
  'Aucune évaluation enregistrée pour ce joueur.':
      'No evaluation has been recorded for this player.',
  'Cours passés': 'Past lessons',
  'Mes notes': 'My notes',
  'Historique des cours': 'Lesson history',
  'Aucun cours passé pour le moment.': 'No past lessons yet.',
  'Historique des notes': 'Evaluation history',
  'Aucune note enregistrée pour le moment.': 'No evaluations recorded yet.',
  'Impossible de charger vos notes.': 'Unable to load your evaluations.',
  'Demande déjà envoyée': 'Request already sent',
  'Mot de passe oublié ?': 'Forgot password?',
  'Saisissez d’abord une adresse e-mail valide.':
      'Enter a valid email address first.',
  'Si un compte correspond à cette adresse, un lien de réinitialisation vient d’être envoyé.':
      'If an account matches this address, a password reset link has been sent.',
  'Trop de tentatives. Réessayez dans quelques minutes.':
      'Too many attempts. Try again in a few minutes.',
  'Impossible d’envoyer le lien. Réessayez.':
      'Unable to send the link. Try again.',
  'Historique des réservations': 'Booking history',
  'Consultez les séances à venir et les réservations passées de vos joueurs.':
      'View your players’ upcoming sessions and past bookings.',
  'Toutes': 'All',
  'Passées': 'Past',
  'Impossible de charger l’historique.': 'Unable to load booking history.',
  'Connectez-vous pour consulter vos réservations.':
      'Sign in to view your bookings.',
  'Historique du mois': 'Monthly history',
  'réservation': 'booking',
  'réservations': 'bookings',
  'Aucune réservation pour cette date.': 'No booking on this date.',
  'Aucune réservation dans cette période.': 'No booking in this period.',
  'Refusée': 'Rejected',
  'Cette semaine': 'This week',
  'séances': 'sessions',
  'sur le court': 'on court',
  'XP gagnés': 'XP earned',
  'Objectif du mois': 'Monthly goal',
  'Dernier badge gagné': 'Latest badge',
  'Tous les badges': 'All badges',
  'Série en feu 🔥': 'On fire 🔥',
  '3 entraînements dans la même semaine': '3 training sessions in one week',
  'À ne pas manquer': 'Don’t miss it',
  'DANS 16 JOURS': 'IN 16 DAYS',
  '22–23 août · Tennis Club Bonanjo': 'August 22–23 · Bonanjo Tennis Club',
  'Notifications': 'Notifications',
  'Réservation confirmée': 'Booking confirmed',
  'Séance avec Coach David · Aujourd’hui 17:30':
      'Session with Coach David · Today 5:30 PM',
  'Nouveau badge pour Lucas': 'New badge for Lucas',
  'Il décroche le badge « Série en feu »': 'He earned the “On fire” badge',
  'Message de Coach David': 'Message from Coach David',
  'Très belle séance aujourd’hui !': 'Great session today!',
  'PROCHAINE SÉANCE': 'NEXT SESSION',
  'AUCUNE SÉANCE': 'NO UPCOMING SESSION',
  'Réservez une séance pour commencer.': 'Book a session to get started.',
  'Voir les séances disponibles': 'Browse available sessions',
  'AUJOURD’HUI': 'TODAY',
  'Perfectionnement · 1h30': 'Advanced training · 1h30',
  'Coach David · Court central': 'Coach David · Centre court',
  '9 ans · Niveau Orange': 'Age 9 · Orange level',
  'Réserver un cours': 'Book a lesson',
  'Cours de tennis': 'Tennis lesson',
  'Terrain': 'Court',
  'Trouvez la séance parfaite pour Lucas.':
      'Find the perfect session for Lucas.',
  'Type de séance': 'Session type',
  'Individuel': 'Private',
  '1 joueur': '1 player',
  'Petit groupe': 'Small group',
  '4 joueurs max.': '4 players max.',
  'Académie & coach': 'Academy & coach',
  'Tennis Club Bonanjo': 'Bonanjo Tennis Club',
  'Rue Njo-Njo · 1,2 km': 'Njo-Njo Street · 1.2 km',
  '4,9 ★ · Coach principal de Lucas': '4.9 ★ · Lucas’s main coach',
  'Choisir une date': 'Choose a date',
  'Créneaux disponibles': 'Available times',
  '3 places restantes · Court central\nDurée 1h30 · Matériel inclus':
      '3 spots left · Centre court\nDuration 1h30 · Equipment included',
  'Confirmer la réservation': 'Confirm booking',
  'C’est réservé !': 'You’re booked!',
  'Rendez-vous mardi 11 août à 10:30 avec Coach David.':
      'See you Tuesday, August 11 at 10:30 AM with Coach David.',
  'Voir dans mon calendrier': 'View in my calendar',
  'LUN': 'MON',
  'MAR': 'TUE',
  'MER': 'WED',
  'JEU': 'THU',
  'VEN': 'FRI',
  'SAM': 'SAT',
  'Mon calendrier': 'My calendar',
  'AOÛT 2026': 'AUGUST 2026',
  '2 événements': '2 events',
  'Perfectionnement': 'Advanced training',
  'Jeu & Match': 'Play & Match',
  'Préparation tournoi': 'Tournament preparation',
  'Coach Émilie': 'Coach Émilie',
  'Court central · Tennis Club Bonanjo': 'Centre court · Bonanjo Tennis Club',
  'Court 2 · Académie Littoral': 'Court 2 · Littoral Academy',
  'Les prochains défis de Lucas.': 'Lucas’s next challenges.',
  'INSCRIT': 'REGISTERED',
  'Préparation': 'Preparation',
  'À découvrir': 'Discover',
  'Voir la carte': 'View map',
  'Inscrire Lucas': 'Register Lucas',
  'Catégorie': 'Category',
  'Joueurs': 'Players',
  'Terrains': 'Courts',
  'Conversations': 'Conversations',
  'Rechercher une conversation...': 'Search conversations...',
  'Écrire un message...': 'Write a message...',
  'Votre réservation de samedi est confirmée.':
      'Your Saturday booking is confirmed.',
  'Parents · Groupe U10': 'Parents · U10 Group',
  'Sophie : Je peux apporter les boissons !': 'Sophie: I can bring the drinks!',
  'Voici les photos de l’entraînement 📸': 'Here are the training photos 📸',
  'Lucas a fait une très belle séance aujourd’hui 🎾':
      'Lucas had a great session today 🎾',
  'Bonjour Sophie ! Lucas a été très concentré aujourd’hui.':
      'Hi Sophie! Lucas was very focused today.',
  'Son coup droit progresse vraiment bien 🎾':
      'His forehand is improving really well 🎾',
  'Merci David ! Il était très fier de sa séance.':
      'Thank you David! He was very proud of his session.',
  'Profil joueur': 'Player profile',
  'Mon profil': 'My profile',
  'Mes joueurs': 'My players',
  'Ajouter': 'Add',
  'Ajouter un enfant': 'Add a child',
  'Ajouter un joueur enfant': 'Add a child player',
  'Ajouter l’enfant': 'Add child',
  'Paiement cash en attente de confirmation par un administrateur. Le profil sera activé après validation.':
      'Cash payment awaiting administrator confirmation. The profile will be activated after approval.',
  'Prénom de l’enfant': "Child's first name",
  'Nom de l’enfant': "Child's last name",
  'Âge': 'Age',
  'Sexe': 'Gender',
  'Fille': 'Girl',
  'Garçon': 'Boy',
  'Femme': 'Female',
  'Homme': 'Man',
  'Autre': 'Other',
  'Aucune académie rattachée': 'No academy linked',
  'L’académie pourra être rattachée plus tard.':
      'The academy can be linked later.',
  'Aucun joueur enfant ajouté.': 'No child player added.',
  'Connectez-vous pour gérer votre profil et vos enfants.':
      'Sign in to manage your profile and children.',
  'Modifier mon profil': 'Edit my profile',
  'Modifier le joueur': 'Edit player',
  'Modifier cet enfant': 'Edit this child',
  'Enregistrer': 'Save',
  'Numéro de téléphone': 'Phone number',
  'Sélectionnez un enfant pour afficher ses statistiques.':
      'Select a child to view their statistics.',
  'Aucune statistique enregistrée pour ce joueur pour le moment.':
      'No statistics have been recorded for this player yet.',
  'Se déconnecter': 'Sign out',
  'Se déconnecter ?': 'Sign out?',
  'Annuler': 'Cancel',
  'Vous pourrez continuer à découvrir l’application sans être connecté.':
      'You can continue exploring the app without being signed in.',
  '9 ans · CM1 · Droitier': 'Age 9 · Grade 4 · Right-handed',
  '🎾 Niveau Orange': '🎾 Orange level',
  'Progression globale': 'Overall progress',
  'progression': 'progress',
  '+8% ce mois-ci': '+8% this month',
  'Lucas progresse plus vite que son objectif. Beau travail !':
      'Lucas is progressing faster than his goal. Great work!',
  'Compétences': 'Skills',
  'Service': 'Serve',
  'Coup droit': 'Forehand',
  'Revers': 'Backhand',
  'Volée': 'Volley',
  'Déplacement': 'Footwork',
  'Concentration': 'Focus',
  'Statistiques de saison': 'Season stats',
  'de jeu': 'played',
  'badges': 'badges',
  'Objectif actuel': 'Current goal',
  'Réussir 7 services sur 10': 'Land 7 serves out of 10',
  'Objectif fixé avec Coach David · 6/10': 'Goal set with Coach David · 6/10',
  'Note du coach': 'Coach’s note',
  '« Lucas gagne en confiance. Son placement s’améliore et il encourage toujours ses partenaires. Prochaine étape : régularité au service. »':
      '“Lucas is growing in confidence. His positioning is improving and he always encourages his teammates. Next step: consistency on serve.”',
  'Messages': 'Messages',
  'Joueurs enfants': 'Child players',
  'Facultatif : vous pourrez aussi ajouter d’autres enfants depuis votre profil.':
      'Optional: you can add more children later from your profile.',
  'Cash': 'Cash',
  'Carte bancaire': 'Bank card',
  'Lien de paiement': 'Payment link',
  'Virement bancaire': 'Bank transfer',
  'Prénom': 'First name',
  'Nom': 'Last name',
  'Mode de paiement': 'Payment method',
  'Réservation envoyée !': 'Booking request sent!',
  'Votre demande est en attente de validation par l’académie.':
      'Your request is awaiting approval from the academy.',
  'Fermer': 'Close',
  'Choisissez un enfant puis une séance réellement disponible.':
      'Select a child, then choose an available session.',
  'Joueur': 'Player',
  'Sélectionner un enfant': 'Select a child',
  'Séances disponibles': 'Available sessions',
  'Vous n’avez pas encore ajouté de joueur.':
      'You have not added a player yet.',
  'Créez d’abord le profil de votre enfant pour pouvoir réserver une séance.':
      'Create your child’s profile before booking a session.',
  'Créer un joueur': 'Create a player',
  'Aucune séance disponible pour cette académie.':
      'No sessions are available for this academy.',
  'Déconnexion': 'Sign out',
  'Séance': 'Session',
  'Le joueur a assisté à la séance': 'The player attended the session',
  'Le joueur était absent': 'The player was absent',
  'Heure d’arrivée': 'Arrival time',
  'Heure de départ': 'Departure time',
  'Choisir': 'Select',
  'Confirmer': 'Confirm',
  'Enregistrement...': 'Saving...',
  'Impossible de charger les profils des enfants.':
      'Unable to load the child profiles.',
  'Ajoutez un enfant pour pouvoir ensuite le rattacher à une académie et réserver ses séances.':
      'Add a child so you can assign them to an academy and book sessions.',
  'Chargement des séances...': 'Loading sessions...',
  'Tennis': 'Tennis',
  'Paddle': 'Padel',
  'Lundi': 'Monday',
  'Mardi': 'Tuesday',
  'Mercredi': 'Wednesday',
  'Jeudi': 'Thursday',
  'Vendredi': 'Friday',
  'Samedi': 'Saturday',
  'Dimanche': 'Sunday',
  'minutes': 'minutes',
  'Renseignez le nom, le prénom et un âge compris entre 3 et 80 ans.':
      'Enter a first name, last name and an age between 3 and 80.',
  'Choisissez une configuration de séance et un mode de paiement.':
      'Select a session package and a payment method.',
  'Impossible d’ajouter cet enfant. Réessayez.':
      'Unable to add this child. Please try again.',
  'Forfait': 'Package',
  'Cours du joueur': 'Player lessons',
  'Activation en attente': 'Activation pending',
  'Reste': 'Remaining',
  'Le forfait est épuisé. Réabonnez ce joueur pour réserver de nouvelles séances.':
      'This package has run out. Renew it to book more sessions.',
  'Il ne reste que': 'Only',
  'séance(s). Pensez à réabonner ce joueur.':
      'session(s) remaining. Please renew this player’s package.',
  'séance(s) restantes sur': 'session(s) remaining out of',
  'place(s)': 'spot(s)',
  'Présence enregistrée.': 'Attendance saved.',
  'Impossible d’enregistrer la présence.': 'Unable to save attendance.',
  'Présent': 'Present',
  'Absent': 'Absent',
  'Privée': 'Private',
  'Semi-privée': 'Semi-private',
  'Groupe': 'Group',
  'Séance privée': 'Private session',
  'Séance semi-privée': 'Semi-private session',
  'Séance de groupe': 'Group session',
  'Séance de tennis': 'Tennis session',
  'Séance de padel': 'Padel session',
  'Paddle session': 'Padel session',
  'Tennis session': 'Tennis session',
  'Coach à définir': 'Coach to be confirmed',
  'DEMAIN': 'TOMORROW',
  'Confirmée': 'Confirmed',
  'Terminée': 'Completed',
  'Annulée': 'Cancelled',
  'En attente': 'Pending',
  'Connexion impossible. Réessayez.': 'Unable to sign in. Please try again.',
  'Veuillez compléter correctement tous les champs.':
      'Please complete all fields correctly.',
  'Cette adresse e-mail est déjà utilisée.':
      'This email address is already in use.',
  'Le mot de passe doit contenir au moins 6 caractères.':
      'The password must contain at least 6 characters.',
  'Authentification impossible. Réessayez.':
      'Authentication failed. Please try again.',
  'Choisissez une séance et un mode de paiement pour chaque enfant.':
      'Select a session package and payment method for each child.',
  'Complétez correctement chaque profil joueur (âge de 3 à 80 ans).':
      'Complete each player profile correctly (age 3 to 80).',
  'Impossible de créer le profil. Réessayez.':
      'Unable to create the profile. Please try again.',
  'Connectez-vous pour réserver un cours.': 'Sign in to book a lesson.',
  'Impossible de charger les réservations. Réessayez.':
      'Unable to load bookings. Please try again.',
  'Demander la réservation': 'Request booking',
  'Envoi en cours...': 'Sending...',
  'Présence': 'Attendance',
  'Modifier la présence': 'Edit attendance',
  'Confirmez la présence et renseignez les heures demandées.':
      'Confirm attendance and enter the requested times.',
  'L’heure de départ doit être après l’heure d’arrivée.':
      'The departure time must be after the arrival time.',
  'Enregistrement impossible.': 'Unable to save.',
  'Le forfait est épuisé. Réabonnez ce joueur pour continuer.':
      'This package has run out. Renew it to continue.',
  'Impossible de modifier votre profil.': 'Unable to update your profile.',
  '22–23 AOÛT': '22–23 AUGUST',
  'Hier': 'Yesterday',
  'Authentification requise.': 'Authentication required.',
  'Permission insuffisante.':
      'You do not have permission to perform this action.',
  'Ce joueur ne vous est pas rattaché.': 'This player is not assigned to you.',
  'Joueur introuvable.': 'Player not found.',
  'Ce joueur a été supprimé.': 'This player has been deleted.',
  'Séance ou joueur introuvable.': 'Session or player not found.',
  'Réservation introuvable.': 'Booking not found.',
  'Cette séance est complète.': 'This session is full.',
  'Cette séance ne peut plus être réservée.':
      'This session can no longer be booked.',
  'La séance est complète ou fermée.': 'The session is full or closed.',
  'Cette réservation a déjà été traitée.':
      'This booking has already been processed.',
  'Cette réservation ne peut plus être annulée.':
      'This booking can no longer be cancelled.',
  'Cette réservation ne vous est pas assignée.':
      'This booking is not assigned to you.',
  'La réservation doit être confirmée.': 'The booking must be confirmed.',
  'Cette configuration de séance ne correspond pas à l’âge du joueur.':
      'This session package does not match the player’s age.',
  'Cette configuration de séance n’est plus disponible.':
      'This session package is no longer available.',
  'Aucune configuration de séance ne correspond à l’âge de ce joueur.':
      'No session package matches this player’s age.',
  'L’âge du joueur doit être renseigné avant la réservation.':
      'The player’s age must be provided before booking.',
  'Le forfait de ce joueur est épuisé. Demandez son réabonnement.':
      'This player’s package has run out. Please ask them to renew.',
  'Le forfait de ce joueur est épuisé. Veuillez le réabonner.':
      'This player’s package has run out. Please renew it.',
  'Cette séance ne fait pas partie du forfait de ce joueur.':
      'This session is not included in this player’s package.',
  'Ce profil joueur est en attente de confirmation du paiement cash par un administrateur.':
      'This player profile is awaiting cash payment confirmation by an administrator.',
  'Choisissez un mode de paiement.': 'Select a payment method.',
  'Mode de paiement invalide.': 'Invalid payment method.',
  'Choisissez un type de séance.': 'Select a session type.',
  'L’âge doit être compris entre 3 et 80 ans.': 'Age must be between 3 and 80.',
  'Confirmez la présence ou l’absence du joueur.':
      'Confirm whether the player attended or was absent.',
  'Les heures d’arrivée et de départ sont invalides.':
      'The arrival and departure times are invalid.',
  'La séance doit avoir commencé.': 'The session must have started.',
  'La séance doit avoir commencé avant son évaluation.':
      'The session must have started before it can be evaluated.',
  'Chaque note doit être comprise entre 1 et 5.':
      'Each rating must be between 1 and 5.',
  'Commentaire trop long.': 'The comment is too long.',
  'Choisissez votre sport': 'Choose your sport',
  'Contactez directement l’académie pour programmer votre cours.':
      'Contact the academy directly to schedule your lesson.',
  'Appeler': 'Call',
  'Impossible d’ouvrir cette application.': 'Unable to open this application.',
  'Contactez l’académie pour programmer votre cours.':
      'Contact the academy to schedule your lesson.',
  'Connectez-vous pour consulter les réservations programmées par l’académie.':
      'Sign in to view bookings scheduled by the academy.',
  'Me connecter': 'Sign in',
  'Réservations programmées': 'Scheduled bookings',
  'Aucune réservation programmée à refuser.':
      'There is no scheduled booking to reject.',
  'Refuser cette réservation ?': 'Reject this booking?',
  'Refuser la réservation': 'Reject booking',
  'Réservation refusée.': 'Booking rejected.',
  'Impossible de refuser cette réservation.': 'Unable to reject this booking.',
};
