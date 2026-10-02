# Phase 4A — Web Back Office

29 septembre 2026 — SportA uniquement. Autorisation humaine : « Passez a la
prochaine phase », puis demandes de poursuite. Périmètre : MVP back-office Web
plateforme et académie ; aucune modification Flutter ni environnement distant.

## Réalisation

Les deux points d'entrée Web utilisent par défaut Supabase. Le code connecté
commun se trouve dans `apps/academy-admin/src/connect/` ; Platform Admin l'importe
comme il importait déjà l'aperçu partagé. Le workspace complet est donc requis
pour compiler Platform Admin. Les anciens aperçus restent disponibles via
`VITE_DESIGN_PREVIEW=true`, avec leurs données fictives clairement séparées.
Le bundle connecté ne charge pas Firebase.

- **Auth** : connexion, déconnexion, demande de récupération, callback recovery,
  invitation et activation du propriétaire, mot de passe et langue préférée.
  Les fragments contenant les tokens sont immédiatement supprimés de l'URL.
  Une mutation du mot de passe dont la réponse a été perdue peut être confirmée
  par une nouvelle connexion au même utilisateur Auth.
- **Session** : stockage dans `sessionStorage`, renouvellement mutualisé ; une
  réponse de refresh ne peut pas rétablir une session après déconnexion.
- **Accès et académies** : `get_access_context`, liste des académies autorisées,
  navigation selon les permissions serveur, refus des rubriques hors périmètre.
  L'académie sélectionnée est conservée par utilisateur/origine et revérifiée au
  chargement. Les formulaires revérifient les permissions avant toute commande.
- **Plateforme** : académies, invitation initiale du propriétaire, statut,
  plans sans prix/quota inventé, abonnements manuels et audit plateforme.
- **Académie** : membres/rôles, invitations/renvoi/révocation, coachs, joueurs,
  liens familiaux et contacts, sites, courts, groupes/cours, offres versionnées,
  achats de forfaits, crédits et historique, séances, réservations, présences,
  évaluations, encaissements, factures consultables/imprimables, tournois,
  notifications, destinataires et paramètres/logo.
- **Assets** : upload via Edge, PNG/JPEG/WebP, clé d'opération liée au fichier,
  affichage via URL signée. Aucun accès Storage direct côté client.

Le catalogue Web raccorde **62 commandes** existantes (59 de 3C, plus renvoi,
relance des notifications et destinataires). L'acceptation des invitations et les
assets passent par leurs parcours dédiés. La présence d'un formulaire ne signifie
pas que toutes ses branches métier ont été rejouées dans le navigateur : le
périmètre des preuves est détaillé ci-dessous.

## Contrats et invariants

`scripts/generate-web-contracts.mjs` extrait les noms et types des paramètres des
migrations locales. `contracts.ts` est généré ; `check:web-contracts` détecte une
dérive. Le client utilise des structures typées pour session, accès, pagination,
arguments RPC et valeurs JSON autorisées.

Les lectures utilisent les projections 3B ou les colonnes explicitement accordées
sur les tables publiques. Les relations sont sélectionnées par leurs UUID, avec
des noms et dates affichés. Aucune écriture directe dans les tables. Les clés
`service_role` et `sb_secret_` sont rejetées par la configuration navigateur.

Les montants restent des chaînes décimales, sans conversion flottante. Dates et
horaires sont convertis dans le fuseau de l'académie ; les heures inexistantes ou
ambiguës aux transitions DST sont refusées. Le serveur conserve l'autorité sur
D34, crédits, capacité, finance, permissions et révisions.

Les formulaires conservent leur intention et clé d'opération dans `sessionStorage`
avant l'envoi. Après une réponse incertaine, ils proposent le rejeu exact, y compris
après rechargement. Les données de lecture sont renouvelées après confirmation.
Les réponses tardives d'une autre académie sont ignorées. Aucun succès optimiste
n'est affiché avant confirmation du serveur.

## Vérification

| Vérification | Résultat |
|---|---|
| Compilation Academy Admin et Platform Admin | Réussite TypeScript + Vite |
| `npm run lint:web` sur le nouveau code et les entrées | Réussite |
| `npm run check:web-contracts` | Contrats conformes aux migrations |
| `npm run test:web` | 8/8 tests du client et des conversions |
| Tests Academy Admin historiques | 16/16 ; ne constituent pas la preuve Supabase |
| `npm run test:web:local` | Parcours Chromium avec Supabase Auth/PostgREST/Edge réels |

Le parcours navigateur vérifie :

1. Connexion plateforme, création d'académie et invitation initiale par l'UI.
2. Activation du propriétaire par callback, retrait du fragment et rechargement.
3. Invitation d'un membre, attribution du rôle coach, création de sa fiche.
4. Joueur, site, court, offre publiée, forfait, règlement confirmé et facture.
5. Séance, réservation confirmée, présence, évaluation ; R=9, H=0 après consommation.
6. D34 : quota épuisé + override → PENDING, sans crédit/place réservés.
7. Modification concurrente : refus de la révision périmée.
8. Réponse perdue après commit : rechargement et rejeu sans doublon.
9. Deux académies : sélection, isolation des listes et réponse tardive ignorée.
10. Coach sans finance, URL de rubrique forgée, suspension puis accès actualisés.
11. Rendu mobile sans débordement horizontal et absence d'exception navigateur.

Les comptes sont synthétiques (`example.test`). Le test utilise uniquement les
ports locaux 54321/54322 pour Supabase et 5173/5174 pour les interfaces. Il amorce
un utilisateur plateforme par SQL de test ; il ne crée aucun endpoint public de
bootstrap. Il déplace uniquement sa propre séance fictive dans le passé pour
vérifier la présence sans attendre le jour suivant. Les autres mutations métier
passent par les RPC avec JWT utilisateur.

## Lancement local

1. Utiliser la pile Supabase locale validée en 3D.
2. Renseigner dans chaque application `.env.local` :

```dotenv
VITE_SUPABASE_URL=http://127.0.0.1:54321
VITE_SUPABASE_ANON_KEY=<clé anon ou publishable de la pile locale>
VITE_DESIGN_PREVIEW=false
```

3. Lancer depuis la racine :

```bash
npm run dev:academy
npm run dev:platform
```

Académie : `http://localhost:5173` ; plateforme : `http://localhost:5174`.
Les paramètres publics locaux ont été ajoutés aux fichiers `.env.local` ignorés,
sans modifier les valeurs Firebase préexistantes.

Pour rejouer le navigateur, fermer les serveurs sur ces deux ports ; le test les
lance et les arrête lui-même. Les fonctions Edge doivent être servies avec un
fichier d'environnement local connu :

```bash
npx playwright install chromium --no-shell
SPORTA_EDGE_ENV_FILE=/chemin/vers/edge-local.env npm run test:web:local
```

Le script récupère les paramètres par `supabase status -o json` sans les afficher,
refuse une API autre que `http://127.0.0.1:54321` et ne transmet aucune clé service
au navigateur. Le secret worker ne sert qu'au provisionnement local. Les captures,
logs et comptes de test sont enregistrés dans un répertoire temporaire annoncé ;
le fichier des comptes est privé (`0600`). Les données restent dans la pile jetable.

Les autres commandes utiles : `npm run build:web`, `npm run lint:web`, `npm run test:web`,
`npm run check:web-contracts` et `npm run generate:web`.

## Modifications préexistantes et limites

Le fichier HTML Platform Admin manquait. Un nouveau point d'entrée minimal vers
`src/main.tsx` et un nouveau modèle `.env.example` Supabase ont été créés ; aucune
ancienne configuration Firebase supprimée n'a été restaurée. Son ancien ESLint et
`.env.sporta` restent absents. Les changements 3D existants ont été conservés.

- Interface MVP en français ; la langue préférée du profil est transmise à Auth/
  l'acceptation, sans prétendre fournir une interface entièrement bilingue.
- Les sélecteurs chargent les pages des références autorisées ; la liste principale
  est paginée. La recherche filtre les éléments déjà chargés et l'indique.
- Les droits sont revalidés au chargement, à l'actualisation et avant chaque
  commande ; pas de souscription Realtime aux révocations dans cette phase.
- Les emails externes, orchestration des workers, choix D28 et D05/D29/D32 restent
  dans leurs périmètres déjà documentés. Aucun paiement en ligne ni règle SaaS
  supplémentaire n'a été créé.
- La recette QA complète (langues, charge, Realtime, navigateurs multiples,
  accessibilité approfondie), Flutter, staging et production restent à réaliser.

**Phase 4A : MVP Web implémenté et validé localement ; prêt pour revue humaine.**
**Prochaine phase : 4B Flutter, sur instruction humaine.**

Dernière passe navigateur : captures et comptes locaux dans
`/var/folders/jf/m30yxqp15zj0m29t48z_1sdw0000gn/T/sporta-web-YlromM/`.
Ce chemin temporaire est une preuve locale de session, pas une dépendance du projet.
