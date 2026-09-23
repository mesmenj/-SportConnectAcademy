# SportA — aperçu du design

Les trois applications démarrent maintenant sur un **aperçu interactif sans Firebase**. Cette étape concerne le design ; elle ne termine pas la migration métier de Classcard vers le modèle multi-académies.

## Ouvrir les interfaces

```bash
npm run dev:academy   # http://localhost:5173
npm run dev:platform  # http://localhost:5174
```

Flutter :

```bash
cd apps/student
flutter run -d chrome --web-port 5175
```

Aucun compte, émulateur ni accès cloud n’est nécessaire. Les données sont fictives. Les ajouts, changements de statut et messages sont stockés uniquement en mémoire et disparaissent au rechargement. Aucun règlement ni invitation n’est envoyé.

## Direction visuelle

- Vert profond `#163E33` : navigation, textes principaux et boutons.
- Citron `#D5F279` : accents, sélections et appels à l’action sur fond foncé.
- Blanc cassé `#F5F6F2` : fond des pages.
- Bordures `#E7EAE3`, texte secondaire `#7B857A`.
- Cartes arrondies, typographie hiérarchisée, icônes cohérentes, états vides, recherche, filtres et fiches de détail.
- Illustrations de terrain dessinées en CSS et Flutter ; aucun nouveau service d’images.
- Administrations : navigation latérale sur ordinateur, tiroir sur mobile, tableaux à défilement horizontal.
- Flutter : navigation inférieure sur téléphone, rail sur grand écran.

## Parcours disponibles

| Interface | Écrans et interactions d’aperçu |
| --- | --- |
| Administration académie | Tableau de bord, périodes, réservations en liste/planning, joueurs/familles, coachs, séances/tarifs, groupes, terrains, tournois, factures, communication, équipe et profil. Recherche, filtres, formulaires d’ajout adaptés, fiches, confirmation/annulation de réservation, marquage d’une facture comme réglée. |
| Plateforme | Tableau de bord, académies, fiches, suspension/réactivation, abonnements, renouvellement simulé, modification des forfaits, équipe, journal d’activité et profil. |
| Flutter famille | Accueil, sélection/ajout de joueurs, progression, réservation en trois étapes, calendrier hebdomadaire, annulation, historique, tournois et inscription simulée, forfaits/factures, messages, notifications, accueil en trois pages et connexion de démonstration. |
| Flutter coach | Dans Profil → Espace coach : tableau de bord, présences et formulaire d’évaluation simulée. |

Les formulaires constituent une prévisualisation des parcours ; les règles métier, permissions, disponibilités, quotas et calculs de facturation restent à connecter au backend. Les valeurs de progression et graphiques sont des exemples. La sélection d’académie dans l’aperçu change le contexte affiché et conserve le même jeu d’exemples. L’aperçu est en français ; la localisation complète des nouveaux écrans reste à intégrer avec les parcours métier.

## Organisation du code

- `apps/academy-admin/src/design/DesignApp.tsx` : composants d’aperçu partagés entre les deux administrations.
- `apps/academy-admin/src/design/design.css` : styles et adaptation aux tailles d’écran.
- `apps/academy-admin/src/design/fixtures.ts` : données et navigation.
- `apps/academy-admin/src/design/forms.ts` : champs par métier et transformation des formulaires locaux.
- `apps/*-admin/src/EntryApp.tsx` : chargement de l’aperçu ou de l’application Firebase existante.
- `apps/student/lib/design/design_app.dart` : aperçu Flutter, composants, navigation et état local.
- Les thèmes historiques Flutter/React ont reçu la palette SportA ; les écrans Classcard conservés restent disponibles pour la future reprise métier.

La comparaison des sources a trouvé les pages Classcard déjà copiées dans SportA : aucun écran source manquant dans `classcard-admin/src` et `classcard_student/lib`. L’aperçu utilise leurs parcours comme référence sans réactiver les appels aux anciennes collections globales.

## Retrouver les entrées Firebase existantes

Web local :

```bash
VITE_DESIGN_PREVIEW=false npm run dev:academy
VITE_DESIGN_PREVIEW=false npm run dev:platform
```

Le mode `sporta` utilise toujours l’entrée Firebase existante :

```bash
npm run dev:sporta --prefix apps/academy-admin
npm run dev:sporta --prefix apps/platform-admin
```

Flutter : ajouter `--dart-define=DESIGN_PREVIEW=false` aux commandes Firebase/émulateurs. Les autres paramètres restent nécessaires, comme décrit dans [FIREBASE.md](FIREBASE.md).

Le mode Firebase affiche encore le socle antérieur. Le nouveau design interactif n’est pas présenté comme connecté aux données réelles.

## Vérification

```bash
npm run build --prefix apps/academy-admin
npm run build --prefix apps/platform-admin
cd apps/student
flutter analyze lib/design/design_app.dart lib/main.dart
flutter test test/design_preview_test.dart
flutter build web --dart-define=DESIGN_PREVIEW=true
```

Les captures dans `docs/design/` montrent les interfaces à 1440 px et 390 px. Elles servent de référence visuelle, pas de preuve d’intégration backend.

Vérifications effectuées : compilation des deux administrations et de Flutter Web ; analyse Flutter sans erreur ; trois tests de widgets réussis (navigation mobile, réservation complète, navigation ordinateur) ; contrôle navigateur des 19 rubriques à 320 et 390 px, et ajout d’un joueur/création/confirmation d’une réservation sans exception JavaScript.
