# État vérifié — Sport Connect Academy

Vérification initiale du 26 septembre 2026 ; clôture locale 3D et implémentations 4A/4B du 29 septembre 2026 dans `/Users/apple/Documents/SportA`, branche
`main`, base Git `9814b80`. Ce rapport décrit le workspace disponible, pas un
éventuel travail réalisé ailleurs ou des environnements distants.

## État avant cette reprise

`AGENTS.md`, le README Supabase, les migrations, les fonctions Edge, le contrat
greenfield final et le rapport 3D annoncé étaient absents. `supabase/` contenait
seulement des dossiers vides et un `.DS_Store`. Les designs V1/V1.1 ont été retrouvés
dans `Documents/projet classcard/docs/audit-sport-connect-academy` et copiés sans
modification dans `docs/database/`. La roadmap fournie est maintenant conservée.

| Domaine | État observé | Travail restant |
|---|---|---|
| Contrat greenfield | Finalisé dans cette reprise, 41 tables | Revue des choix documentés |
| 3A PostgreSQL | Implémenté et testé localement : 123 assertions | 427 assertions globales validées aussi sur Supabase local |
| 3B RLS | Lectures implémentées et testées localement : 92 assertions ([rapport](PHASE_3B_RLS_SECURITY_REPORT.md)) | PostgREST/JWT réels vérifiés sur le parcours 3D ; revue produit et performances restent distinctes |
| 3C RPC | 59 RPC implémentées : 142 assertions et 8 courses à deux connexions ([rapport](PHASE_3C_BUSINESS_RPC_REPORT.md)) | Décisions D05/D29/D32 encore ouvertes ; parcours RPC réel validé en 3D |
| 3D Auth/Storage/Edge | Clôturé localement : 70 assertions `005`, 4 courses 3D, 24 tests Edge et parcours intégré réel ([rapport](PHASE_3D_AUTH_STORAGE_EDGE_REPORT.md)) | Brevo externe et rétention D28 à valider avant environnement partagé ; intégration UI en 4A/4B |
| 4A Web académie | MVP connecté : Auth, contexte tenant, lectures/RPC, formulaires, réessais et assets ; build et parcours Chromium réussis | Revue humaine, QA complète et limites du rapport 4A |
| 4A Web plateforme | MVP connecté : académies, invitation owner, plans/abonnements/audit ; entrée recréée, dépendances installées, build réussi | Revue humaine et QA complémentaire |
| 4B Flutter | MVP connecté parent/élève/coach : Auth, contexte tenant, lectures/RPC, 7 commandes, rejeu ; widgets + HTTP réel et Chromium réussis ([rapport](PHASE_4B_FLUTTER_IMPLEMENTATION_REPORT.md)) | Revue humaine, exécution Android/iOS, limites du rapport 4B |
| 5 QA intégration | QA locale réalisée : parcours complet Web/Flutter, sécurité, concurrence, Storage, fuseau, réseau/retry, audit ; 3 défauts client corrigés ([rapport](PHASE_5_QA_INTEGRATION_REPORT.md)) | Revue humaine ; Realtime, Brevo, Android/iOS, interfaces FR uniquement, charge |
| 6 Staging | Au 2 octobre : backend seul déployé sur `ordjngzihkmknnizlujp` (offre gratuite, production exclue) : 26 migrations, 461 assertions SQL distantes, 8 fonctions Edge vérifiées par HTTP, décodage images hébergé, aucune donnée de test conservée ([runbook](PHASE_6_STAGING_RUNBOOK.md)) | Frontends/domaines/e-mails reportés, D28 non décidé, workers et cron inactifs |
| 7 Production | Non commencée | Après validation du staging |

La roadmap nomme **4A Web et 4B Flutter** ; elle ne définit pas de phase 4D.

## Aperçus historiques : écarts conservés à titre de référence

Les lignes ci-dessous décrivent les anciens aperçus, toujours disponibles
explicitement. Le mode Web par défaut utilise maintenant `src/connect/`,
les contrats RPC générés et des formulaires dédiés ; ces anciens formulaires ne
sont pas branchés en CRUD sur les tables. Flutter reste à adapter.

| Source actuelle | Écart | Adaptation attendue en 4A/4B après les RPC |
|---|---|---|
| `apps/academy-admin/src/design/forms.ts`, players | Nom unique, parent libre et achat réunis dans un formulaire | `first_name/last_name`, âge daté ou naissance, liens multiples via memberships, achat de package séparé |
| Même fichier, sessions | Formule avec prix et nombre de séances, sans `price_basis` | Séparer `service_offers` versionnées, `player_packages` achetés et `sessions` planifiées ; sélectionner les UUID |
| Même fichier, stadiums | Terrain et nombre de courts regroupés | Site `stadiums`, ressources `courts` identifiées, choix du court par UUID |
| Même fichier, bookings | Choix par nom, prix saisi, pas de package/session explicite | Session/joueur/package identifiés ; RPC autoritaire, motif d'override, D34 PENDING sans crédit |
| Même fichier, team | Libellés d'accès génériques | Rôles fixes, invitation via Auth, aucun grant individuel |
| Même fichier, invoices | Paiement/facture simulés | Documents et encaissements séparés, montants exacts/devise, snapshots et RPC |
| Aperçus Web/Flutter | Données conservées en mémoire, sélection d'académie illustrative | Rechargement scoped, permissions réelles, erreurs et réessais idempotents |
| `apps/student/lib/main.dart` | `DESIGN_PREVIEW=true` par défaut ; sinon Firebase | Nouvelle entrée Supabase après 3B–3D, sans dépendance runtime ChallengeMe |
| `apps/student/lib/data/firebase_*` et écrans historiques | Anciennes collections globales | Repositories Supabase et projections autorisées, aucun réemploi des requêtes globales |
| Modes Firebase SportA | Petit socle Firestore, rôles/quota différents du contrat | Prototypes historiques, ne prouvent pas l'implémentation de Sport Connect |

Le branchement Web 4A est implémenté après la validation du socle 3D. Voir
[le rapport 4A](PHASE_4A_WEB_IMPLEMENTATION_REPORT.md) pour les preuves navigateur
et les limites du MVP. Le branchement Flutter 4B est décrit dans
[le rapport 4B](PHASE_4B_FLUTTER_IMPLEMENTATION_REPORT.md).

## Vérifications exécutées

| Commande | Résultat |
|---|---|
| `node scripts/test-database.mjs` | 25 migrations ; 427/427 assertions SQL (3A–3D) et 12/12 courses de concurrence, PostgreSQL 17.9 jetable |
| `npm run test:edge` / `test:edge:deno` / `check:edge` | 24/24 (Node), 24/24 (Deno), types des 8 fonctions |
| `npm test` | 3 tests Firebase unitaires réussis ; 1 test émulateurs ignoré sans émulateurs |
| `npm test --prefix apps/academy-admin` | 16/16 tests existants réussis ; concernent le code historique, pas Supabase |
| `npm run build --prefix apps/academy-admin` | Réussite, interface Supabase connectée compilée |
| `npm run test:flutter` / `lint:flutter` | 12 réussis, 1 ignoré sans configuration locale ; analyse sans problème |
| `npm run test:flutter:local` | Widgets + HTTP réel : parent, réservation/annulation, coach présence/évaluation, R=9 et H=0 |
| `npm run test:flutter:browser` | Build release Chromium 390 px, connexion parent et isolation du joueur non lié |
| `npm run build --prefix apps/platform-admin` | Réussite après installation des dépendances et nouveau point d’entrée HTML |
| `npm run test:web` / `lint:web` / `check:web-contracts` | 8/8 tests ; lint du nouveau code et contrats conformes |
| `npm run test:web:local` | Chromium : parcours métier, D34, concurrence, réessai idempotent, deux tenants, accès coach et mobile réussis |
| `supabase db reset --local` | 25 migrations appliquées sur la pile locale |
| `npm run test:supabase:db` | 427/427 assertions sur Supabase réel, cinq suites sélectionnées |
| `npm run test:supabase:local` | Auth, invitations, recovery, PostgREST, assets PNG/JPEG/WebP, rejeu, URLs signées et workers locaux réussis |
| Supabase CLI / Docker | CLI 2.118.0 et conteneurs locaux disponibles ; configuration corrigée et exécutée |

L'accès mémoire partagée PostgreSQL et le cache SDK Flutter étaient bloqués par
le sandbox ; les vérifications ont été exécutées après autorisation d'escalade.
Les tests autonomes utilisent des clusters temporaires. La validation 3D a
reconstruit uniquement la pile Supabase locale identifiée comme jetable ; 4A y
ajoute des données synthétiques sans réinitialisation.

## Changements utilisateur conservés

Avant intervention : suppression de `apps/platform-admin/.env.example`,
`.env.sporta`, `eslint.config.js`, `index.html` ; `.gitignore` non suivi dans ce
même dossier. En 4A, `index.html` et `.env.example` ont été recréés pour le mode
Supabase (aucune restauration des configurations Firebase supprimées). Les autres
suppressions et le `.gitignore` utilisateur sont conservés.

## Suite

3D est clôturée sur le périmètre local. La demande « Passez a la prochaine phase »
a autorisé le MVP Web 4A, implémenté et validé localement : prêt pour revue humaine.
4B Flutter est implémentée et validée localement sur Web : prêt pour revue humaine.
Android/iOS n'ont pas été exécutés. La QA d'intégration locale 5 est réalisée et
prête pour revue humaine. Brevo externe, rétention D28, charge, Realtime, langues
d'interface, staging et production restent à réaliser dans leurs périmètres.
