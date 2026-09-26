# Phase 3C — Business RPC Report

26 septembre 2026 — workspace `/Users/apple/Documents/SportA`, base `9814b80`.
Suite de [3A](PHASE_3A_DATABASE_IMPLEMENTATION_REPORT.md) et [3B](PHASE_3B_RLS_SECURITY_REPORT.md).
Autorisation : demande humaine « Passez au 3C ». Aucun backend distant, aucune
donnée ChallengeMe, aucun déploiement. **STOP pour revue humaine** avant 3D.

## 1. Migrations ajoutées

| Migration | Contenu |
|---|---|
| `20260926001700_command_infrastructure.sql` | Codes d'erreur, reçus idempotents, audit, outbox, rappels, validation monétaire exacte, arithmétique R/H/A, mouvement ledger + cache |
| `20260926001800_booking_engine.sql` | 8 RPC de réservation/présence, ordre de verrous, contrôles et overrides |
| `20260926001900_players_packages_finance.sql` | Joueurs, liens familiaux, forfaits, crédits, paiements, factures (13 RPC) |
| `20260926002000_access_catalog_sessions.sql` | Rôles/invitations, académie et SaaS, ressources, coachs, offres versionnées, séances, évaluations, tournois (38 RPC) |

**59 RPC** `public.*` : SECURITY DEFINER, `search_path = pg_catalog`, exécutables
par `authenticated` uniquement. Aucune policy d'écriture : les tables restent en
lecture seule côté client (3B).

## 2. Contrat commun (C0)

- Acteur = `auth.uid()` avec profil actif ; permission et relation revérifiées dans
  la transaction ; académie explicite.
- `operation_key` obligatoire. Reçu `(acteur, rpc, clé)` avec hash des arguments
  et du tenant : un rejeu renvoie le résultat enregistré sans nouvel effet ; même
  clé et autre contenu → `IDEMPOTENCY_CONFLICT`. Deux rejeux simultanés sont
  sérialisés par un verrou consultatif transactionnel.
- `expected_revision` sur les objets versionnés → `STALE_REVISION`.
- Audit, événements de réservation, outbox et reçu dans la même transaction, avec le
  même `operation_id`. Les FK différées vérifient au commit que chaque effet pointe
  vers un reçu du même tenant.
- Erreurs : message = code stable. `42501` FORBIDDEN, `P0002` NOT_FOUND (également
  pour une ressource hors périmètre, afin de ne pas révéler son existence), `22023`
  entrée invalide, `P0001` refus métier.
- Montants : chaîne décimale exacte validée **avant** le cast `numeric(18,2)` ; XAF
  entier (`1000` ou `1000.00`), autres devises ≤ 2 décimales ; notation scientifique
  et devises inconnues refusées.

## 3. Réservations — D30/D34

Ordre de verrous : joueur → séance → forfait → réservation. R/H/A sont recomptés
après verrouillage, en incluant les réservations invisibles à l'acteur.

| Commande | Effet |
|---|---|
| request_booking | Famille liée (ou opérateur) ; PENDING si A ≥ 1 ; aucune place ni aucun hold |
| schedule_booking | CONFIRMED si A ≥ 1 (H+1, place+1, rappel 24 h) ; **override quota à A = 0 → PENDING + OVERRIDE_USED (D34)** |
| approve_booking | PENDING → CONFIRMED sous verrou ; un override quota ne confirme jamais sans crédit |
| reject / cancel | Staff : terminal, libère place et H sans ledger. Famille : retrait de son propre PENDING |
| record_attendance | PRESENT consomme le crédit réservé même si A = 0 ; ABSENT libère sans débit ; corrections compensatoires exactes, ABSENT → PRESENT exige A ≥ 1 |
| complete_booking | Consomme sans fabriquer de présence ; avant le début → refus (D29) |
| archive_booking | COMPLETED : places et crédits intacts ; actif : annulation puis archivage dans la même transaction |

Les cinq overrides (capacité, âge, offre, quota, chevauchement joueur) exigent
chacun leur permission exacte et un motif ; seuls les contrôles réellement dérogés
sont inscrits dans `OVERRIDE_USED`. L'état/la date de séance, l'activité/le type,
le tenant, le court et le coach ne sont jamais dérogeables.

## 4. Autres domaines

- **Joueurs/liens** : un parent crée un enfant lié GUARDIAN, un élève crée son SELF ;
  plusieurs guardians ; un seul SELF/principal/financier actif ; la révocation ne
  désigne pas de successeur ; l'audit nomme les champs modifiés, jamais leurs valeurs.
- **Forfaits** : prix figé (PACKAGE = prix, SESSION = prix × séances, borné).
  Crédits uniquement après un paiement confirmé du montant exact ou pour un forfait
  gratuit explicite ; ajustement manuel avec R' ≥ 0 et R' ≥ H.
- **Finance** : Owner/Admin seulement ; devise identique au forfait ; un paiement
  confirmé par forfait ; une facture par paiement, numéro fourni (D32).
- **Accès** : rôles fixes ; pas d'action sur soi ; OWNER réservé à `transfer_owner` ;
  garde du dernier owner actif ; invitation normalisée, bornée à 30 jours, sans email
  dans l'outbox (livraison et acceptation en 3D).
- **Plateforme** : création d'académie + invitation du premier owner en une
  opération ; statut d'académie ; plans sans prix ; cycle d'abonnement journalisé.
- **Catalogue sportif** : ressources, coach rattaché à une membership COACH
  existante, offres versionnées (une seule publiée par série), séances arbitrées par
  les exclusions court/coach, annulation de séance atomique et bornée (200).

## 5. Tests

| Suite | Assertions |
|---|---|
| `001_foundation.sql` / `002_history_scope_finance.sql` (3A) | 78 + 45 |
| `003_authorization_reads.sql` (3B) | 92 |
| `004_business_rpc.sql` (3C, transactionnel) | **142** |
| `supabase/tests/concurrency/` (3C, deux connexions) | **8 scénarios** |

Les 8 courses de la roadmap passent : dernier crédit, dernière place, double
approbation, annulation contre présence, rejeu, double compensation, même court,
même coach. Pour chaque course, A exécute sa commande puis attend à une « porte »
en conservant ses verrous. On constate dans `pg_stat_activity` que B est bloqué ;
la porte s'ouvre ensuite, puis l'état final est vérifié.

Tests de mutation (défaut volontaire, puis restauration à l'identique) :

| Mutation | Test qui échoue |
|---|---|
| Sans verrou de séance | Dernière place : B sur-réserve |
| Sans verrou d'idempotence | Rejeu : B ne renvoie pas le reçu |
| Override quota qui confirme | D34 dans `004` |

`npm run test:database` : 20 migrations, **357 assertions SQL + 8 scénarios de
concurrence**, PostgreSQL 17.9.

## 6. Problèmes trouvés et corrigés

- `ALTER DEFAULT PRIVILEGES IN SCHEMA … REVOKE EXECUTE` ne retire pas l'EXECUTE
  global accordé à PUBLIC. Les nouvelles fonctions internes restaient donc
  exécutables par PUBLIC. Le schéma `private` restait inaccessible, mais chaque
  migration 3C révoque maintenant explicitement ces droits, et un test le vérifie.
- L'assertion 3B « aucune fonction publique volatile » est remplacée par « les 19
  projections sont STABLE ».

## 7. Décisions ouvertes : refus explicites plutôt que règles inventées

| Décision | Comportement actuel |
|---|---|
| D05 : annulation ou refus d'un CONFIRMED par la famille | `MEMBER_POLICY_UNRESOLVED` |
| D29 : complétion administrative avant le début | `COMPLETION_BEFORE_START_UNRESOLVED` |
| D32/D26 : numérotation et mentions des factures | Numéro fourni par l'académie ; instantané client minimal |
| D32 SaaS : effets d'une suspension commerciale | Statut journalisé, aucune restriction appliquée |
| D17 : durée d'essai | Date explicite obligatoire |

Hors 3C : acceptation des invitations, parcours Auth, assets/Storage, destinataires
et relance des notifications, workers (3D).

## 8. Limites

- Tests sur PostgreSQL avec le substitut `auth.uid()` ; PostgREST, JWT signés et
  runtime Supabase complet non testés.
- Un joueur sans âge connu est traité comme non éligible (override d'âge nécessaire).
- `amount_snapshot` d'une réservation vaut le prix unitaire pour un forfait SESSION
  et 0 pour un forfait PACKAGE : aucun prix n'est obtenu par division.
- Pas de benchmark de charge.

## 9. Points de revue avant 3D

1. Les refus D05/D29 conviennent-ils jusqu'à décision ?
2. Codes d'erreur et formes de résultat : contrat à figer pour 4A/4B.
3. Borne d'invitation (30 jours) et rappel à 24 h (repris de V1).
4. Autorisation de démarrer 3D (Auth, invitations, Storage, Edge/workers).
