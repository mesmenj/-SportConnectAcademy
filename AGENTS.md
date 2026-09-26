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
Aucun déploiement ou écriture Firebase/Supabase distant dans cette reprise locale.

Les modes Firebase existants et les aperçus UI ne prouvent pas une intégration
Supabase. Aucun rapport 3D n'était présent lors de la reprise du 26 septembre 2026.
Ne pas annoncer 3B/3C/3D comme terminées sans leurs migrations/tests réels.

## État et prochain travail

Phase 3A implémentée : 41 tables, 13 migrations, RBAC fixe, contraintes et RLS.
Phase 3B implémentée (migrations 014–016) : lectures seules, policies SELECT,
colonnes accordées, 19 projections, droits recalculés à chaque requête.
Phase 3C implémentée (migrations 017–020) : 59 RPC atomiques, reçus idempotents,
audit/outbox, D34 = PENDING, refus explicites D05/D29.
Phase 3D implémentée localement (migrations 021–024, 8 fonctions Edge, client
Auth) : invitations et renvoi, assets privés décodés, workers de notification.
Validation locale : 427 assertions SQL, 12 courses à deux connexions, 24 tests
Edge (Node et Deno), contrôle de types. **Pile Supabase complète jamais exécutée**
(Docker absent) : `npm run test:supabase:local` reste à lancer avant de clore 3D.

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

Au début de la reprise, quatre fichiers Platform Admin étaient déjà supprimés
(`.env.example`, `.env.sporta`, `eslint.config.js`, `index.html`) et son `.gitignore`
était non suivi. Ne pas restaurer ces modifications sans comprendre leur contexte.
