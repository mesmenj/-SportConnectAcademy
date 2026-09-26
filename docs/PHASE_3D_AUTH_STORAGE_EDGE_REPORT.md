# Phase 3D — Auth, Storage, Edge : rapport local

26 septembre 2026 — workspace `/Users/apple/Documents/SportA`, base `9814b80`.
Suite de [3C](PHASE_3C_BUSINESS_RPC_REPORT.md). Aucun projet Supabase distant,
aucun déploiement, aucune donnée ChallengeMe.

**Statut : implémenté et validé localement sans le runtime Supabase complet.**
Docker et la CLI Supabase sont absents : Auth réel, PostgREST, Storage et
l'exécution des fonctions Edge sous `supabase functions serve` n'ont pas été
exécutés ensemble. `npm run test:supabase:local` existe, mais n'a pas été lancé.

## 1. Migrations

| Migration | Contenu |
|---|---|
| `20260926002100_auth_invitations.sql` | Auth reste la seule autorité sur l'email et sa vérification ; pas d'inscription publique. `accept_invitation` exige un email vérifié et identique, compare l'empreinte SHA-256 du jeton, crée un profil minimal sans lire les métadonnées de rôle et revérifie que l'invitant a encore le droit d'inviter. Baux de provisionnement réservés au service (`svc_claim_invitation`, `svc_finish_invitation`) |
| `20260926002200_private_assets.sql` | Bucket privé `academy-private-assets`, 2 Mo, sans policy Storage client. `prepare_asset` / `authorize_asset_read` côté base ; la finalisation n'est acceptée qu'après décodage réel de l'image par l'Edge ; nettoyage avec une date limite fournie par l'opérateur (D28 non inventée) |
| `20260926002300_notification_workers.sql` | Expansion de l'outbox en transaction ; destinataires locaux ; rappels ; bail d'envoi séparé ; webhook Brevo idempotent ; envoi perdu → `UNKNOWN` sans renvoi automatique ; purge des contenus sensibles |
| `20260926002400_invitation_resend.sql` | Renvoi explicite d'une invitation : l'ancien jeton est invalidé ; refus si un envoi est en cours ou si une invitation plus récente est active pour le même email |

Les RPC `svc_*` sont réservées à `service_role`. Elles ne sont exécutables ni par
`authenticated` ni par `anon`, et un owner ne peut pas usurper le rôle de worker
(test).

## 2. Fonctions Edge

`brevo-webhook`, `cleanup-assets-and-content`, `deliver-email`,
`expand-email-outbox`, `provision-invitation`, `read-asset-url`,
`schedule-notifications`, `secure-asset-upload` : des points d'entrée minces vers
`_shared/handlers.mjs`.

- L'utilisateur est authentifié via Auth HTTP ; les RPC utilisateur ne passent
  jamais par l'autorisation service.
- Les secrets des workers sont comparés en temps constant.
- Les corps de requête sont bornés.
- Les images sont réellement décodées (PNG, JPEG, WebP) avant la finalisation.
- Les emails sont localisés dans le fuseau de l'académie, sans interpolation HTML.
- Les erreurs du fournisseur ne divulguent ni secret ni email.

`supabase/auth/client.mjs` : client Auth (invitation, connexion, rafraîchissement,
réinitialisation, mot de passe, déconnexion), sans injection de rôle.

Les dossiers vides `asset-url`, `cleanup`, `provision-invitations`, `send-emails`
et `upload-asset` précèdent la reprise ; ils ne contiennent aucune fonction.

## 3. Tests exécutés

| Commande | Résultat |
|---|---|
| `npm run test:database` | 24 migrations ; **427 assertions SQL** (dont 70 en `005_auth_storage_workers.sql`) et **12 courses à deux connexions**. 4 passes consécutives vertes |
| `npm run test:edge` (Node) | 24/24 |
| `npm run test:edge:deno` | 24/24 |
| `npm run check:edge` | Contrôle de types des 8 fonctions |

Courses 3D : double acceptation, révocation contre acceptation, **renvoi contre
acceptation de l'ancien lien** (l'ancien jeton est refusé, aucune adhésion n'est
créée, une seule notification de renvoi), webhook contre résultat tardif de
l'expéditeur.

## 4. Défauts trouvés et corrigés pendant cette reprise

- **Prise de bail d'envoi intermittente (production)** : `svc_claim_delivery`
  écrivait `lease_until` et `next_attempt_at` avec deux appels distincts à
  `clock_timestamp()`. La contrainte SENDING impose leur égalité, donc le worker
  échouait aléatoirement (2 exécutions sur 3 avant correction). La même instant
  sert désormais pour les deux colonnes ; le test `005` et les données de
  concurrence sont corrigés de la même façon.
- **Renvoi d'une invitation supplantée** : renvoyer une invitation expirée alors
  qu'une invitation plus récente était active pour le même email produisait une
  erreur brute `23505`. Le code métier `INVITATION_EXISTS` est désormais renvoyé,
  avec un test dédié.

## 5. Reste à faire avant de clore 3D

1. Démarrer une pile Supabase locale jetable (Docker + CLI), puis exécuter
   `supabase db reset --local` et `npm run test:supabase:local`, avec les fonctions
   servies.
2. Vérifier la compatibilité réelle de `config.toml`, des redirections Auth et du
   bucket avec la version de la CLI.
3. Faire valider par un humain les choix de rétention (D28) et de fournisseur
   email avant tout environnement partagé.

Tant que le point 1 n'est pas fait, 3D ne doit pas être annoncée comme validée
sur Supabase.
