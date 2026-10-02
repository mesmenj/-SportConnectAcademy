# Sport Connect Academy — reprise du workspace SportA

## Lire avant de poursuivre

1. `docs/IMPLEMENTATION_STATUS.md` : état observé et écarts des interfaces.
2. `docs/database/SPORT_CONNECT_DATABASE_GREENFIELD_FINAL.md` : contrat normatif.
3. `docs/PHASE_3A_DATABASE_IMPLEMENTATION_REPORT.md`,
   `docs/PHASE_3B_RLS_SECURITY_REPORT.md`,
   `docs/PHASE_3C_BUSINESS_RPC_REPORT.md` et
   `docs/PHASE_3D_AUTH_STORAGE_EDGE_REPORT.md` : réalisation et tests 3A–3D.
4. `supabase/README.md` : commandes locales et limites du banc PostgreSQL.
5. `docs/IMPLEMENTATION_ROADMAP.md` : roadmap humaine conservée.

Priorité : instructions humaines récentes, contrat greenfield final, V1.1, V1,
puis ancien code utilisé comme référence. Les anciens documents de design sont
des copies inchangées ; leurs réserves D34 sont remplacées par la décision finale.

## Frontières

Ce workspace est la cible indépendante. Les repositories ChallengeMeAcademy
(`classcard-admin`, `classcard-functions`, `classcard_student`, etc.) restent en
lecture seule. Aucun import de comptes, données, secrets ou configurations.
Firebase et production restent sans écriture. Le 2 octobre 2026, l’utilisateur
a autorisé la création et les écritures Supabase distantes pour le staging
uniquement, sur l’offre gratuite. Production protégée : `phjzyohsscwrgwvhgvfh`.
Aucun import de secrets ou de données de production. Hébergement/domaines et
e-mail sont reportés ; nettoyage désactivé tant que D28 n’est pas validée.

Les modes Firebase existants et les aperçus UI ne prouvent pas une intégration
Supabase. Aucun rapport 3D n'était présent lors de la reprise du 26 septembre 2026.
Ne pas annoncer 3B/3C/3D comme terminées sans leurs migrations/tests réels.

## État et prochain travail

Phase 3A implémentée : 41 tables, 13 migrations, RBAC fixe, contraintes et RLS.
Phase 3B implémentée (migrations 014–016) : lectures seules, policies SELECT,
colonnes accordées, 19 projections, droits recalculés à chaque requête.
Phase 3C implémentée (migrations 017–020) : 59 RPC atomiques, reçus idempotents,
audit/outbox, D34 = PENDING, refus explicites D05/D29.
Phase 3D clôturée localement le 29 septembre 2026 (migrations 021–025, 8 fonctions Edge, client
Auth) : invitations et renvoi, assets privés décodés, workers de notification.
Validation locale : 427 assertions SQL, 12 courses à deux connexions, 24 tests
Edge (Node et Deno), contrôle de types. Pile Supabase complète validée localement :
25 migrations, 427 assertions SQL et parcours Auth/PostgREST/Storage/Edge réel.
Voir le rapport 3D pour les preuves et limites (Brevo externe et rétention D28).
Phase 4A MVP Web implémentée le 29 septembre : deux entrées Supabase connectées,
62 commandes raccordées, Auth et contexte académie, aucune mutation directe.
Validation : builds des deux applications, lint du nouveau code, 8 tests client,
16 tests historiques, parcours Chromium sur Supabase local (D34, révision périmée,
rejeu après réponse perdue, isolation et réponse tardive lors du changement tenant).
Voir `docs/PHASE_4A_WEB_IMPLEMENTATION_REPORT.md` pour le périmètre et les limites.
Phase 4B Flutter implémentée le 29 septembre (`apps/student/lib/connect/`) :
Auth Supabase, contexte académie, parent/coach, 7 commandes, rejeu idempotent.
Validation : analyse, 12 tests Flutter, parcours widgets + HTTP réel sur Supabase
local (`test:flutter:local`) et contrôle Chromium du build (`test:flutter:browser`).
Web uniquement : aucune exécution Android/iOS. Voir
`docs/PHASE_4B_FLUTTER_IMPLEMENTATION_REPORT.md`.
Dans un `testWidgets` à HTTP réel, fermer le client dans le corps du test :
les minuteurs keep-alive sont vérifiés avant les `tearDown`.
Phase 5 QA locale réalisée le 29 septembre : `test:qa:local` et matrice complète.
Correctifs : sessions Web (connexion tardive, 401 périmé), mutation liée à son
auteur (`actor`, Web et Flutter), intention Flutter conservée sur `AUTH_REQUIRED`,
outil `invitation:link` (identité = `auth.users` par email, pas `invited_user_id`).
Ouvert : Realtime, Brevo, Android/iOS, interfaces FR seules, charge.
Voir `docs/PHASE_5_QA_INTEGRATION_REPORT.md`.
Phase 6 (2 octobre) : écritures distantes autorisées pour un nouveau staging
seulement, offre gratuite, production `phjzyohsscwrgwvhgvfh` exclue.
Staging distant `ordjngzihkmknnizlujp` (eu-west-3) créé et déployé (backend seul) :
26 migrations, 461 assertions SQL distantes en transactions annulées, 8 fonctions
Edge contrôlées par HTTP (`scripts/test-staging-{database,api,media}.mjs <ref>`),
Vault prêt, 0 cron, 0 worker actif, aucune donnée conservée. Workspace non lié ;
secrets dans `supabase/.temp/staging-deploy/` (ignoré). `secure-asset-upload`
exige son propre `deno.json` (imports npm) pour démarrer sur l’hébergé.
Domaines et e-mails reportés par l’utilisateur.
Mode `staging:preflight --backend-only` préparé et testé : origines/callbacks/
redirections vides, Brevo désactivé, refus de la production. Migration 026
(planificateur ops, pg_cron/pg_net/Vault) présente et validée : 443 assertions SQL
et 12 courses sur PostgreSQL jetable ; 34 assertions de planification sur
Supabase local en transaction annulée. Tous les workers sont installés désactivés ;
le nettoyage nécessite une rétention explicite. Voir le runbook phase 6.
Ne pas confondre validation locale de la migration et déploiement distant.

## Invariants à conserver

- Toutes relations métier protègent `academy_id` par FK composite.
- D34 : R ≥ 0, H ≤ R, A = R − H ≥ 0 ; quota override sans crédit → PENDING.
- Pas de `credit_holds`, `hold_exempt`, crédit fictif ou confirmation sans package.
- Plusieurs GUARDIAN possibles ; SELF/principal/contact financier actifs uniques.
- Les règles de crédit, finance, capacité et permissions appartiennent aux RPC.
- Les clients ne reçoivent jamais de clé service_role ou de mutations directes.
- Finance en numeric(18,2), XAF entier ; valider la précision avant cast dans 3C.
- Aucun prix ou quota SaaS inventé, aucun paiement en ligne en V1.

## Vérification et changements préexistants

`npm run test:database` crée un cluster PostgreSQL jetable sans URL distante.
Il utilise un substitut minimal `auth.users`, exclusivement pour les tests DDL.
Il ajoute un cluster `conc` pour les courses (`supabase/tests/concurrency/`).
Ne jamais déplacer `supabase/local/auth-test-bootstrap.sql` dans les migrations.
Dans une assertion SQL, ne pas appeler une RPC et relire son effet dans la même
instruction (instantané commun) : `pg_temp.exec` puis `pg_temp.last()`.
Deux colonnes qui doivent être égales (bail) : un seul `clock_timestamp()`.
Les triggers différés s'exécutent après le retour de la RPC : tester aussi les
contraintes sous le rôle client. `check_parent_scope` est SECURITY DEFINER (025),
sans droit client supplémentaire sur `private`.
Sur Supabase jetable vierge : `npm run test:supabase:db`, puis le parcours
`npm run test:supabase:local`. Ne pas lancer `supabase test db` sans sélection :
il traite les fixtures et la préparation des courses comme des tests autonomes.
Les suites SQL supposent une base sans les données du parcours intégré.

Au début de la reprise, quatre fichiers Platform Admin étaient déjà supprimés
(`.env.example`, `.env.sporta`, `eslint.config.js`, `index.html`) et son `.gitignore`
était non suivi. Ne pas restaurer ces modifications sans comprendre leur contexte.
