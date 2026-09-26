# Phase 3B — RLS Security Report

26 septembre 2026 — workspace `/Users/apple/Documents/SportA`, base `9814b80`.
Suite de la [phase 3A](PHASE_3A_DATABASE_IMPLEMENTATION_REPORT.md). Aucun backend
distant, aucune donnée ChallengeMe, aucun déploiement. **STOP pour revue humaine**
avant 3C, conformément à la roadmap.

## 1. Périmètre

3B ouvre uniquement des **lectures** aux clients `authenticated`. Aucune policy
d'écriture, aucune RPC de mutation : les mutations restent réservées aux RPC 3C.
`anon` n'exécute aucune fonction applicative et ne lit aucune table.

## 2. Migrations ajoutées

| Migration | Contenu |
|---|---|
| `20260926001400_authorization_helpers.sql` | Helpers `private.*` SECURITY DEFINER, `search_path = pg_catalog` : acteur actif, rôle/permission locale, permission plateforme, lien joueur, affectation coach, règles de lecture par ressource |
| `20260926001500_read_policies_and_column_grants.sql` | `GRANT SELECT` par **colonne** + une policy `SELECT` par table publique ; EXECUTE limité aux helpers utilisés par les policies |
| `20260926001600_authorized_read_projections.sql` | 19 projections `public.*` en lecture seule (JSON à champs fixes, pagination par curseur, fenêtres bornées) |

## 3. Modèle d'autorisation

- Identité : seul `auth.uid()` compte. Claims `role`, `academy_id`,
  `app_metadata`, `user_metadata` sont ignorés (testé).
- Droits recalculés à chaque requête depuis la base : profil `ACTIVE`, membership
  `ACTIVE`, académie `ACTIVE` non supprimée, rôle non révoqué, bundle fixe du rôle.
  Aucun cache : une révocation s'applique à l'instruction suivante (testé).
- Lien familial : `SELF` exige le rôle STUDENT, `GUARDIAN` le rôle PARENT, lien non
  révoqué. Un lien sans le rôle correspondant ne donne rien (testé avec Staff).
- Coach : seulement les séances dont il est le coach, via une fiche coach active
  rattachée à sa membership active. Rôle COACH sans fiche = aucune affectation.
- Plateforme : métadonnées d'académie, plans, abonnements, audit plateforme.
  Aucune permission plateforme n'ouvre joueurs, liens, réservations ou finance.

## 4. Protection des colonnes

Lecture directe (PostgREST) limitée aux colonnes non sensibles. Jamais accordées :
date de naissance/âge déclaré/genre, notes et snapshots contractuels de réservation,
prix et conditions de package, snapshots de facture, auteurs d'enregistrement,
`operation_id`. Ces données passent uniquement par des projections qui vérifient la
relation (ex. `get_player_profile` : date de naissance pour Owner/Admin/Manager ou
famille liée ; âge seul pour Staff/Coach).

| Donnée | Owner/Admin | Manager | Staff | Coach | Parent/Student |
|---|---|---|---|---|---|
| Joueurs | académie | académie | académie | séances affectées | liés |
| Naissance/genre | oui | oui | non | non | liés |
| Liens familiaux | tous | tous | propre lien | aucun | propre lien |
| Paiements/factures | académie | non | non | non | joueur lié |
| Prix du package | oui | non | non | non | non |
| Crédits R/H | oui | oui | A seulement | non | oui |
| Évaluations | académie | académie | non | ses séances | joueur lié |
| Invitations/audit | oui | non | non | non | non |

`list_player_packages` expose `available_sessions = R − H` calculé côté serveur
(H = réservations CONFIRMED sans consommation nette au ledger) ; aucune colonne
d'état de crédit n'est ajoutée.

## 5. Tests

`supabase/tests/database/003_authorization_reads.sql` : **92 assertions**, exécutées
réellement sous le rôle `authenticated` avec le sujet JWT de chaque acteur.

Couverture roadmap : Academy A/B ; membership suspendue, invitée, sans rôle ; profil
suspendu ; liens joueur et guardians multiples ; affectation coach ; révocation
(rôle coach, fiche coach, lien guardian, membership, profil, rôle plateforme,
académie suspendue) ; UUID forgés (joueur, facture, académie, package d'un autre
tenant) ; isolation finance ; plateforme vs tenant ; validation des pages/fenêtres.

Contrôle de sensibilité : une mutation volontaire du helper finance (lecture ouverte
à tout porteur de `payments.read`) fait échouer la suite, puis a été annulée.

| Commande | Résultat |
|---|---|
| `npm run test:database` | 16 migrations ; **215/215** assertions (78 + 45 + 92), PostgreSQL 17.9 |

## 6. Limites

- Validé sur PostgreSQL avec le substitut `auth.uid()` ; PostgREST, JWT signés,
  Realtime et Storage ne sont pas testés (CLI Supabase/Docker absents).
- Les policies appellent des helpers par ligne : à mesurer sur volume réel avant
  production (index existants sur `academy_id`, pas de benchmark réalisé).
- Une réservation supprimée mais encore CONFIRMED compte dans H ; la sémantique
  d'archivage relève des transitions 3C.
- Le Staff voit le nom affiché des membres actifs (sans téléphone ni user_id) pour
  planifier ; à confirmer en revue.
- Les parents ne voient pas le prix total de leur package (seulement leurs
  paiements/factures) ; choix conservateur à confirmer en revue.

## 7. Points de revue avant 3C

1. Matrice du §4, en particulier les deux derniers points des limites.
2. Validation sur runtime Supabase complet (PostgREST exposant `public` seulement).
3. Autorisation de démarrer 3C (RPC atomiques R/H/A, quotas, finance, idempotence).
