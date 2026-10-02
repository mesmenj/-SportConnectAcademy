# SportA

## Reprise Sport Connect Academy — mise à jour du 29 septembre 2026

La cible est désormais le contrat greenfield PostgreSQL/Supabase. **Les phases
3A–3D sont implémentées et 3D est validée sur la pile Supabase locale complète :
41 tables, 25 migrations, 427 assertions SQL et 12 tests de concurrence.**
Le MVP Web 4A plateforme/académie est connecté à Supabase et validé dans Chromium
localement. L'application Flutter 4B (parents, élèves, coachs) est connectée à
Supabase et validée localement sur Web. Aucun staging ni environnement
de production validé.
Les sections Firebase ci-dessous décrivent le prototype antérieur.

- [État vérifié et écarts des interfaces](docs/IMPLEMENTATION_STATUS.md)
- [Rapport phase 3A](docs/PHASE_3A_DATABASE_IMPLEMENTATION_REPORT.md)
- [Rapport 4A et lancement des interfaces Web](docs/PHASE_4A_WEB_IMPLEMENTATION_REPORT.md)
- [Rapport 4B et lancement Flutter](docs/PHASE_4B_FLUTTER_IMPLEMENTATION_REPORT.md)
- [Clôture locale phase 3D](docs/PHASE_3D_AUTH_STORAGE_EDGE_REPORT.md)
- [Contrat des tables](docs/database/SPORT_CONNECT_DATABASE_GREENFIELD_FINAL.md)
- [Tests et configuration Supabase locale](supabase/README.md)
- [Consignes de reprise](AGENTS.md)

Vérification SQL locale : `npm run test:database` (PostgreSQL 17 requis, cluster jetable).

## Design — aperçu interactif

Les commandes Web ouvrent désormais les interfaces connectées à Supabase local.
Pour retrouver les aperçus fictifs Web, utiliser `VITE_DESIGN_PREVIEW=true`.
Flutter ouvre aussi Supabase ; aperçu fictif avec `--dart-define=DESIGN_PREVIEW=true`.

Voir [DESIGN.md](docs/DESIGN.md) pour les écrans disponibles, les captures et les commandes permettant de retrouver le mode Firebase. **Le backend n’a pas été migré dans cette étape.** L’état du socle décrit ci-dessous concerne le mode Firebase existant.

Socle SaaS indépendant pour plusieurs académies sportives, préparé à partir du projet client. Aucun projet Firebase réel n’est nécessaire pour la démonstration locale. Aucun paiement en ligne n’est activé.

## Ce qui fonctionne dans cette version

- Nouveau back-office opérateur React : authentification, tableau de bord, création et suspension d’académies, catalogue des forfaits, activation/prolongation manuelle des abonnements, gestion des membres et journal d’audit.
- Nouvel espace académie React : connexion, choix parmi ses académies, consultation du forfait, liste et création des joueurs avec contrôle serveur des quotas et de l’échéance, gestion des membres par le propriétaire.
- Nouvelle entrée Flutter SportA : connexion, liste de ses académies et consultation d’une académie autorisée.
- Backend distinct, règles Firestore avec refus par défaut et données métier sous `academies/{academyId}`. Aucun accès global aux joueurs pour les opérateurs de plateforme.
- Comptes, forfaits et académie de démonstration à initialiser dans les émulateurs.

## État de la reprise de l’ancien projet

Les sources du projet client sont copiées, mais **la reprise fonctionnelle complète n’est pas terminée** : les anciennes pages de réservations, coachs, cours, tournois, factures et notifications restent à migrer vers le modèle par académie.

- `apps/academy-admin/src/App.tsx` et les anciens composants sont conservés ; l’entrée active utilise `TenantApp.tsx`.
- `apps/student/lib/app.dart`, `features` et `data` sont conservés ; l’entrée active utilise `sporta_app.dart`.
- `reference/client-functions` conserve le backend historique à adapter ; il n’est pas déployé par la configuration SportA.
- Les règles refusent les anciennes collections globales. Réactiver un ancien écran sans migration provoquerait des refus d’accès.
- Les images et logos historiques sont conservés comme références ; les nouvelles entrées ne les affichent pas. Les remplacer par les ressources SportA avant réactivation des anciens parcours.

Ce socle sert à développer le produit ; il n’est pas présenté comme une version commerciale complète.

## Arborescence

```text
apps/platform-admin/     Back-office SportA — port 5174
apps/academy-admin/      Administration d’une académie — port 5173
apps/student/            Application Flutter
functions/               API SportA active
reference/               Backend source conservé pour migration
docs/                    Architecture, état de migration et activation Firebase
```

## Projet Firebase cloud

Les applications Android, iOS, Flutter Web et les deux administrations sont enregistrées dans **`sporta-hub-2026`**. Les configurations sont intégrées ; les commandes habituelles restent en mode émulateur. Voir [la configuration Firebase](docs/FIREBASE.md) pour lancer le mode cloud et terminer les prérequis Auth, Firestore, App Check et backend.

## Démarrage local

Prérequis : Node.js 22, Java 21+, Flutter compatible avec le projet. La CLI Firebase est une dépendance locale pour ne pas modifier celle de la machine.

```bash
cd /Users/apple/Documents/SportA
npm ci
npm run install:all
```

Les fichiers `.env.local` des deux interfaces sont déjà préparés pour `demo-sporta`. Sur une autre machine, copier leurs `.env.example` en `.env.local`.

Terminal 1 :

```bash
npm run emulators
```

Terminal 2, une fois les émulateurs prêts :

```bash
npm run seed:local
VITE_DESIGN_PREVIEW=false npm run dev:platform
```

Terminal 3 :

```bash
VITE_DESIGN_PREVIEW=false npm run dev:academy
```

- Plateforme : http://localhost:5174 — `operator@sporta.test`
- Académie : http://localhost:5173 — `owner@sporta.test`
- Mot de passe de ces comptes **locaux uniquement** : `SportA-local-2026!`
- Le script de données de démonstration refuse tout projet autre que `demo-sporta` et exige les variables d’émulateurs.
- Pour créer une autre académie, créer d’abord son propriétaire dans l’émulateur Authentication, puis utiliser son email dans le back-office.
- Les données locales sont éphémères par défaut. Elles peuvent être recréées avec `seed:local`.

Le lanceur local utilise automatiquement le Java fourni par Android Studio sur ce Mac. Pour choisir explicitement un JDK, définir JAVA_HOME :

```bash
JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" npm run emulators
```

L’entrée Flutter ne démarre plus Firebase : voir `apps/student/README.md` pour
la configuration Supabase locale (4B).

## Vérification

```bash
npm run build
npm test
npm run test:emulators
cd apps/student
flutter analyze lib/connect lib/main.dart test/connect
```

Les tests d’intégration utilisent un projet de démonstration et vérifient les lectures croisées, les écritures croisées, les rôles, la suspension, l’expiration, l’idempotence des activations et les créations concurrentes au-delà des quotas joueurs et équipe. Ils doivent être lancés sans autre instance d’émulateurs sur les mêmes ports.

## Firebase plus tard

Voir [FIREBASE.md](docs/FIREBASE.md). Aucun identifiant, secret, domaine d’envoi ou clé de signature du client existant n’est nécessaire pour SportA. Le projet actuel n’a pas été modifié par cette préparation.

Voir [ARCHITECTURE.md](docs/ARCHITECTURE.md) et [MIGRATION.md](docs/MIGRATION.md) pour le modèle retenu et la suite des migrations.
