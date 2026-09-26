# État vérifié — Sport Connect Academy

Vérification du 26 septembre 2026 dans `/Users/apple/Documents/SportA`, branche
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
| 3A PostgreSQL | Implémenté et testé localement : 123 assertions | Validation sur runtime Supabase complet |
| 3B RLS | Lectures implémentées et testées localement : 92 assertions ([rapport](PHASE_3B_RLS_SECURITY_REPORT.md)) | Revue humaine ; validation PostgREST/JWT réels |
| 3C RPC | 59 RPC implémentées : 142 assertions et 8 courses à deux connexions ([rapport](PHASE_3C_BUSINESS_RPC_REPORT.md)) | Revue humaine ; décisions D05/D29/D32 ; validation sur runtime Supabase |
| 3D Auth/Storage/Edge | Implémenté localement : 70 assertions `005`, 4 courses 3D, 24 tests Edge ([rapport](PHASE_3D_AUTH_STORAGE_EDGE_REPORT.md)) | Pile Supabase complète (Docker/CLI) jamais exécutée ; `test:supabase:local` à lancer |
| 4A Web académie | Aperçu interactif existant, compilation et tests réussis | Modèles typés, Supabase Auth, requêtes/RPC et états d'erreur |
| 4A Web plateforme | Aperçu partagé existant, ancien mode Firebase | Entrée HTML supprimée avant reprise et dépendances absentes ; intégration Supabase absente |
| 4B Flutter | Aperçu interactif existant, 3 tests réussis | Auth Supabase, contexte tenant, repositories/RPC, adaptation des modèles |
| 5 QA intégration | Non réalisée sur la cible | Parcours complet et tests réseau/concurrence/langue/timezone |
| 6/7 staging/production | Non vérifiés, aucune modification | Après les phases et validations précédentes |

La roadmap nomme **4A Web et 4B Flutter** ; elle ne définit pas de phase 4D.

## Interfaces : écarts concrets avec les tables

Les interfaces sont réutilisables visuellement mais leur état local ne constitue
pas un contrat de données. Aucun écran ne doit être branché directement en CRUD
sur les nouvelles tables.

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

Les modifications UI ne sont pas activées prématurément : leurs commandes et
RPC et le socle 3D existent localement ; leur validation sur pile Supabase réelle précède le branchement.

## Vérifications exécutées

| Commande | Résultat |
|---|---|
| `node scripts/test-database.mjs` | 24 migrations ; 427/427 assertions SQL (3A–3D) et 12/12 courses de concurrence, PostgreSQL 17.9 jetable |
| `npm run test:edge` / `test:edge:deno` / `check:edge` | 24/24 (Node), 24/24 (Deno), types des 8 fonctions |
| `npm test` | 3 tests Firebase unitaires réussis ; 1 test émulateurs ignoré sans émulateurs |
| `npm test --prefix apps/academy-admin` | 16/16 tests existants réussis ; concernent le code historique, pas Supabase |
| `npm run build --prefix apps/academy-admin` | Réussite, aperçu Vite compilé |
| `flutter test test/design_preview_test.dart` dans apps/student | 3/3 widgets réussis |
| `npm run build --prefix apps/platform-admin` | Échec initial `tsc: command not found` ; dépendances absentes |
| Supabase CLI / Docker | Non disponibles ; aucune validation Auth/API/Storage complète revendiquée |

L'accès mémoire partagée PostgreSQL et le cache SDK Flutter étaient bloqués par
le sandbox ; les vérifications ont été exécutées après autorisation d'escalade.
Les fichiers de test sont temporaires ; aucune base existante n'a été réinitialisée.

## Changements utilisateur conservés

Avant intervention : suppression de `apps/platform-admin/.env.example`,
`.env.sporta`, `eslint.config.js`, `index.html` ; `.gitignore` non suivi dans ce
même dossier. Aucun de ces fichiers n'a été restauré/modifié.

## Suite

3B, 3C et 3D sont implémentées localement. Avant 4A/4B : exécuter la pile Supabase
complète (`test:supabase:local`) et obtenir la revue humaine de 3C/3D.
