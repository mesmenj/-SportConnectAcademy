# Phase 5 — Intégration et QA locale

29 septembre 2026 — SportA uniquement. Autorisation humaine : « Poursuivre la
phase 5 » (reprise après l'arrêt de la session Codex), « avec la même rigueur ».
Périmètre : pile Supabase locale jetable, clients Web et Flutter Web. Aucun
environnement distant, aucune donnée ChallengeMe, aucun email externe.

## Corrections issues de la revue

### Sessions Web (revue humaine du client Web, correctifs Codex vérifiés)

1. **Connexion tardive après déconnexion** : une connexion terminée après une
   déconnexion pouvait rétablir la session. `login` incrémente désormais la
   génération de session ; une réponse périmée est rejetée (`AUTH_REQUIRED`).
2. **Ancien 401 effaçant une nouvelle session** : une réponse « accès refusé »
   d'une requête lancée sous l'ancienne session pouvait effacer la nouvelle.
   La génération est comparée avant tout effacement.

Tests : `late login cannot restore a session after logout`,
`old unauthorized response cannot clear a newly authenticated session`.

### Mutation liée à son auteur (Web et Flutter, nouveau)

La revue ne couvrait pas ce cas. Une commande préparée par le compte A était
envoyée avec la session *courante* : si le compte changeait entre la
revérification des droits et l'envoi (un `await`, ou un rafraîchissement du
jeton), la commande de A partait avec le JWT de B et lui était attribuée.

- Web : `rpc` et `edge` acceptent un `actor` ; la requête est refusée avant
  envoi (`AUTH_REQUIRED`, non incertaine) si la session n'appartient plus à cet
  utilisateur ou si la génération a changé. Le formulaire d'action et l'envoi
  d'image le transmettent. L'envoi d'image capture l'utilisateur **avant** le
  calcul de l'empreinte : sa clé d'idempotence ne peut plus être dérivée d'un
  autre compte.
- Flutter : même garde dans `ConnectClient.rpc` ; `CommandJournal.replay` lie
  le contrôle d'accès et la mutation au propriétaire du journal.

### Intention Flutter conservée après une ré-authentification (nouveau)

`CommandJournal.replay` supprimait l'opération en attente pour toute erreur non
incertaine, y compris `AUTH_REQUIRED`. Une commande dont la réponse avait été
perdue était donc effacée par une simple expiration de session : son auteur ne
pouvait plus la rejouer avec la même clé d'idempotence. Seule une réponse métier
définitive termine désormais l'intention.

Tests : Web `a command prepared by one account is never sent with another
account JWT`, `account switch during token refresh cannot send the pending
command` ; Flutter `account switch during replay never sends the command with
another JWT and keeps it`.

### Outil d'activation locale (`scripts/local-invitation-link.mjs`)

Commencé par Codex pour supprimer les erreurs de recopie des liens rencontrées
pendant la revue. Il génère un fichier `activation.html` cliquable (mode 0600,
dossier temporaire privé, `no-referrer`), sans envoyer d'email ni consommer le
jeton.

Défaut corrigé : l'outil liait le lien Auth à `invited_user_id`, qui n'est
renseigné qu'à l'acceptation ; il échouait donc sur toute invitation valide.
L'identité est maintenant celle de `auth.users` pour l'email de l'invitation,
la même liaison que celle imposée par `svc_finish_invitation`.

```bash
npm run invitation:link -- <UUID de l'invitation affiché dans le Web>
```

## Couverture de la roadmap

Parcours : Platform Admin → académie → owner → coach → joueur → offre → forfait
→ séance → réservation → présence → ledger → facture/paiement, via les
formulaires Web (`test:web:local`) et le client Flutter (`test:flutter:local`).

| Exigence | Preuve | Statut |
|---|---|---|
| Sécurité | 427 assertions SQL (RLS, RPC, FK tenant) ; refus PostgREST ; 8 gardes Edge ; route forgée, révocation en direct, coach restreint ; jetons corrompus et réutilisés refusés ; mutation liée à son auteur | Couvert |
| Concurrence | 12 courses à deux connexions ; courses client (refresh, déconnexion, connexion tardive, 401 périmé, changement de compte, réponse tardive d'académie) | Couvert, hors charge |
| Emails | Rendu FR/EN, fuseau de l'académie, passage de date, heure d'été/hiver ; SMTP local | Rendu couvert ; délivrabilité Brevo non testée |
| Storage | PNG/JPEG/WebP, rejeu idempotent, téléchargement signé, image corrompue refusée, accès direct et étranger refusés | Couvert |
| Fuseau horaire | Conversion académie, heures ambiguës et inexistantes (DST), emails | Couvert |
| Langues | Préférence EN conservée ; emails FR/EN | Partiel : interfaces Web et Flutter en français uniquement |
| Erreur réseau / retry | Réponse perdue, rechargement, réessai sans doublon (Web) ; rejeu après reconstruction du journal (Flutter) | Couvert |
| Audit | Audit de l'académie lu sous le rôle owner, périmètre tenant | Couvert (audit plateforme : parcours 4A) |
| Realtime | Aucune table métier publiée (vérifié) | **Non implémenté** |
| Navigation Web/Flutter | Chromium Web 390 px ; build Flutter compilé sous Chromium 390 px | Web couvert ; Android/iOS non exécutés |

## Validation (29 septembre 2026)

| Commande | Résultat |
|---|---|
| `npm run test:database` | 427 assertions SQL, 12 courses, PostgreSQL 17.9 jetable |
| `npm run test:edge` / `test:edge:deno` / `check:edge` | 27 tests Node, 24 tests Deno, types OK |
| `npm run check:web-contracts` | Contrats générés à jour |
| `npm run test:web` | 13/13 (dont 2 nouveaux) |
| `npm test --prefix apps/academy-admin` | 16/16 historiques |
| `npm run lint:web` / `build:web` | Sans erreur |
| `npm run test:flutter` / `lint:flutter` | 13 réussis, 1 ignoré (HTTP réel, lancé à part) ; aucun problème d'analyse |
| `npm run test:supabase:local` | Auth, PostgREST, Storage, Edge et workers réels |
| `npm run test:web:local` | 8 parcours Chromium |
| `npm run test:qa:local` | Activation par fichier généré, Storage, langue, fuseau, audit, Realtime |
| `npm run test:flutter:local` | Parcours famille/coach, ledger = 9, facture émise |
| `flutter build web` + `test:flutter:browser` | Bundle reconstruit après correction ; aucun secret ni compte de test dans le bundle |

`npm run test:supabase:db` n'a **pas** été relancé : il exige une base vierge et
la base locale contient les comptes de la revue manuelle, qui n'ont pas été
effacés. Les mêmes suites SQL passent sur le cluster jetable de `test:database`.

Les parcours intégrés lisent `SPORTA_LOCAL_ANON_KEY`, `SPORTA_LOCAL_SERVICE_KEY`
et `WORKER_SECRET` depuis `supabase status -o json` et le fichier Edge local
(voir `supabase/README.md`).

## Limites ouvertes

- **Realtime** : aucune mise à jour en direct ; les droits sont revérifiés au
  chargement, à l'actualisation et avant chaque commande.
- **Brevo** : délivrabilité externe et rétention D28 à valider avant tout
  environnement partagé.
- **Mobile** : Android/iOS non exécutés.
- **Langues d'interface** : FR uniquement côté Web et Flutter.
- **Charge et navigateurs multiples** : non mesurés (Chromium seulement).
- Décisions D05/D29/D32 inchangées.

**Phase 5 : QA d'intégration locale réalisée ; prête pour revue humaine.**
**Prochaine phase : 6 Staging, uniquement sur instruction humaine et après
arbitrage des limites ci-dessus.**
