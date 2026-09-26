# SPORT CONNECT ACADEMY — MASTER IMPLEMENTATION ROADMAP

## MISSION GÉNÉRALE

Nous avons terminé :

1. l’audit de ChallengeMeAcademy ;
2. `SPORT_CONNECT_DATABASE_DESIGN_V1.md` ;
3. `SPORT_CONNECT_DATABASE_DESIGN_V1_1.md` ;
4. la revue humaine de l’architecture.

Nous passons maintenant de la **conception** à la **construction réelle de Sport Connect Academy**.

Sport Connect Academy est un **nouveau produit greenfield indépendant**.

ChallengeMeAcademy a servi uniquement à :

* comprendre le métier ;
* identifier les workflows utiles ;
* comprendre les règles existantes ;
* identifier les défauts techniques à éviter ;
* guider la conception de Sport Connect Academy.

ChallengeMeAcademy n'est PAS le système cible.

---

# 0. RÈGLE ABSOLUE — CHALLENGEMEACADEMY EST READ-ONLY

ChallengeMeAcademy doit rester totalement intact.

Aucune modification n'est autorisée sur :

* `classcard-admin`;
* `classcard-functions`;
* `classcard_student`;
* Firebase Auth ChallengeMeAcademy ;
* Firestore ChallengeMeAcademy ;
* Storage ChallengeMeAcademy ;
* Firebase Functions ;
* Firebase Rules ;
* Firebase indexes ;
* Firebase configuration ;
* données ;
* utilisateurs ;
* secrets ;
* environnements ;
* CI/CD ;
* déploiements ;
* scripts existants.

## Opérations interdites

Ne jamais exécuter contre ChallengeMeAcademy :

* écriture Firestore ;
* migration ;
* correction ;
* backfill ;
* seed ;
* script de transformation ;
* déploiement ;
* modification Firebase Auth ;
* modification Storage ;
* modification Cloud Functions ;
* `firebase deploy`;
* suppression ;
* dual-write ;
* synchronisation avec Sport Connect Academy.

ChallengeMeAcademy peut uniquement être :

```text
READ
INSPECT
SEARCH
COMPARE
REFERENCE
```

Si une commande ou modification pourrait toucher ChallengeMeAcademy :

```text
STOP
```

---

# 1. SPORT CONNECT ACADEMY EST UN PROJET INDÉPENDANT

Sport Connect Academy doit posséder ses propres :

* repository / workspace ;
* application Flutter ;
* application Web de gestion ;
* PostgreSQL ;
* projet Supabase ;
* Supabase Auth ;
* Supabase Storage ;
* Edge Functions ;
* migrations ;
* tests ;
* secrets ;
* environnements ;
* utilisateurs ;
* données.

Aucune dépendance runtime vers ChallengeMeAcademy.

Architecture attendue :

```text
ChallengeMeAcademy
      │
      │ référence read-only
      ▼
Connaissance métier
      │
      ▼
SPORT CONNECT ACADEMY
      │
      ├── Flutter
      ├── Web Back Office
      ├── Supabase Auth
      ├── PostgreSQL
      ├── Storage
      ├── Realtime
      └── Edge Functions
```

---

# 2. ORDRE DE PRIORITÉ DES SOURCES

Pour toute décision future :

```text
1. Décisions humaines Sport Connect Academy
2. SPORT_CONNECT_DATABASE_DESIGN_V1_1.md
3. SPORT_CONNECT_DATABASE_DESIGN_V1.md
4. AUDIT.md
5. Code ChallengeMeAcademy en lecture seule
```

En cas de conflit :

```text
SPORT CONNECT ACADEMY > ChallengeMeAcademy
```

ChallengeMeAcademy documente l'ancien système.

Il ne doit pas imposer ses défauts au nouveau.

---

# 3. D34 EST DÉSORMAIS FERMÉ

Mettre :

```text
D34 = DECIDED — HUMAN
```

Décision retenue :

## Quota override ne permet pas une confirmation sans crédit

Variables :

```text
R = remaining_sessions
H = confirmed_unconsumed_bookings
A = R - H
```

Invariant :

```text
R >= 0
H <= R
A >= 0
```

Un booking ne peut devenir :

```text
CONFIRMED
```

que si :

```text
A >= 1
```

après verrou du package et recalcul serveur.

Si un utilisateur autorisé utilise :

```text
bookings.override.quota
```

alors que :

```text
A = 0
```

le booking reste ou devient :

```text
PENDING
```

avec :

```text
OVERRIDE_USED
```

et raison obligatoire.

Il sera confirmable ultérieurement lorsqu'un crédit deviendra disponible.

Ne jamais créer :

* `credit_holds`;
* `hold_exempt`;
* crédit fictif ;
* A négatif ;
* CONFIRMED sans crédit couvert ;
* CONFIRMED opérationnel sans package résolu.

---

# 4. GREENFIELD CLEANUP AVANT SQL

Avant de créer la base, relire V1/V1.1 et identifier toutes les structures existant uniquement pour une migration ChallengeMeAcademy.

Les tables actuellement identifiées sont :

```text
legacy_identity_map
legacy_entity_map
migration_issues
```

Sport Connect Academy étant greenfield :

ces tables ne doivent PAS faire partie du MVP.

Ne pas créer :

* Firebase UID mapping ;
* Firestore entity mapping ;
* migration quarantine ChallengeMe ;
* staging ChallengeMe ;
* migration scripts ChallengeMe ;
* reconciliation tables ChallengeMe.

## Important

Ne supprime PAS :

```text
command_receipts
audit_log
academy_assets
```

simplement parce qu'elles se trouvent près des tables migration.

Elles servent au nouveau système lui-même.

---

# 5. NOMBRE DE TABLES CIBLE

Le design V1.1 contient 44 tables.

Trois tables semblent exclusivement liées à la migration ChallengeMeAcademy :

```text
legacy_identity_map
legacy_entity_map
migration_issues
```

La cible Greenfield devrait donc être :

```text
41 tables
```

Mais NE PAS forcer artificiellement le chiffre 41.

Avant SQL :

1. vérifier les 44 tables ;
2. confirmer lesquelles sont exclusivement legacy ;
3. vérifier leurs dépendances ;
4. produire le catalogue final Greenfield ;
5. expliquer toute différence.

Si seules T40, T41 et T42 sont retirées :

```text
FINAL TABLE COUNT = 41
```

---

# 6. CRÉER LE CONTRAT GREENFIELD FINAL

Avant les migrations, produire :

```text
SPORT_CONNECT_DATABASE_GREENFIELD_FINAL.md
```

Ce document ne doit PAS recommencer un audit de 1 000 lignes.

Il doit être court et normatif.

Il doit contenir :

## A. Greenfield principles

## B. ChallengeMeAcademy read-only boundary

## C. Final table list

## D. Tables removed from V1.1

## E. D34 final decision

## F. Final RBAC

## G. Final booking/credit invariants

## H. Final dependency order

## I. Remaining product decisions that do NOT block DDL

## J. SQL implementation authorization

Terminer cette section par :

```text
GREENFIELD DESIGN STATUS: READY FOR DDL
CHALLENGEMEACADEMY MODIFIED: NO
LEGACY MIGRATION TABLES INCLUDED: NO
EXPECTED TABLE COUNT: <number>
```

---

# 7. IMPORTANT — NE PAS CONFONDRE ROADMAP ET AUTORISATION

Les phases suivantes constituent la roadmap complète :

```text
PHASE 3A — Database Foundation
PHASE 3B — RLS Security
PHASE 3C — Business RPC
PHASE 3D — Auth / Storage / Edge
PHASE 4A — Web Back Office
PHASE 4B — Flutter App
PHASE 5 — Integration & QA
PHASE 6 — Staging
PHASE 7 — Production
```

Mais pour cette mission :

# TU ES AUTORISÉ UNIQUEMENT À EXÉCUTER :

```text
GREENFIELD FINALIZATION
+
PHASE 3A
```

À la fin de Phase 3A :

```text
STOP
```

Ne commence pas Phase 3B sans nouvelle autorisation humaine.

---

# ============================================================

# PHASE 3A — DATABASE FOUNDATION

# ============================================================

# 8. OBJECTIF PHASE 3A

Construire localement le socle PostgreSQL/Supabase de Sport Connect Academy.

Créer :

* schemas ;
* extensions nécessaires ;
* tables ;
* colonnes ;
* PK ;
* FK ;
* FK tenant-aware ;
* uniques ;
* CHECK ;
* exclusion constraints ;
* indexes ;
* rôle/permission catalogs ;
* seed RBAC ;
* RLS activé en deny-by-default ;
* tests d'intégrité.

Ne PAS encore créer :

* policies RLS complètes ;
* business RPC complètes ;
* Edge Functions ;
* Storage bucket réel ;
* Flutter ;
* Web UI ;
* données production.

---

# 9. WORKSPACE

Identifier le workspace Sport Connect Academy.

## Si un projet Sport Connect Academy existe déjà

Utiliser uniquement celui-ci.

## Si aucun projet Sport Connect Academy n'existe

Créer un nouveau workspace indépendant, par exemple :

```text
sport-connect-academy/
```

Il doit être séparé des repositories ChallengeMeAcademy.

Ne pas créer Sport Connect Academy à l'intérieur de :

```text
classcard-admin/
classcard-functions/
classcard_student/
```

Si le workspace courant ne permet pas de créer un projet indépendant sans risque :

STOP et documenter :

```text
SPORT_CONNECT_WORKSPACE_REQUIRED
```

Ne jamais utiliser ChallengeMeAcademy comme dossier cible par commodité.

---

# 10. INSPECTION INITIALE

Dans Sport Connect Academy uniquement, inspecter :

```text
supabase/
supabase/config.toml
supabase/migrations/
supabase/tests/
supabase/seed.sql
.env*
README*
package.json
pubspec.yaml
```

et toute configuration existante.

Documenter ce qui existe avant modification.

Ne jamais copier :

* `.env` ChallengeMe ;
* Firebase credentials ;
* API keys ;
* service account ;
* Firebase project ID ;
* Brevo secrets ;
* production URLs.

---

# 11. SUPABASE LOCAL UNIQUEMENT

Cette phase doit être locale.

Autorisé :

```text
supabase init
supabase start
supabase db reset
supabase test db
```

ou équivalents locaux appropriés.

Interdit :

```text
supabase link
supabase db push
supabase functions deploy
supabase secrets set
```

vers un projet distant.

Aucun projet Supabase production ou staging distant ne doit être modifié.

---

# 12. MIGRATIONS PAR DOMAINES

Ne créer PAS un fichier SQL géant.

Organiser les migrations par dépendances.

Exemple logique :

```text
001_extensions_and_schemas
002_identity_and_platform
003_academy_access
004_sport_core
005_packages_and_ledger
006_sessions_and_bookings
007_finance_and_subscriptions
008_notifications_and_audit
009_assets_and_internal_support
010_constraints_and_exclusions
011_indexes
012_rbac_seed
013_rls_deny_by_default
```

Si Supabase CLI utilise des timestamps :

utiliser les noms générés par la CLI.

Les numéros ci-dessus décrivent l'ordre logique, pas obligatoirement le filename physique.

---

# 13. SCHEMAS

Utiliser au minimum :

```text
public
private
```

selon le design approuvé.

Les objets purement internes ne doivent pas être exposés directement au client.

Ne pas utiliser le schéma `public` comme synonyme de données publiques.

---

# 14. EXTENSIONS

N'activer que les extensions nécessaires.

Évaluer notamment :

```text
pgcrypto
btree_gist
```

pour :

* UUID ;
* exclusions GiST terrain ;
* exclusions GiST coach.

Pas d'extensions « au cas où ».

---

# 15. AUTH

Utiliser :

```text
auth.users
```

comme identité globale.

Ne créer aucune table applicative :

```text
users
```

concurrente.

Créer :

```text
user_profiles
```

avec :

```text
user_profiles.id → auth.users.id
```

Ne pas stocker :

* password ;
* password hash ;
* Firebase UID ;
* email comme deuxième source Auth autoritaire.

---

# 16. MULTI-TENANCY

Toutes les tables métier tenant doivent utiliser :

```text
academy_id NOT NULL
```

lorsque défini par le design.

Utiliser les uniques nécessaires :

```text
UNIQUE(academy_id,id)
```

pour les FK tenant-aware.

Aucune ressource de Academy A ne doit pouvoir référencer une ressource Academy B.

La DB doit protéger cette règle indépendamment des futures RPC.

---

# 17. PLAYER LINKS

Supporter :

* plusieurs GUARDIAN ;
* un SELF actif maximum ;
* un primary actif maximum ;
* un financial contact actif maximum.

Créer les uniques partiels validés.

Ne jamais recréer :

```text
one guardian per player
```

comme règle globale.

---

# 18. SERVICE OFFERS

Créer :

```text
service_offers
```

Pas :

```text
sessionConfigurations
```

dans le nouveau domaine.

`price_basis` :

```text
PACKAGE
SESSION
```

obligatoire.

Autoriser :

* plusieurs offres de même durée ;
* overlap de tranche d'âge ;
* offres similaires.

Une seule version PUBLISHED par :

```text
academy_id + offer_key
```

---

# 19. PACKAGES & LEDGER

Créer :

```text
player_packages
course_ledger
```

`course_ledger` :

append-only.

`remaining_sessions` :

cache transactionnel serveur.

Ne pas créer :

```text
credit_holds
reserved_sessions
available_sessions
```

comme colonnes autoritaires.

---

# 20. BOOKING CREDIT MODEL

Conserver :

```text
R = remaining_sessions
H = confirmed_unconsumed_bookings
A = R-H
```

avec :

```text
R >= 0
H <= R
A >= 0
```

Le DDL doit créer les index nécessaires au calcul futur de H.

La logique transactionnelle elle-même sera implémentée en Phase 3C.

Ne pas créer de trigger complexe pour simuler les futures RPC.

---

# 21. COURTS

Matérialiser :

```text
stadiums
courts
```

Court réel avec UUID.

Pas d'ID métier concaténé.

Créer exclusion :

```text
academy_id
court_id
tstzrange(starts_at,ends_at,'[)')
```

sur :

```text
OPEN
CLOSED
```

CANCELLED ne bloque pas.

Créneaux adjacents autorisés.

---

# 22. COACH CONFLICT

Créer exclusion locale academy :

```text
academy_id
coach_id
tstzrange(starts_at,ends_at,'[)')
```

sur :

```text
OPEN
CLOSED
```

Pas de conflit global par user Auth.

La même personne peut théoriquement être coach dans deux academies simultanément en V1.

---

# 23. BOOKINGS

Unique actif :

```text
session_id + player_id
```

uniquement :

```text
PENDING
CONFIRMED
```

CANCELLED/REJECTED permettent une nouvelle ligne UUID.

COMPLETED reste historique.

`deleted_at` ne doit pas contourner l'unique actif.

---

# 24. MONEY

Utiliser :

```text
numeric(18,2)
```

Jamais float.

Devises V1 :

```text
AED
XAF
EUR
USD
MAD
```

XAF :

pas de fraction.

Autres :

≤ 2 décimales.

Aucune conversion FX.

---

# 25. FINANCE

Maintenir séparés :

```text
service_offer
player_package
booking
payment
invoice
```

Un booking n'est jamais une preuve de paiement.

Pas de :

* Stripe ;
* online payment ;
* refund ;
* payment provider ;

en Phase 3A.

---

# 26. SAAS

Créer seulement le socle manuel :

```text
platform_plans
academy_subscriptions
subscription_events
```

Pas de prix SaaS inventé.

Pas de quota commercial inventé.

Pas de billing provider.

---

# 27. RBAC

Rôles plateforme :

```text
SUPER_ADMIN
PLATFORM_ADMIN
```

Rôles academy :

```text
ACADEMY_OWNER
ACADEMY_ADMIN
MANAGER
STAFF
COACH
STUDENT
PARENT
```

Pas de :

```text
SUPPORT
BILLING_ADMIN
```

V1.

Pas de custom role.

Pas de permission directement attachée à un utilisateur.

Pas de grant individuel libre.

Seeder :

```text
permissions
platform_roles
platform_role_permissions
academy_roles
academy_role_permissions
```

selon V1.1.

---

# 28. OVERRIDES

Overrides existants :

```text
bookings.override.capacity
bookings.override.age
bookings.override.offer
bookings.override.quota
bookings.override.player_overlap
```

Interdits :

```text
tenant
FK
court conflict
coach conflict
negative remaining_sessions
session state/date
```

Quota override :

ne permet jamais CONFIRMED si A=0.

---

# 29. NOTIFICATIONS

Créer uniquement la structure DB nécessaire.

Pas encore Brevo.

Pas encore worker.

Pas encore Edge Function.

Conserver le modèle outbox/audit approuvé.

---

# 30. ASSETS

Créer :

```text
academy_assets
```

Pas encore de bucket.

Le futur Storage sera séparé et privé.

Ne pas créer de bucket lors de cette phase.

---

# 31. COMMAND RECEIPTS

Conserver :

```text
command_receipts
```

Ce n'est PAS une table legacy.

Elle servira à :

* idempotence ;
* retries ;
* prévention double effet ;
* futurs RPC.

---

# 32. AUDIT

Conserver :

```text
audit_log
```

Ce n'est PAS une table ChallengeMe.

Elle appartient au nouveau système.

---

# 33. NE PAS CRÉER LES TABLES LEGACY

Ne pas créer :

```text
legacy_identity_map
legacy_entity_map
migration_issues
```

sauf si l'inspection découvre une dépendance indispensable au nouveau produit.

Si une dépendance est découverte :

ne pas la recréer silencieusement.

Documenter :

```text
GREENFIELD_DEPENDENCY_CONFLICT
```

et expliquer.

---

# 34. RLS PHASE 3A

Activer RLS sur toutes les tables des schemas exposés.

Mais Phase 3A est :

```text
DENY BY DEFAULT
```

Ne pas encore construire toute la matrice.

Aucune policy temporaire :

```sql
USING (true)
```

Aucun accès anon aux données métier.

Les tables `private` ne sont pas exposées aux clients.

---

# 35. TESTS PHASE 3A

Créer et exécuter localement les tests structurels.

Tester notamment :

### Greenfield

* aucune table legacy migration ;
* aucune dépendance runtime ChallengeMe ;
* aucun Firebase UID dans modèle opérationnel.

### Multi-tenancy

* Academy A → ressource B refusé ;
* player/package cross-tenant refusé ;
* court/session cross-tenant refusé.

### Guardians

* plusieurs guardians différents acceptés ;
* deux primary actifs refusés ;
* deux financial contacts actifs refusés.

### Offers

* deux mêmes durées acceptées ;
* âge overlap accepté ;
* une seule version published academy/offer_key.

### Sessions

* collision court refusée ;
* créneau adjacent accepté ;
* CLOSED continue bloquer court ;
* CANCELLED ne bloque pas ;
* collision coach local refusée.

### Bookings

* PENDING + PENDING même player/session refusé ;
* PENDING + CONFIRMED refusé ;
* après CANCELLED nouvelle ligne autorisée ;
* après REJECTED nouvelle ligne autorisée.

### Money

* XAF fraction refusée ;
* XAF entier accepté ;
* EUR/USD/AED/MAD avec deux décimales accepté.

### RBAC

* STAFF n'a pas finance ;
* MANAGER n'a pas membership administration ;
* COACH n'a pas finance ;
* Parent/Student n'ont pas opérations staff.

### RLS

* activé sur toutes les tables exposées ;
* aucun accès anon métier.

---

# 36. LOCAL VALIDATION

Si Supabase local fonctionne :

exécuter les migrations localement.

Puis :

```text
supabase db reset
supabase test db
```

ou commandes locales compatibles.

Si le runtime n'est pas disponible :

NE PAS utiliser un projet distant.

Rapporter :

```text
LOCAL_RUNTIME_NOT_AVAILABLE
```

---

# 37. RAPPORT PHASE 3A

Créer :

```text
PHASE_3A_DATABASE_IMPLEMENTATION_REPORT.md
```

Sections obligatoires :

## 1. Greenfield Boundary Verification

## 2. ChallengeMeAcademy Integrity Verification

## 3. Final Table Count

## 4. Tables Removed From V1.1

## 5. Files Created

## 6. Migrations Created

## 7. Schemas

## 8. Extensions

## 9. Tables

## 10. Tenant-aware Foreign Keys

## 11. Constraints

## 12. Exclusion Constraints

## 13. Indexes

## 14. RBAC Seeds

## 15. RLS Deny-by-default

## 16. Tests Created

## 17. Tests Executed

## 18. Test Results

## 19. Design Deviations

## 20. Problems Found

## 21. Remaining Product Decisions

## 22. Git Diff — Sport Connect Academy Only

## 23. Confirmation No ChallengeMeAcademy File Was Modified

---

# 38. DIFF SAFETY CHECK

Avant de terminer :

vérifier explicitement le Git diff.

Le rapport doit identifier :

```text
FILES MODIFIED IN SPORT CONNECT ACADEMY
```

et :

```text
FILES MODIFIED IN CHALLENGEMEACADEMY
```

Le second résultat doit être :

```text
NONE
```

Si un fichier ChallengeMeAcademy a été modifié accidentellement :

ne pas continuer.

Restaurer uniquement la modification accidentelle générée pendant cette mission, sans écraser une modification utilisateur existante.

Puis documenter l'incident.

---

# ============================================================

# ROADMAP APRÈS PHASE 3A — NE PAS EXÉCUTER MAINTENANT

# ============================================================

# PHASE 3B — RLS SECURITY

Après revue humaine 3A uniquement.

Objectif :

implémenter les vraies policies :

```text
Platform Admin
Owner
Academy Admin
Manager
Staff
Coach
Student
Parent
```

Tester :

* Academy A/B ;
* membership suspended ;
* player links ;
* coach assignment ;
* role revocation ;
* forged UUID ;
* finance isolation ;
* platform vs tenant.

STOP après 3B pour revue humaine.

---

# PHASE 3C — BUSINESS RPC

Après approbation 3B.

Implémenter les RPC atomiques :

```text
request_booking
schedule_booking
approve_booking
reject_booking
cancel_booking
record_attendance
complete_booking
archive_booking
```

Puis :

```text
player/package/ledger
payments/invoices
membership/roles
academy/subscription
resources
evaluations
```

Implémenter :

* auth.uid() ;
* permissions ;
* locks ;
* expected_revision ;
* operation_key ;
* command_receipts ;
* audit ;
* outbox ;
* rollback atomique.

Tests concurrence obligatoires :

* dernier crédit ;
* dernière place ;
* double approval ;
* cancel vs attendance ;
* retry ;
* double compensation ;
* same court ;
* same coach.

STOP après 3C.

---

# PHASE 3D — AUTH / STORAGE / EDGE

Après validation RPC.

## Auth

Créer les vrais parcours Sport Connect :

* signup/invite ;
* login ;
* reset password ;
* membership invitation ;
* owner onboarding.

Aucun compte ChallengeMe importé.

## Storage

Créer :

```text
academy-private-assets
```

pour :

* academy branding ;
* tournament covers.

URLs signées.

## Edge

Seulement :

* Auth Admin ;
* invitations ;
* upload sécurisé ;
* Brevo ;
* webhook ;
* workers ;
* reminders.

Pas de business transaction booking dans Edge.

STOP après 3D.

---

# PHASE 4A — WEB BACK OFFICE

Construire le nouveau back office Sport Connect Academy.

Priorité :

1. Platform Admin login
2. Create academy
3. Academy Owner invitation
4. Academy dashboard
5. Memberships
6. Coaches
7. Players
8. Stadiums
9. Courts
10. Offers
11. Packages
12. Sessions
13. Bookings
14. Attendance
15. Evaluations
16. Finance
17. Tournaments
18. Notifications/audit

ChallengeMe UI peut être consulté comme référence.

Ne jamais modifier le projet ChallengeMe.

Tout code réutilisé doit être copié dans Sport Connect Academy puis modifié uniquement dans le nouveau projet.

Aucun import de secrets/configuration Firebase.

STOP après MVP Back Office.

---

# PHASE 4B — FLUTTER

Construire l'application Sport Connect Academy.

Parcours :

```text
Authentication
Academy context
Player profile
Packages
Sessions
Bookings
Booking history
Attendance
Evaluations
Parent/guardian
Coach planning
Coach attendance
```

Flutter ne contient jamais l'autorité métier.

Flutter :

```text
DISPLAY
INPUT
LOCAL UX STATE
```

PostgreSQL/RPC :

```text
AUTHORIZATION
BUSINESS RULES
TRANSACTIONS
CREDITS
CAPACITY
FINANCE
```

STOP après MVP Flutter.

---

# PHASE 5 — INTEGRATION & QA

Tester le parcours complet avec nouvelles données fictives Sport Connect :

```text
Platform Admin
   ↓
Academy
   ↓
Owner
   ↓
Coach
   ↓
Player
   ↓
Offer
   ↓
Package
   ↓
Session
   ↓
Booking
   ↓
Attendance
   ↓
Ledger
   ↓
Invoice/Payment
```

Tester :

* sécurité ;
* concurrence ;
* emails ;
* Storage ;
* timezone ;
* langues ;
* erreur réseau ;
* retry ;
* audit ;
* Realtime ;
* navigation Flutter/Web.

Aucune donnée ChallengeMe utilisée.

---

# PHASE 6 — STAGING

Créer un environnement Sport Connect Academy staging indépendant.

Tester uniquement avec comptes/données Sport Connect.

Ne pas connecter staging à Firebase ChallengeMe.

---

# PHASE 7 — PRODUCTION

Seulement après validation humaine finale :

* Supabase production indépendant ;
* secrets production ;
* backups ;
* monitoring ;
* domains ;
* builds Web/Flutter ;
* observabilité ;
* runbooks.

ChallengeMeAcademy continue à fonctionner séparément.

---

# STOP CONDITION DE CETTE MISSION

Pour cette mission, exécuter uniquement :

```text
1. GREENFIELD FINALIZATION
2. PHASE 3A DATABASE FOUNDATION
3. LOCAL TESTS
4. PHASE 3A REPORT
```

Puis :

```text
STOP
```

Ne pas commencer Phase 3B automatiquement.

Terminer le rapport par :

```text
STATUS: PHASE 3A READY FOR HUMAN REVIEW

PROJECT: SPORT CONNECT ACADEMY
PROJECT TYPE: GREENFIELD

GREENFIELD DESIGN FINALIZED: YES/NO

EXPECTED TABLE COUNT: <number>
ACTUAL TABLE COUNT: <number>

LEGACY CHALLENGEME MIGRATION TABLES CREATED: NO
CHALLENGEME FILES MODIFIED: NO
CHALLENGEME FIREBASE MODIFIED: NO
CHALLENGEME DATA MODIFIED: NO

LOCAL MIGRATIONS CREATED: YES/NO
LOCAL MIGRATIONS APPLIED: YES/NO

LOCAL TESTS EXECUTED: YES/NO
LOCAL TESTS PASSED: <x>/<y>

REMOTE SUPABASE MODIFIED: NO
PRODUCTION DATA MODIFIED: NO

DESIGN DEVIATIONS: <number>
BLOCKING IMPLEMENTATION ISSUES: <number>

NEXT AUTHORIZED PHASE: NONE — HUMAN REVIEW REQUIRED
```
Poursuivre ou ca c'est arreter
