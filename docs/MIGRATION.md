# État et ordre des migrations

## Actif et distinct du projet client

- Console opérateur, profils `platformOperators`, catalogue des plans, abonnements manuels.
- Académies, membres (responsables, coachs, parents, élèves), suspension et réactivation des accès, annuaire des appartenances utilisateur. Les propriétaires et les opérateurs gèrent les rattachements ; le quota d’équipe est transactionnel.
- Espace web académie minimal et création de joueurs avec quotas transactionnels.
- Connexion et sélection d’académie dans la nouvelle entrée Flutter.
- Architecture Firestore cloisonnée et Storage fermé jusqu’à migration des fichiers.

## À migrer avant parité fonctionnelle

1. Membres : invitations et création des comptes par un parcours utilisateur, permissions plus fines et transfert de propriété. Le rattachement de comptes Authentication existants et la suspension d’accès sont actifs.
2. Configurations de cours, installations et communautés : chemins tenant et références locales, suppression des lectures globales.
3. Séances et réservations : capacité, idempotence, décompte des cours et cohérence des références au sein de l’académie.
4. Évaluations, présence, tournois et calendriers : permissions dédiées par rôle.
5. Encaissements famille et factures : snapshots tenant, séquence/reférence par académie, identité de facturation configurable.
6. Notifications : configuration d’expéditeur par académie, secrets dédiés côté serveur, payloads privés, journaux et workers cloisonnés.
7. Fichiers : règles Storage par académie, limites et validation d’images.
8. Parcours Flutter historiques : contexte d’académie explicite dans chaque repository, auth et navigation. Remplacer les supports marketing du client.
9. FR/EN : réutiliser le catalogue hérité et traduire les nouvelles interfaces de plateforme. Les nouvelles interfaces du socle sont actuellement en français.
10. Paiements SaaS : choix du prestataire, tarifs, devises, renouvellement, webhooks signés et idempotents. Travail reporté à la demande du propriétaire du projet.

## Règles de migration

Une fonctionnalité n’est pas activée tant que ses règles, fonctions et requêtes ne sont pas adaptées ensemble. Aucun `academyId` fourni par l’interface n’est considéré comme une autorisation. Ne jamais ajouter une règle globale permissive pour débloquer un ancien écran. Ajouter des tests A/B pour chaque collection et chaque fonction migrée.

Aucune donnée réelle du client n’a été importée. Une éventuelle migration de données exigera un périmètre, une validation des propriétaires, des sauvegardes et un script explicite.
