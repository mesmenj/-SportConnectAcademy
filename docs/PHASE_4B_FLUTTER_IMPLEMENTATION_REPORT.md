# Phase 4B — Application Flutter joueurs, familles et coachs

29 septembre 2026 — SportA uniquement. Travail commencé par Codex puis finalisé
dans le même workspace. Périmètre : `apps/student` et scripts de test locaux ;
aucun environnement distant, aucune modification des migrations ou des RPC.

## Réalisation

L'entrée par défaut de `apps/student` utilise Supabase (`lib/connect/`). Firebase
n'est plus initialisé au démarrage ; l'aperçu historique reste disponible avec
`--dart-define=DESIGN_PREVIEW=true`. Les dépendances Firebase restent déclarées
pour le code historique conservé, mais le mode connecté ne les charge pas.

- **Auth** : connexion email/mot de passe, renouvellement mutualisé du jeton,
  déconnexion ; une réponse de refresh tardive ne rétablit pas une session fermée.
  Récupération du mot de passe via le callback Web 4A (`AUTH_RECOVERY_URL`).
  L'activation d'une invitation reste le parcours Web 4A ; pas d'inscription publique.
- **Session** : jetons en mémoire uniquement. Un rechargement Web ou une fermeture
  complète exige une reconnexion. Aucun mot de passe, JWT ni clé privilégiée stocké.
- **Configuration** : URL et clé **publique** par `--dart-define`. Le client refuse
  les clés `service_role`/non-anon et le HTTP hors boucle locale (`10.0.2.2` inclus
  pour l'émulateur Android ; exception cleartext limitée au manifeste debug).
- **Contexte académie** : `list_my_academies`, `get_access_context`, lectures
  conditionnées aux permissions serveur, réponses tardives d'une autre académie
  ignorées, données effacées lors d'une révocation.
- **Parent/élève** : joueurs liés, profil, contacts familiaux, forfaits et
  historique des crédits, planning, demande de réservation (joueur + forfait),
  annulation d'une demande, suivi de présence, historique et évaluation.
- **Coach** : séances affectées, saisie/correction de présence, évaluation et correction.

Lectures : `list_players`, `list_sessions`, `list_bookings`, `list_service_offers`,
`list_coaches`, `list_player_packages`, `list_course_ledger`, `list_booking_events`,
`get_player_profile`, et colonnes accordées de `courts`, `player_links`,
`player_evaluations`. Pagination par curseur serveur, fenêtre de 120 jours navigable.

Commandes raccordées (7) : `create_player`, `request_booking`, `cancel_booking`,
`reject_booking`, `record_attendance`, `record_evaluation`, `correct_evaluation`.
Aucune écriture directe dans les tables ; crédits, capacité, D34, révisions et
permissions restent décidés par les RPC.

Une commande est journalisée (`SharedPreferences`, clé par URL Supabase et
utilisateur) avec académie, arguments et clé d'opération avant l'envoi. Après une
réponse incertaine, le bouton de reprise rejoue exactement la même opération ; le
journal est effacé après réponse définitive. Pas de file hors ligne ni de
synchronisation en arrière-plan.

## Vérification

| Vérification | Résultat |
|---|---|
| `npm run lint:flutter` (`lib/connect`, `main.dart`, `test/connect`) | Aucun problème |
| `npm run test:flutter` | 12 réussis, 1 ignoré (parcours réel sans configuration locale) |
| `flutter build web --release --no-web-resources-cdn` | Réussite ; aucun secret ni compte de test dans le bundle |
| `npm run test:flutter:local` | Parcours widgets + HTTP réel sur Supabase local réussi (≈ 43 s) |
| `npm run test:flutter:browser` | Chromium, build compilé, 390 px, sans exception navigateur |

Tests client (`client_test.dart`) : refus des clés privilégiées et de la
configuration non sûre, refresh unique et logout prioritaire, rejeu après réponse
perdue avec charge identique, révision périmée définitive et journal non
rejouable par un autre utilisateur, pagination par curseur, réponse tardive
d'académie et révocation. `widget_test.dart` : connexion, académie et navigation
famille à 390 px sans Firebase.

Le parcours réel (`local_integration_test.dart`, préparé par
`scripts/test-flutter-local.mjs`) vérifie :

1. Connexion parent ; seul le joueur lié est visible, le joueur non lié est
   invisible dans l'UI et `get_player_profile` le refuse.
2. Profil : responsable légal et 9 crédits disponibles.
3. Demande de réservation avec joueur et forfait, puis annulation motivée.
4. Parent sans action de présence ; coach : planning, présence « Présent »,
   séance terminée, évaluation visible dans l'historique.
5. Retour parent : `Restants : 9 · Réservés : 0`, `Disponibles : 9`, évaluation
   visible. Aucune exception Flutter.

Le contrôle Chromium sert le build sur `127.0.0.1:5175`, se connecte en parent,
vérifie l'accueil et la carte du joueur lié, l'absence du joueur non lié dans
l'arbre d'accessibilité, et produit `flutter-home.png` et `flutter-players.png`.

Les comptes sont synthétiques (`example.test`). Comme en 4A, le script amorce un
super-administrateur par SQL de test et déplace uniquement sa propre séance dans
le passé pour permettre la présence ; les autres mutations passent par les RPC
avec JWT utilisateur. Il ajoute des données sans réinitialiser la base.

### Corrections de finalisation

- **Nettoyage HTTP du test réel** : les connexions keep-alive inactives de
  `HttpClient` créent des minuteurs de 15 s dans la zone fake-async. Le test
  avançait l'horloge de 20 s pour les vider ; il ferme maintenant le client à la
  fin du corps du test, avant la vérification des invariants (qui précède les
  `tearDown`). Aucun minuteur en attente.
- **Sélecteurs Chromium** : Flutter expose le texte d'une carte comme contenu de
  nœud sémantique, et fusionne la carte joueur en `group` nommé. Les sélecteurs
  `[aria-label*=…]` ne trouvaient rien ; ils utilisent `getByText` et
  `getByRole('group', {name})`.

## Lancement local

Voir `apps/student/README.md`. En résumé, depuis la racine, pile Supabase locale
démarrée :

```bash
npm run configure:flutter:local
cd apps/student && flutter run -d chrome --web-port=5175 --dart-define-from-file=config.local.json
```

Parcours de test :

```bash
SPORTA_EDGE_ENV_FILE=<fichier env Edge local> npm run test:flutter:local
cd apps/student && flutter build web --release --no-web-resources-cdn \
  --dart-define-from-file=<dossier affiché>/public-config.json && cd ../..
SPORTA_FLUTTER_ARTIFACTS=<dossier affiché> npm run test:flutter:browser
```

Les fonctions Edge doivent être servies (worker d'invitation). Le port 5175 doit
être libre pour le contrôle Chromium.

## Limites

- Validé sur Flutter Web (widgets et Chromium) uniquement. Android/iOS : configuration
  prévue (`10.0.2.2`, manifeste debug) mais **aucune exécution sur émulateur ou
  appareil** pendant 4B.
- Pas de persistance de session : reconnexion après rechargement ou redémarrage.
- Invitations, récupération du mot de passe et assets passent par les parcours Web
  4A ; pas d'upload ni d'affichage d'assets dans Flutter.
- Parcours réel limité à un parent et un coach sur une académie. D34, capacité et
  courses sont couverts côté serveur (3C) et Web (4A), pas rejoués dans l'UI
  Flutter ; révision périmée, rejeu et réponse tardive d'académie le sont par les
  tests client avec transport simulé.
- Pas de notifications push, de Realtime ni de mode hors ligne.
- Revue humaine, QA 5 (réseau, langue, fuseaux), staging et production restent à faire.
