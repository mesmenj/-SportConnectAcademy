# Sport Connect Academy — fondation locale

Phases **3A à 3D**, implémentées le 26 septembre 2026 : 41 tables, 24 migrations,
contraintes, RBAC, lectures autorisées (3B), 59 RPC de commande (3C), puis Auth,
invitations, assets privés et workers de notification (3D, fonctions Edge dans
`functions/`). Aucune écriture client directe sur les tables. 3D n'a pas encore
tourné sur une pile Supabase complète.

Contrat : [Greenfield final](../docs/database/SPORT_CONNECT_DATABASE_GREENFIELD_FINAL.md).
Résultats : [rapport 3A](../docs/PHASE_3A_DATABASE_IMPLEMENTATION_REPORT.md),
[rapport 3B](../docs/PHASE_3B_RLS_SECURITY_REPORT.md),
[rapport 3C](../docs/PHASE_3C_BUSINESS_RPC_REPORT.md),
[rapport 3D](../docs/PHASE_3D_AUTH_STORAGE_EDGE_REPORT.md).
Reprise globale : [état de l'implémentation](../docs/IMPLEMENTATION_STATUS.md).

## Test local sans Docker

Prérequis : Node.js et PostgreSQL 17 avec `btree_gist` installé.

```bash
npm run test:database
# Si PostgreSQL n'est pas dans PATH ou au chemin Homebrew Intel détecté :
SPORTA_PG_BIN=/chemin/postgresql/bin npm run test:database
```

Le script initialise **un nouveau cluster temporaire**, écoute seulement sur son
socket Unix unique, applique toutes les migrations et exécute les deux suites SQL.
Il arrête le serveur à la fin et conserve les fichiers/logs temporaires pour
diagnostic. Aucune base existante n'est réinitialisée. Il n'accepte aucun argument
de connexion, URL ou projet distant et n'utilise pas les variables PG de la session.

Résultat vérifié : **427/427 assertions et 12/12 courses à deux connexions sur
PostgreSQL 17.9**. Les courses utilisent une base jetable `conc` du même cluster. Les données de test
sont synthétiques, les transactions de test sont annulées. Les rôles `anon` et
`authenticated` sont réellement utilisés pour vérifier les refus d'accès.

`local/auth-test-bootstrap.sql` est un substitut minimal d'Auth (`auth.users.id`)
réservé à ce cluster jetable. Il ne valide ni le login Supabase, ni les JWT, ni
PostgREST, Realtime, Storage ou Edge. Ne pas le déployer.

## Supabase local complet

La CLI Supabase et Docker n'étaient pas disponibles dans l'environnement de reprise.
`config.toml` prépare le projet local avec PostgreSQL 17, seul `public` exposé,
signup désactivé et Storage désactivé en 3A. Sa compatibilité CLI n'a pas encore
été vérifiée par un démarrage effectif.

Une fois la CLI et son runtime installés, depuis **ce workspace indépendant** :

```bash
supabase start
supabase db reset --local
supabase test db
```

Ces commandes réinitialisent la base Supabase locale du projet ; ne les utiliser
que pour des données locales jetables. Les tests produisent du TAP et incluent
leurs fixtures via `support/`, sans dépendance pgTAP.

Aucune commande `link`, `db push`, `functions deploy` ou `secrets set` n'est
nécessaire à cette phase. Aucun seed utilisateur, compte admin ou tarif commercial.

## Organisation

- `migrations/` : 001 schémas/extensions ; 002 identité ; 003 accès ; 004 sport ;
  005 offres/packages/ledger ; 006 séances/bookings ; 007 finance/SaaS ;
  008 notifications/audit ; 009 reçus/assets ; 010 FK/exclusions ; 011 index ;
  012 catalogue RBAC ; 013 triggers structurels/RLS ; 014 helpers d'autorisation ;
  015 policies SELECT et colonnes accordées ; 016 projections de lecture ;
  017 infrastructure de commande ; 018 moteur de réservation ; 019 joueurs,
  forfaits et finance ; 020 accès, catalogue, séances et évaluations.
- `tests/database/001_foundation.sql` : 78 assertions, intégrité métier et RLS.
- `tests/database/002_history_scope_finance.sql` : 45 assertions, scopes, historique,
  reçus, finance et métadonnées assets.
- `tests/database/003_authorization_reads.sql` : 92 assertions 3B, lectures sous le
  rôle `authenticated` par acteur, A/B, révocations, UUID forgés, finance, plateforme.
- `tests/database/004_business_rpc.sql` : 142 assertions 3C (D30/D34, idempotence,
  overrides, présence, finance, rôles, plateforme, atomicité).
- `tests/concurrency/` : données validées par commit et 8 courses orchestrées par
  `scripts/test-database.mjs`.
- `functions/` : dossiers existants vides ; aucune fonction Edge implémentée.

## Limites intentionnelles de 3A

Les contraintes ne remplacent pas les RPC : R/H/A, autorisation, cohérence du solde
avec le ledger, compteur de places, immutabilité contractuelle après publication,
validation de précision avant cast, transitions et idempotence fonctionnelle
sont portés par les RPC 3C et testés dans `004` et les courses. Les tests insèrent certaines fixtures avec
le rôle propriétaire pour isoler le DDL ; ce n'est pas un parcours client autorisé.

Les clients lisent via 3B et écrivent uniquement via les RPC 3C. Ne jamais ajouter
de policy d'écriture ni de policy temporaire permissive pour un ancien écran.

Références techniques : [contraintes PostgreSQL 17](https://www.postgresql.org/docs/17/ddl-constraints.html)
et [RLS Supabase](https://supabase.com/docs/guides/database/postgres/row-level-security).
