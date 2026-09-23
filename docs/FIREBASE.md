# Firebase SportA

Projet : `sporta-hub-2026` (SportA), compte de création `mesmenj@gmail.com`.
Console : https://console.firebase.google.com/project/sporta-hub-2026/overview
Alias CLI : `sporta`. Le projet par défaut reste `demo-sporta` pour les commandes locales.

## Applications enregistrées

| Application | Identifiant Firebase | Identifiant natif |
| --- | --- | --- |
| Flutter Android | `1:748675195464:android:2030db6ffac8e07da42e7d` | `com.sporta.app` |
| Flutter iOS | `1:748675195464:ios:43670326f3e97135a42e7d` | `com.sporta.app` |
| Flutter Web | `1:748675195464:web:b3707efa61f1bdb4a42e7d` | — |
| Academy Admin | `1:748675195464:web:64403b9c69f76f27a42e7d` | — |
| Platform Admin | `1:748675195464:web:08b7344b3fdcd0c7a42e7d` | — |

Les configurations clientes publiques sont intégrées au code. Elles ne sont pas des clés de compte de service.
Android utilise `android/app/google-services.json` et le plugin Google Services ; iOS embarque `ios/Runner/GoogleService-Info.plist`. Flutter sélectionne sa configuration cloud par plateforme dans `firebase_options_sporta.dart`.

## Choisir le mode

Les interfaces disposent désormais d’un aperçu de design sans Firebase, décrit dans [DESIGN.md](DESIGN.md). Pour les émulateurs web, définir `VITE_DESIGN_PREVIEW=false`. Le mode web `sporta` garde automatiquement l’entrée Firebase. Pour Flutter, ajouter `--dart-define=DESIGN_PREVIEW=false` pour activer Firebase.

Les commandes locales existantes gardent les émulateurs et leurs comptes de démonstration.
Pour cibler le cloud, une fois les prérequis ci-dessous remplis :

```bash
npm run dev:sporta --prefix apps/academy-admin
npm run dev:sporta --prefix apps/platform-admin
```

Les profils `.env.sporta` prennent priorité sur `.env.local` en mode `sporta`. Placer la clé publique reCAPTCHA v3 dans `VITE_APPCHECK_SITE_KEY` dans chaque `.env.sporta.local` (ignoré par Git).
Les builds correspondants sont `npm run build:sporta --prefix apps/academy-admin` et `npm run build:sporta --prefix apps/platform-admin`.

Flutter, depuis `apps/student` :

```bash
flutter run -d chrome --dart-define=DESIGN_PREVIEW=false --dart-define=USE_FIREBASE_EMULATORS=false --dart-define=FIREBASE_APPCHECK_SITE_KEY=VOTRE_CLE_PUBLIQUE
flutter run -d ID_APPAREIL --dart-define=DESIGN_PREVIEW=false --dart-define=USE_FIREBASE_EMULATORS=false
```

La seconde commande concerne Android/iOS. Utiliser également ces paramètres pour les builds cloud. Sans `USE_FIREBASE_EMULATORS=false`, Flutter reste en mode émulateur.

## Prérequis cloud encore à terminer

L'enregistrement des applications ne déploie pas le backend et ne rend pas les parcours cloud opérationnels à lui seul.

1. Activer Authentication Email/Password, vérifier les domaines autorisés et créer les vrais comptes SportA. Les comptes `@sporta.test` restent exclusivement locaux.
2. Choisir la région Firestore, créer la base et déployer les règles/index du projet. Les fonctions actuelles ciblent `europe-west1`.
3. Enregistrer App Check : reCAPTCHA v3 pour chacune des trois apps web, Play Integrity pour Android (empreinte SHA-256 de signature nécessaire), DeviceCheck pour iOS. Flutter active ces fournisseurs natifs par défaut. Les simulateurs nécessitent une configuration de débogage App Check dédiée avant utilisation cloud.
4. Choisir l'hébergement du backend et, si nécessaire, le compte de facturation. Aucune facturation n'a été associée par cette configuration.
5. Déployer les fonctions SportA et créer le premier opérateur après création de son compte Authentication :

```bash
GCLOUD_PROJECT=sporta-hub-2026 npm --prefix functions run grant:operator -- votre-email
```

Exécuter le bootstrap avec les droits IAM appropriés, sans variables d'émulateurs. Déployer uniquement `functions/`, jamais `reference/client-functions/`.
6. Pour Hosting, créer et associer les sites aux targets `platform` et `academy` avant déploiement.

## Héberger les fonctions dans Classcard

C'est possible avec une architecture entre projets, mais le backend actuel n'est pas configuré pour cela. `initializeApp()` utilise le projet d'exécution, et les clients utilisent les fonctions du projet SportA.
Il faudrait une identité d'exécution dédiée dans Classcard, des permissions minimales sur SportA, un Admin SDK ciblant explicitement SportA et des endpoints clients adaptés. La validation Firebase Auth et App Check doit aussi cibler SportA ; changer uniquement le `projectId` de Firestore ne suffit pas. Les déclencheurs éventuels doivent être étudiés séparément.

La configuration actuelle conserve donc les endpoints SportA, sans modification ni déploiement dans Classcard. Héberger directement les fonctions dans SportA évite ce couplage ; un même compte de facturation peut être lié à plusieurs projets si le propriétaire le décide.

Références :
- https://firebase.google.com/docs/projects/multiprojects
- https://firebase.google.com/docs/auth/admin/verify-id-tokens
- https://firebase.google.com/docs/functions/callable-reference
