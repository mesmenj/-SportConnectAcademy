# Phase 3A — Database Implementation Report

26 septembre 2026 — workspace `/Users/apple/Documents/SportA`, base `9814b80`.
La reprise porte sur les fichiers effectivement disponibles. Aucun rapport 3D ni
implémentation Supabase antérieure n'a été trouvé. Voir aussi
[l'état global et les écarts UI](IMPLEMENTATION_STATUS.md).

## 1. Greenfield Boundary Verification

Le socle PostgreSQL a été construit dans SportA exclusivement. Aucun utilisateur,
enregistrement ou identifiant Firebase n'est importé. Les tests utilisent des UUID
synthétiques et `example.test`. Les anciennes interfaces/modes Firebase restent
présents comme prototypes ; ils ne constituent pas une cible Supabase conforme.

## 2. ChallengeMeAcademy Integrity Verification

Seules les spécifications V1/V1.1 ont été lues puis copiées dans SportA. `cmp`
confirme que les copies restent identiques à leurs sources. Aucune commande
d'écriture, déploiement ou seed n'a ciblé les repositories ou services ChallengeMe.
Il n'y a pas eu de snapshot de production ni de contrôle distant : aucune
affirmation d'audit de production n'est faite.

## 3. Final Table Count

**41 tables : 24 public, 17 private**, comptées dans le catalogue PostgreSQL après
application des migrations. `auth.users` est une dépendance Supabase, exclue du
compte applicatif. Le substitut de test n'est pas une migration applicative.

## 4. Tables Removed From V1.1

T40 `legacy_identity_map`, T41 `legacy_entity_map`, T42 `migration_issues` : aucune
FK opérationnelle indispensable. T43 `command_receipts`, T44 `academy_assets` et
T39 `audit_log` sont conservées. Aucun `credit_holds`.

## 5. Files Created

- `AGENTS.md` : contexte de reprise et invariants.
- `docs/IMPLEMENTATION_ROADMAP.md` : copie de la roadmap fournie.
- `docs/IMPLEMENTATION_STATUS.md` : audit d'état et écarts UI.
- `docs/database/SPORT_CONNECT_DATABASE_DESIGN_V1.md` et `V1_1.md` : copies sources.
- `docs/database/SPORT_CONNECT_DATABASE_GREENFIELD_FINAL.md` : contrat final.
- Le présent rapport.
- `supabase/README.md`, `supabase/config.toml`.
- Les 13 migrations ci-dessous.
- `supabase/local/auth-test-bootstrap.sql` : uniquement pour le banc de test.
- `supabase/tests/database/001_foundation.sql`, `002_history_scope_finance.sql`,
  `support/helpers.sql`, `support/fixtures.sql`.
- `scripts/test-database.mjs` : cluster jetable, application et assertions SQL.

Fichiers existants modifiés : `README.md` et `package.json` (`test:database`).

## 6. Migrations Created

Toutes sont dans `supabase/migrations/`, horodatées `2026092600NN00`.

| NN | Suffixe | Contenu |
|---|---|---|
| 01 | extensions_and_schemas | private, extensions, btree_gist, restrictions |
| 02 | identity_and_platform | Identité Supabase, catalogues et racine academy |
| 03 | academy_access | Memberships, rôles et intentions d'invitation |
| 04 | sport_core | Joueurs/liens, coachs, sites/courts, communautés |
| 05 | packages_and_ledger | Offres versionnées, achats, ledger |
| 06 | sessions_and_bookings | Séances, réservations, présence, évaluations |
| 07 | finance_and_subscriptions | Paiements, factures, tournois, SaaS manuel |
| 08 | notifications_and_audit | Outbox, livraisons, payloads, rappels, audit |
| 09 | assets_and_internal_support | Reçus idempotents et métadonnées assets |
| 10 | constraints_and_exclusions | 154 FK et deux exclusions GiST |
| 11 | indexes | 34 index de lecture/travail, en plus des PK/uniques/exclusions |
| 12 | rbac_seed | 91 actions, 2 rôles plateforme, 7 rôles academy |
| 13 | integrity_and_rls_deny_by_default | Immutabilité, scope, append-only, RLS |

Les FK cycliques sont ajoutées une fois les tables créées. Les futurs reçus peuvent
être insérés après leurs effets dans la même transaction.

## 7. Schemas

`public` : tables clients candidates, protégées et sans accès en 3A. `private` :
attributions, journaux, outbox et supports internes non exposés. `extensions` :
extension technique. `auth` est fourni par Supabase en environnement réel.

## 8. Extensions

`btree_gist` pour les clés UUID des exclusions. `pgcrypto` n'est pas nécessaire :
PostgreSQL 17 fournit `gen_random_uuid()` nativement. Les hashes seront produits
ou validés par les commandes futures ; leur format est contrôlé par le DDL.

## 9. Tables

Le [catalogue final](database/SPORT_CONNECT_DATABASE_GREENFIELD_FINAL.md#c-catalogue-final)
énumère les 41 tables et leurs schémas. Tous les objets sont créés par migrations,
aucune modification manuelle de base n'est requise.

## 10. Tenant-aware Foreign Keys

154 FK avec ON UPDATE/DELETE RESTRICT. Relations sportives composites, package du
bon joueur, court du bon stade, évaluation du bon booking/séance/coach, facture du
bon paiement/joueur. La facture garde une FK tenant sur le paiement même avec un
joueur NULL. Assets et logo/couverture liés au bon tenant. Les effets ont en plus
un contrôle différé du scope de leur reçu ; les notifications PLATFORM à academy
NULL ne contournent pas le contrôle de scope parent/enfant.

## 11. Constraints

Statuts fermés, champs requis, bornes, JSON objets bornés, UUID, revision > 0,
montants exacts numeric(18,2), XAF entier, refus de NaN, soldes/compteurs ≥ 0.
Plusieurs guardians et uniques partiels SELF/principal/contact financier.
Unique publication academy/offer_key, unique booking PENDING/CONFIRMED sans filtre
deleted_at, paiement confirmé unique par package, facture unique par paiement.
Publication publique interdite, bucket prévu privé et chemin asset construit à
partir des UUID. Les scopes/identités/provenances sont immuables et les journaux
append-only, y compris face à TRUNCATE.

Les règles multi-lignes de crédit/capacité ne sont **pas** déclarées réalisées :
elles appartiennent aux RPC 3C. La DB exige un package sur CONFIRMED/COMPLETED,
mais cela ne prouve pas à lui seul A ≥ 1 à la confirmation.

## 12. Exclusion Constraints

Deux GiST locales à academy : court et coach, intervalle `[starts_at, ends_at)`,
états OPEN/CLOSED. CANCELLED libère les ressources ; les créneaux adjacents sont
acceptés. Aucun verrou/exclusion global par utilisateur Auth.

## 13. Indexes

Les index de lecture suivent V1/V1.1 : annuaires, calendriers, historique,
encaissements, audit, files de travail et purge. I38 confirmations par package
inclut les lignes archivées ; I39 couvre les mouvements par booking pour calculer
le net consommé. Aucun unique sur durée d'offre ni exclusion d'âge.

## 14. RBAC Seeds

91 permissions fermées, 18 attributions plateforme et 308 attributions academy.
Pas de permission utilisateur libre. Owner/Admin finance et accès ; Manager sport
sans finance/gestion des membres ; Staff sans override ; Coach sans finance ;
Student/Parent sans opérations staff. Seul Owner transfère la propriété.
La relation SELF/GUARDIAN/affectation et les projections restent à implémenter :
le catalogue de permission n'est pas une policy RLS.

## 15. RLS Deny-by-default

RLS activé sur les 41 tables ; aucun CREATE POLICY. Privileges directs retirés à
PUBLIC, anon et authenticated ; schéma private et fonctions internes inaccessibles.
Un test accorde temporairement SELECT pour prouver que RLS masque encore toutes
les lignes, et INSERT pour prouver que RLS refuse toujours l'écriture.

## 16. Tests Created

Deux suites SQL TAP, sans pgTAP externe : 78 assertions fondation et 45 assertions
historique/scope/finance/assets. Elles vérifient aussi les codes SQLSTATE attendus
pour distinguer un vrai rejet tenant d'une autre erreur. Helpers/fixtures ne sont
chargés que dans des transactions de test annulées.

## 17. Tests Executed

`node scripts/test-database.mjs` sous PostgreSQL **17.9 Homebrew** : nouveau cluster
isolé, Auth minimal de test, 13 migrations exécutées en transactions, deux suites,
arrêt du serveur. Le lancement initial a rencontré le refus de mémoire partagée
du sandbox ; il a été relancé avec l'escalade autorisée.

Également : compilation et 16 tests Academy Admin, 3 tests Flutter, 3 tests
unitaires du backend Firebase existant. Ces tests UI/historiques ne prouvent pas
une intégration Supabase. Un test Firebase émulateur était ignoré.

## 18. Test Results

**123/123 assertions SQL réussies.** Toutes les migrations appliquées depuis une
base vide. Les échecs intermédiaires concernaient deux fixtures ayant provoqué une
unicité avant la FK/scope visée ; les fixtures ont été corrigées pour tester le
contrôle attendu. Aucun échec restant dans les suites exécutées.

Runtime Supabase complet : `LOCAL_RUNTIME_NOT_AVAILABLE` (CLI et Docker absents).
Validation Auth/JWT/PostgREST/Storage/Edge non exécutée. Le test PostgreSQL est
l'équivalent local autorisé pour le DDL, pas une simulation d'intégration complète.
Platform Admin : build bloqué par `tsc` absent ; entrée HTML déjà supprimée.

## 19. Design Deviations

Trois adaptations explicites au catalogue historique, décrites dans le contrat final :

1. Greenfield : retrait des trois tables et des valeurs/colonnes exclusivement
   migration ; dates d'événements obligatoires ; aucun état LEGACY opérationnel.
2. CHECK package obligatoire pour CONFIRMED/COMPLETED, traduction physique du
   contrat opérationnel dans une base sans états legacy importés.
3. `pgcrypto` non activé : UUID natif PostgreSQL 17 suffisant.

Durcissements structurels : JSON objets bornés, refus NaN, chemins assets exacts,
checks de bail, motifs d'override et protection append-only. Aucun trigger ne
simule une RPC booking. Aucun changement de D34, des rôles ou des cardinalités.

## 20. Problems Found

- Les livrables 3A–3D annoncés n'étaient pas présents ; aucun état terminé n'a été
  supposé à partir de cette annonce.
- UI existantes fictives/Firebase, modèles incompatibles avec le contrat cible.
- Stack Supabase locale complète absente ; config CLI à valider ultérieurement.
- Platform Admin a des suppressions préexistantes et des dépendances absentes.
- numeric(18,2) arrondit avant CHECK : le futur endpoint doit valider la précision
  brute avant cast. Le DDL ne peut pas rejeter seul toutes les entrées à >2 décimales.

Aucun blocage restant pour la fondation PostgreSQL livrée. Ces limites bloquent
l'annonce d'un MVP intégré ou d'une phase 3D terminée.

## 21. Remaining Product Decisions

D05 annulation, D29 complétion anticipée, D32 numérotation facture, langue/timezone,
rétention et paramètres commerciaux/facturation : non bloquants pour DDL, à traiter
avant les commandes concernées. D34 est fermé : override quota sans crédit →
PENDING, avec motif et OVERRIDE_USED ; jamais disponibilité négative.

## 22. Git Diff — Sport Connect Academy Only

FILES MODIFIED IN SPORT CONNECT ACADEMY : ajouts listés §5, plus README.md et
package.json. Aucun changement des sources UI ou du backend Firebase.

Changements antérieurs conservés : quatre suppressions Platform Admin
(.env.example, .env.sporta, eslint.config.js, index.html) et son .gitignore non suivi.
`git diff --check` exécuté. Les copies V1/V1.1 sont identiques aux sources.
Aucun commit ni déploiement effectué.

## 23. Confirmation No ChallengeMeAcademy File Was Modified

FILES MODIFIED IN CHALLENGEMEACADEMY : **NONE** par cette intervention.
Aucun service distant contacté par les migrations/tests. Aucun utilisateur,
secret, configuration, donnée ou index ChallengeMe modifié.

Le point d'arrêt 3A de la roadmap est respecté. Le prochain chantier technique
est 3B, après revue, puis 3C/3D avant la connexion des UI 4A/4B.

```text
STATUS: PHASE 3A READY FOR HUMAN REVIEW

PROJECT: SPORT CONNECT ACADEMY
PROJECT TYPE: GREENFIELD

GREENFIELD DESIGN FINALIZED: YES

EXPECTED TABLE COUNT: 41
ACTUAL TABLE COUNT: 41

LEGACY CHALLENGEME MIGRATION TABLES CREATED: NO
CHALLENGEME FILES MODIFIED: NO
CHALLENGEME FIREBASE MODIFIED: NO
CHALLENGEME DATA MODIFIED: NO

LOCAL MIGRATIONS CREATED: YES
LOCAL MIGRATIONS APPLIED: YES — DISPOSABLE POSTGRESQL 17 CLUSTER

LOCAL TESTS EXECUTED: YES
LOCAL TESTS PASSED: 123/123

REMOTE SUPABASE MODIFIED: NO
PRODUCTION DATA MODIFIED: NO

DESIGN DEVIATIONS: 3
BLOCKING IMPLEMENTATION ISSUES: 0 — FOR PHASE 3A POSTGRESQL FOUNDATION

NEXT AUTHORIZED PHASE: NONE — HUMAN REVIEW REQUIRED
```
