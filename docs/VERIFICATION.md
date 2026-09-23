# Vérification du 23 septembre 2026

- Backend TypeScript : compilation réussie.
- Tests unitaires des identifiants, quotas et échéances : 3 réussis.
- Émulateurs Authentication / Firestore / Functions : 15 tests réussis, aucun échec ni test ignoré.
- Build des deux interfaces React : réussi.
- ESLint des nouvelles interfaces et de la gestion des membres : réussi.
- Flutter : analyse ciblée sans erreur ; 2 tests hérités réussis ; compilation web réussie.

Les tests d’intégration passent par les véritables endpoints callable des émulateurs et les règles Firestore via REST. Ils couvrent les accès inter-académies, les opérations réservées aux opérateurs, l’idempotence de l’activation d’abonnement, les quotas concurrents joueurs/équipe, la révocation des membres, l’expiration et la suspension d’académie.

Les tests Flutter hérités portent sur les traductions de l’ancien onboarding et des formulaires ; ils ne constituent pas une validation exhaustive du nouveau parcours connecté. La compilation et l’analyse couvrent la nouvelle entrée Flutter. Les parcours utilisateur complets et les modules historiques restant à migrer sont décrits dans MIGRATION.md.

Aucun projet Firebase cloud créé ou déployé. Aucun prestataire de paiement activé.
