# Phase 6 — Staging : préparation et runbook

29 septembre 2026. Autorisation humaine : « Passez à la phase 6 ».
Objectif de la roadmap : un environnement Sport Connect Academy staging
**indépendant**, testé uniquement avec des comptes et données Sport Connect,
jamais connecté à Firebase ChallengeMe.

## État au 2 octobre 2026

**Backend staging déployé et vérifié sur `ordjngzihkmknnizlujp`
(`sport-connect-academy-staging`, eu-west-3, offre gratuite, créé le
1er octobre 2026 20:40 UTC). Production `phjzyohsscwrgwvhgvfh` non touchée.**

L’utilisateur a fourni son projet de **production** `phjzyohsscwrgwvhgvfh` et
explicitement autorisé les écritures pour un **nouveau staging seulement**, sur
l’offre gratuite. Cette instruction remplace l’interdiction distante précédente
pour ce seul environnement. Production et Firebase restent sans écriture.

Le workspace principal n’est pas lié (`supabase link` absent) : le déploiement
utilise un espace isolé et ignoré par git, `supabase/.temp/staging-deploy/`
(mot de passe base, `edge.env`, preuves TAP/JSON). Ne jamais committer ce dossier.

Preuves observées le 2 octobre :

- 26 migrations distantes, dernière `20260929002600` (= local) ;
- `node scripts/test-staging-database.mjs ordjngzihkmknnizlujp` : 461 assertions
  SQL (6 suites, 0 échec), en transactions annulées ; aucune donnée conservée
  (0 `auth.users`, 0 académie après coup) ;
- planificateur : secrets Vault configurés, 0 `cron.job`, 0 worker activé,
  0 rétention (D28) ;
- `node scripts/test-staging-api.mjs ordjngzihkmknnizlujp` : Auth disponible,
  inscription désactivée, confirmation e-mail exigée, lectures anonymes refusées,
  schémas `private/ops/net/vault/cron` non exposés, 8 fonctions Edge démarrées
  et fermées aux requêtes non autorisées, CORS frontend refusé, workers
  invitation/e-mail fermés avant toute réclamation ;
- `node scripts/test-staging-media.mjs ordjngzihkmknnizlujp` : compte Auth jetable
  (connexion + rafraîchissement), décodage hébergé PNG/JPEG/WebP (WASM), image
  corrompue refusée (400), acteur sans adhésion refusé (403) avant toute écriture ;
  compte supprimé.

Incident corrigé : `secure-asset-upload` échouait au démarrage sur le staging
(dépendances npm non résolues). Correctif : `secure-asset-upload/deno.json`
propre à la fonction (pngjs, jpeg-js, @jsquash/webp), redéploiement, puis contrôle
média ci-dessus réussi.

| Sujet | Décision / état |
|---|---|
| Écritures distantes | Autorisées pour staging uniquement ; référence production explicitement refusée par les contrôles |
| Compte/région/offre | Projet `ordjngzihkmknnizlujp`, eu-west-3, offre gratuite |
| Hébergement/domaines | Reportés par l’utilisateur ; ne bloquent pas la préparation du backend seul |
| Emails | Reportés ; Brevo et invitations automatiques restent désactivés |
| D28 | Durée demandée à l’utilisateur, pas encore fournie ; nettoyage automatique désactivé |
| Planification | Migration 026 déployée ; Vault configuré ; 0 cron, 0 worker activé |

### Mode backend seul (sans points 3 et 4)

Le contrôle accepte `--backend-only` avec une configuration dédiée :

```sh
npm run staging:preflight -- --backend-only --project-ref <staging-ref> \
  --env <fichier-secret-staging> --config <config-staging.toml>
```

- `PUBLIC_SUPABASE_URL=https://<staging-ref>.supabase.co` ;
- `ALLOWED_ORIGINS` et `INVITATION_CALLBACK_URL` vides ;
- `BREVO_API_KEY` et `BREVO_SENDER_EMAIL` vides ;
- trois nouveaux secrets indépendants et `ASSET_URL_TTL_SECONDS=120` ;
- `[remotes.staging]` identifie exclusivement le nouveau staging ;
- `auth.site_url` = l’origine API du staging comme valeur technique neutre,
  `additional_redirect_urls=[]`, inscription publique toujours désactivée ;
- aucun frontend, callback ni workflow email n’est annoncé fonctionnel ;
- les cinq workers restent désactivés à l’installation. La livraison et le
  provisionnement seront activés après configuration email/callback. Le nettoyage
  ne peut être activé sans rétention explicite.

Ce mode ne doit pas remplacer la configuration locale des applications. Les
commandes distantes doivent toujours viser le staging vérifié ; ne jamais lier
le workspace à `phjzyohsscwrgwvhgvfh`.

### Planificateur

La migration `20260929002600_worker_schedule.sql` fournit deux tables techniques
dans `ops` (en dehors des 41 tables métier), cinq configurations de workers,
l’envoi pg_net, un cron et une vue de suivi via fonction opérateur. Secrets dans
Vault, aucune autorité supplémentaire pour anon/authenticated/service_role.
Le secret worker est lu lors de l’envoi et n’apparaît pas dans `cron.job`.

Corrections apportées le 2 octobre : rejet du projet production, URL HTTPS
limitée aux projets Supabase, refus des entrées NULL et activation du nettoyage
refusée sans D28. Les secrets peuvent transiter dans la file interne pg_net :
le schéma `net` ne doit jamais être exposé par l’API. Le contrôle impose seulement
`public` dans `api.schemas`.

Validation locale :

- `npm run staging:preflight` : réussi, 26 migrations et 8 fonctions ;
- `npm run test:staging` : 5 tests, dont le refus de production et des emails en
  mode backend seul ;
- `npm run test:database` : 443 assertions, 12 courses ;
- Supabase local : 34 assertions du planificateur, dans une transaction annulée
  avec remplacement temporaire des fonctions concernées. Aucun cron, secret,
  changement de configuration ni envoi HTTP de test conservé après rollback.

La combinaison pg_cron, pg_net et Vault suit la
[documentation Supabase](https://supabase.com/docs/guides/functions/schedule-functions).
Ce résultat prouve la validation locale, pas le fonctionnement d’un staging distant.

## Contrôle préalable

Sans argument, il vérifie le dépôt : 8 points d'entrée Edge alignés sur
`config.toml` et `verify_jwt=false` ; 26 migrations horodatées et uniques, sans
le substitut local `auth.users` ; inscription publique et seed désactivés ; aucun
secret dans les fichiers commitables du dépôt et des submodules (JWT
`service_role` hors démo locale, `sb_secret_`, clé Brevo, `.env` rempli).

Avec la cible, il vérifie en plus :

- le projet visé est hébergé et distinct du projet local ;
- l'URL publique pointe vers `https://<ref>.supabase.co` ;
- les origines sont HTTPS exactes (sans localhost ni joker) ;
- le callback d'invitation est `<origine autorisée>/auth/invitation` ;
- aucun hôte ChallengeMe, ClassCard ou Firebase n'apparaît ;
- trois secrets indépendants d'au moins 32 caractères, aucun repris de la pile
  locale ;
- la durée des liens d'asset est comprise entre 30 et 300 s ;
- les réglages Brevo sont cohérents (les deux ou aucun) ;
- aucune clé `SUPABASE_*` n'est présente ;
- `[remotes.staging]` cible le bon projet, avec `site_url` et redirections en
  HTTPS sur les origines autorisées, sans réactiver les inscriptions ni le seed.

Éprouvé sur des entrées synthétiques : la configuration valide passe, et chaque
défaut injecté est refusé (11 défauts combinés, mauvais projet, secret local
réutilisé, faux secret dans un fichier non suivi).

## Runbook (après les décisions)

Les écritures staging sont désormais autorisées à l’agent. L’authentification
est faite localement par l’utilisateur ; les secrets ne sont jamais affichés,
committés ou transmis aux clients. L’autorisation n’inclut aucune écriture production.

1. `supabase login`, puis création du projet staging dans l'organisation dédiée
   (tableau de bord). Noter le `project-ref`.
2. Ajouter à `supabase/config.toml` :

   ```toml
   [remotes.staging]
   project_id = "<project-ref>"

   [remotes.staging.auth]
   site_url = "https://<academy-staging-host>"
   additional_redirect_urls = ["https://<academy-staging-host>/auth/recovery", "https://<academy-staging-host>/auth/invitation", "https://<platform-staging-host>/auth/recovery", "https://<platform-staging-host>/auth/invitation"]
   ```

   Garder la liste sur une ligne : le contrôle préalable refuse les tableaux
   multilignes au lieu de les lire à moitié.
3. Copier `supabase/functions/.env.staging.example` vers `.env.staging`, générer
   trois secrets neufs (`openssl rand -hex 32`), puis :
   `npm run staging:preflight -- --project-ref <ref> --env supabase/functions/.env.staging`.
   Ne continuer que sur `STAGING PREFLIGHT PASSED`.
4. `supabase link --project-ref <ref>`, puis `supabase db push --dry-run` :
   vérifier que les 26 migrations sont listées, et rien d'autre. Puis
   `supabase db push`, puis `supabase migration list` (local = distant).
5. `supabase config push`, puis contrôler dans le tableau de bord : inscription
   publique désactivée, confirmations e-mail actives, URL et redirections
   staging, SMTP selon la décision 4.
6. `supabase secrets set --env-file supabase/functions/.env.staging`.
7. `supabase functions deploy provision-invitation secure-asset-upload
   read-asset-url expand-email-outbox deliver-email brevo-webhook
   schedule-notifications cleanup-assets-and-content`.
8. Planification des workers selon la décision 6 (livrable à réaliser et tester
   avant cette étape).
9. Builds Web avec la clé **publique** du projet seulement :
   `VITE_SUPABASE_URL` et `VITE_SUPABASE_ANON_KEY` pour les deux back-offices ;
   `SUPABASE_URL`, `SUPABASE_ANON_KEY` et `AUTH_RECOVERY_URL` pour Flutter
   (`vercel-build.sh`). Contrôler qu'aucun bundle ne contient de secret.
10. Premier `SUPER_ADMIN` : inviter le compte depuis Auth, puis une seule
    instruction SQL (profil et rôle), comme dans `test-qa-local.mjs`, exécutée par
    l'opérateur et consignée.
11. Recette staging : les scripts de test actuels refusent toute cible autre que
    loopback, par conception. Un parcours de fumée staging, avec des comptes
    `example.test` et un nettoyage, reste à écrire après les décisions 3 et 4.

Retour arrière : le staging est jetable. En cas de doute, mettre le projet en
pause ou le supprimer. Aucune donnée réelle ne doit y entrer.

## Hors périmètre

Production (phase 7), Android/iOS, Realtime, charge, et toute donnée ou
configuration ChallengeMe.

**Phase 6 : backend seul déployé et vérifié sur le staging `ordjngzihkmknnizlujp`. Frontends, domaines et e-mails reportés, D28 en attente, workers inactifs.**
