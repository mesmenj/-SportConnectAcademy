# Sport Connect Academy — fondation locale

Phases **3A à 3D**, implémentées le 26 septembre 2026 : 41 tables, 25 migrations,
contraintes, RBAC, lectures autorisées (3B), 59 RPC de commande (3C), puis Auth,
invitations, assets privés et workers de notification (3D, fonctions Edge dans
`functions/`). Aucune écriture client directe sur les tables. 3D est clôturée localement le 29 septembre 2026 après validation sur la pile
Supabase complète. Aucun environnement distant modifié.

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
socket Unix unique, applique toutes les migrations et exécute les cinq suites SQL.
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

Validation exécutée le 29 septembre 2026 : CLI Supabase **2.118.0**, PostgreSQL
Supabase **17.6**, Edge Runtime **1.76.2**. Auth, PostgREST, Storage et Edge ont été
exécutés ensemble. `config.toml` expose uniquement `public`, active le stockage
privé et interdit l'inscription publique.

Attention : dans cette CLI, `auth.email.enable_signup = true` active le fournisseur
email (donc la connexion). L'interdiction globale reste portée par
`auth.enable_signup = false` ; le test intégré vérifie le refus HTTP `signup_disabled`.
Voir le [signalement amont](https://github.com/supabase/supabase/issues/40582).
La configuration SMTP locale utilise désormais `[local_smtp]`.

Depuis ce workspace, sur une **pile locale jetable** :

```bash
supabase start
supabase db reset --local
npm run test:supabase:db
```

Le reset efface les données locales du projet. Les cinq suites SQL supposent une
base applicative vierge ; les exécuter **avant** le parcours intégré, qui conserve
ses données synthétiques. Ne pas lancer `supabase test db` sans sélection : la CLI
parcourt aussi `support/` et `concurrency/setup.sql`, qui ne sont pas des suites TAP
et peuvent insérer des fixtures hors des transactions de test.

Pour les fonctions, copier `supabase/functions/.env.example` vers un fichier local
ignoré, renseigner trois secrets aléatoires indépendants (au moins 32 caractères)
et conserver les valeurs localhost. Laisser Brevo vide pour empêcher tout envoi
externe. Dans un terminal séparé :

```bash
supabase functions serve --env-file supabase/functions/.env
```

Dans le terminal de test, fournir `SPORTA_LOCAL_ANON_KEY` et
`SPORTA_LOCAL_SERVICE_KEY` issus exclusivement de `supabase status -o json`, ainsi
que le même `WORKER_SECRET` que celui du fichier Edge. Ne jamais committer ces
valeurs. Puis :

```bash
npm run test:supabase:local
```

Le script n'accepte que HTTP sur loopback, port 54321 ; SQL utilise localhost:54322.
Il crée des comptes `example.test` synthétiques et vérifie : inscription publique
refusée, invitation/acceptation, login/refresh/recovery/logout, refus PostgREST,
upload PNG/JPEG/WebP et rejeu, téléchargement signé, refus Storage direct,
protection des huit endpoints Edge et exécution de workers locaux. La récupération
de mot de passe utilise SMTP local ; aucun email Brevo externe n'est envoyé.
Le test exige Brevo non configuré et aucune invitation antérieure à provisionner.
`SPORTA_PG_BIN` permet de préciser le répertoire contenant `psql`.

Parcours QA de phase 5 (mêmes variables) : `npm run test:qa:local`.

Pour activer à la main un compte invité depuis l'interface Web, sans recopier de
jeton : `npm run invitation:link -- <UUID de l'invitation>`. L'outil provisionne
l'invitation si nécessaire, génère un jeton Auth frais et écrit un fichier
`activation.html` privé (0600) dans un dossier temporaire. Aucun email n'est
envoyé et le jeton n'est pas consommé. Ne pas partager ce fichier.

Aucune commande `link`, `db push`, `functions deploy` ou `secrets set` n'est requise.
Les décisions D28 et fournisseur email restent à valider avant environnement
partagé. La clôture locale ne valide ni la délivrabilité Brevo, ni la charge,
Realtime ou les interfaces 4A/4B.

## Organisation

- `migrations/` : 001 schémas/extensions ; 002 identité ; 003 accès ; 004 sport ;
  005 offres/packages/ledger ; 006 séances/bookings ; 007 finance/SaaS ;
  008 notifications/audit ; 009 reçus/assets ; 010 FK/exclusions ; 011 index ;
  012 catalogue RBAC ; 013 triggers structurels/RLS ; 014 helpers d'autorisation ;
  015 policies SELECT et colonnes accordées ; 016 projections de lecture ;
  017 infrastructure de commande ; 018 moteur de réservation ; 019 joueurs,
  forfaits et finance ; 020 accès, catalogue, séances et évaluations ; 021 Auth/invitations ;
  022 assets privés ; 023 notifications ; 024 renvoi ; 025 autorité du trigger
  différé de contrôle des scopes après retour de la RPC.
- `tests/database/001_foundation.sql` : 78 assertions, intégrité métier et RLS.
- `tests/database/002_history_scope_finance.sql` : 45 assertions, scopes, historique,
  reçus, finance et métadonnées assets.
- `tests/database/003_authorization_reads.sql` : 92 assertions 3B, lectures sous le
  rôle `authenticated` par acteur, A/B, révocations, UUID forgés, finance, plateforme.
- `tests/database/004_business_rpc.sql` : 142 assertions 3C (D30/D34, idempotence,
  overrides, présence, finance, rôles, plateforme, atomicité).
- `tests/database/005_auth_storage_workers.sql` : 70 assertions 3D, contraintes
  différées vérifiées sous le rôle client.
- `tests/concurrency/` : données validées par commit et 12 courses orchestrées par
  `scripts/test-database.mjs`.
- `functions/` : huit fonctions Edge et modules partagés ; 24 tests Node/Deno.
- `auth/client.mjs` : transport Auth destiné aux futures interfaces.
- `../scripts/test-supabase-local.mjs` : parcours intégré sur les services réels.

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
