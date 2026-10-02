# Phase 3D — Auth, Storage, Edge : clôture locale

26 septembre 2026 — workspace `/Users/apple/Documents/SportA`, base `9814b80`.
Suite de [3C](PHASE_3C_BUSINESS_RPC_REPORT.md). Aucun projet Supabase distant,
aucun déploiement, aucune donnée ChallengeMe.

**Statut au 29 septembre 2026 : PHASE 3D CLOSED — LOCAL SUPABASE VALIDATED.**
La demande humaine « Cloturer donc 3D » autorise cette clôture et les corrections.
La pile Docker existante, initialement sans utilisateurs ni académies, a été
reconstruite localement. Auth réel, PostgREST, Storage et les fonctions Edge ont
été exécutés ensemble avec des comptes synthétiques. Aucun environnement distant
n'a été modifié et aucun email externe envoyé.

Environnement vérifié : Supabase CLI **2.118.0**, PostgreSQL Supabase **17.6**,
Edge Runtime **1.76.2** (Deno compatible 2.1.4), PostgreSQL autonome **17.9**.
Les sections initiales décrivent le travail du 26 septembre ; les ajouts de clôture
et les limites restantes figurent ci-dessous.

## 1. Migrations

| Migration | Contenu |
|---|---|
| `20260926002100_auth_invitations.sql` | Auth reste la seule autorité sur l'email et sa vérification ; pas d'inscription publique. `accept_invitation` exige un email vérifié et identique, compare l'empreinte SHA-256 du jeton, crée un profil minimal sans lire les métadonnées de rôle et revérifie que l'invitant a encore le droit d'inviter. Baux de provisionnement réservés au service (`svc_claim_invitation`, `svc_finish_invitation`) |
| `20260926002200_private_assets.sql` | Bucket privé `academy-private-assets`, 2 Mo, sans policy Storage client. `prepare_asset` / `authorize_asset_read` côté base ; la finalisation n'est acceptée qu'après décodage réel de l'image par l'Edge ; nettoyage avec une date limite fournie par l'opérateur (D28 non inventée) |
| `20260926002300_notification_workers.sql` | Expansion de l'outbox en transaction ; destinataires locaux ; rappels ; bail d'envoi séparé ; webhook Brevo idempotent ; envoi perdu → `UNKNOWN` sans renvoi automatique ; purge des contenus sensibles |
| `20260926002400_invitation_resend.sql` | Renvoi explicite d'une invitation : l'ancien jeton est invalidé ; refus si un envoi est en cours ou si une invitation plus récente est active pour le même email |

Migration de clôture : `20260929002500_deferred_scope_trigger_authority.sql`.
Le trigger `private.check_parent_scope` devient SECURITY DEFINER avec un
`search_path` fixé à `pg_catalog` et EXECUTE révoqué aux rôles clients/service.
Les clients ne reçoivent aucun accès supplémentaire au schéma privé.

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
| `npm run test:database` | 25 migrations ; **427 assertions SQL** (dont 70 en `005_auth_storage_workers.sql`) et **12 courses à deux connexions**. Nouvelle exécution réussie le 29 septembre |
| `npm run test:edge` (Node) | 24/24 |
| `npm run test:edge:deno` | 24/24 |
| `npm run check:edge` | Contrôle de types des 8 fonctions |
| `supabase db reset --local` | 25 migrations réappliquées sur une pile locale jetable |
| `npm run test:supabase:db` | 5 suites, **427/427 assertions** sur PostgreSQL Supabase réel |
| `npm run test:supabase:local` | Parcours réel Auth, PostgREST, Storage et Edge réussi |

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

## 5. Corrections révélées par la pile réelle (29 septembre)

- **Connexion email désactivée** : `auth.email.enable_signup=false` entraînait
  `GOTRUE_EXTERNAL_EMAIL_ENABLED=false` avec la CLI 2.118.0. Ce paramètre est
  désormais `true` tandis que `auth.enable_signup=false` interdit toujours
  l'inscription publique. Le parcours réel vérifie `signup_disabled` sur `/signup`.
  [Signalement amont](https://github.com/supabase/supabase/issues/40582).
- **Transaction PostgREST refusée au COMMIT** : le trigger différé de scope
  s'exécutait après le retour de la RPC avec les droits du client, et échouait sur
  `private.command_receipts`. Correction dans la migration 025. La suite `005`
  force désormais les contraintes sous `authenticated`, avant de rétablir le rôle
  de test. Les tests précédents validaient les contraintes sous le propriétaire.
- **Découverte des tests** : `supabase test db` parcourait aussi les fixtures et
  `concurrency/setup.sql`. La commande `test:supabase:db` sélectionne seulement les
  cinq suites TAP. Une base vierge est requise : un passage après le parcours HTTP
  a confirmé que les fixtures/comptages globaux ne sont pas adaptés aux données
  déjà présentes. La validation finale respecte l'ordre reset → SQL → HTTP.
- **Session après récupération** : le test réutilisait un ancien JWT après le
  changement de mot de passe, alors que sa session Auth avait été révoquée. Le
  parcours utilise maintenant le jeton de la nouvelle connexion.
- **Configuration locale** : `[inbucket]` remplacé par `[local_smtp]` ; répertoires
  générés `.temp/` et `.branches/` ignorés par Git. Aucun secret ajouté au dépôt.

## 6. Parcours intégré validé

`test:supabase:local` utilise uniquement loopback : API port 54321, SQL port 54322.
Les vérifications exécutées couvrent :

- refus de l'inscription publique ; création d'un administrateur synthétique par
  Auth Admin local, puis création d'académie par JWT et RPC ;
- provisionnement d'une invitation via Edge, vérification du token Auth, acceptation
  de la membership propriétaire, définition du mot de passe et connexion ;
- rafraîchissement de session, demande de récupération via SMTP local, validation
  d'un token recovery généré par Auth Admin, changement de mot de passe et logout ;
- refus de RPC service pour le propriétaire, refus anonyme et refus hors tenant ;
- upload PNG, téléchargement signé identique aux octets envoyés, refus Storage direct ;
- uploads JPEG et WebP (décodage WASM dans le runtime Edge), rejeu avec le même
  identifiant d'opération et le même asset ;
- refus sans authentification des huit fonctions Edge ; exécution authentifiée
  des workers d'expansion, rappels et purge ; envoi désactivé faute de config Brevo.

Les données synthétiques du dernier parcours restent dans la pile locale jetable.
Les secrets temporaires de test n'ont pas été enregistrés dans Git.
Reproduction et prérequis : [README Supabase](../supabase/README.md).

## 7. Limites après clôture locale

- Aucun appel Brevo externe ni validation de délivrabilité réelle ; webhook et
  erreurs fournisseur couverts par les tests SQL/unitaires, sans fournisseur réel.
- D28 (rétention) et le choix/configuration du fournisseur email restent soumis
  à une décision humaine avant environnement partagé. Aucun calendrier de purge
  supplémentaire ni secret fournisseur n'a été inventé.
- Les workers sont appelés par le test ; leur orchestration périodique dans un
  environnement partagé n'est pas validée ici.
- Les URLs de callback sont locales ; les écrans Web/Flutter, Realtime, la charge,
  staging et production restent hors de la clôture 3D.
- Les décisions produit D05/D29/D32 restent inchangées ; la clôture technique ne
  vaut pas décision métier implicite.

**Suite : phase 4A Web / 4B Flutter sur instruction humaine.**
