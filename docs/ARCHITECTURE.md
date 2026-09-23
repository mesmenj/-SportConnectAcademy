# SportA — architecture de la plateforme

## Objectif

Transformer la base SportA en produit SaaS pour plusieurs académies, avec une application Flutter pour les familles, un espace de gestion pour chaque académie et un back-office opérateur SportA distinct. Le projet et les données du client existant restent indépendants.

## Organisation proposée

- `apps/academy-admin` : interface React des équipes d’une académie.
- `apps/student` : application Flutter des joueurs, parents et coachs.
- `apps/platform-admin` : nouvelle interface React réservée aux opérateurs SportA.
- `functions` : API Firebase et traitements serveur.
- `docs` : modèle de données, installation, exploitation et décisions.

## Isolation des clients

Une académie est un tenant. Les données métier sont placées sous `academies/{academyId}` : membres, joueurs, familles, coachs, installations, forfaits de cours, séances, réservations, tournois, factures et notifications. Les identifiants de documents ont une portée locale à l’académie.

Les collections globales sont limitées à :

- `users/{uid}` : identité personnelle et préférences, sans rôle administrateur global implicite.
- `platformOperators/{uid}` : accès explicite au back-office SportA.
- `plans/{planId}` : catalogue des abonnements SportA.
- `academies/{academyId}` : configuration et état administratif de l’académie.
- `academySubscriptions/{academyId}` : abonnement et limites effectives, écrits côté serveur.
- `platformAuditLogs/{eventId}` : journal des opérations de la plateforme.

Un utilisateur peut appartenir à plusieurs académies. Chaque appartenance se trouve dans `academies/{academyId}/members/{uid}` avec rôle, statut et permissions. L’interface choisit une académie active ; ce choix n’accorde aucun droit en soi.

Les profils sportifs, réservations et factures d’une académie ne sont pas visibles dans une autre. Un opérateur plateforme ne reçoit pas automatiquement accès au détail des familles ; un accès de support doit être explicite et audité.

## Contrôle des accès

Toutes les fonctions métier reçoivent un `academyId`, vérifient l’identité, l’appartenance active et la permission avant de lire ou modifier les données. Les références entrantes (joueur, séance, coach, famille) sont résolues dans le même chemin d’académie. Aucun repli vers une collection globale n’est autorisé.

Les règles Firestore et Storage vérifient également l’appartenance. Les écritures métier sensibles passent par les fonctions. L’Admin SDK contournant les règles, les fonctions doivent refaire ces contrôles. Les workers revalident le tenant et utilisent des clés d’idempotence incluant l’académie.

## Forfaits et abonnements

Séparer les forfaits SaaS payés par les académies des forfaits de cours payés par les familles.

Un plan SaaS contient un nom, un tarif en unités monétaires mineures, une devise, une périodicité et des limites explicites (joueurs, coachs, administrateurs, fonctionnalités). Les montants, limites et conditions sont figés dans l’abonnement lors de son activation : modifier le catalogue ne modifie pas silencieusement les contrats existants.

États : essai, actif, en retard, suspendu, résilié. Dates : début, fin de période et éventuelle grâce. Vérification serveur de l’échéance à chaque opération protégée, même si le traitement planifié n’est pas passé. Les limites sont appliquées en transaction avec les compteurs ; désactiver un bouton ne suffit pas.

Première option proposée : validation manuelle des règlements par un opérateur, avec référence et audit. Un futur prestataire de paiement utilise des webhooks signés, idempotents, et un rapprochement serveur du montant, de la devise et de l’abonnement. Un retour de navigateur ne confirme jamais un paiement.

Une académie expirée doit pouvoir consulter son statut et renouveler. La politique d’accès aux anciennes données (lecture seule, exports) doit être fixée avant commercialisation.

## Nouveau back-office

Authentification, contrôle du rôle opérateur, tableau de bord, création et suspension d’académies, attribution du premier propriétaire, catalogue des plans, activation et renouvellement des abonnements, suivi des échéances et journal d’audit. Les revenus confirmés doivent être séparés des montants contractuels et des paiements encore attendus.

## Migration de la base

Copier uniquement les sources et les assets autorisés : pas de données clients, secrets, configurations Firebase actives, certificats de signature, historiques Git, caches ou artefacts de compilation. Remplacer la marque et les affiches spécifiques au client avant publication de SportA.

Ne pas brancher les écrans hérités sur une base de production avant migration de leurs requêtes et fonctions vers les chemins d’académie. Conserver une liste explicite des fonctionnalités migrées et bloquer celles qui ne le sont pas.

## Vérifications avant ouverture

Tests d’émulateurs avec deux académies : lectures croisées, écritures croisées, usurpation d’identifiant, invitations, révocation, dépassement concurrent de quotas, expiration, double paiement et traitement des notifications. Tests de parcours pour chaque rôle. Aucun accès public aux données privées ; seules les informations de catalogue volontairement publiées peuvent l’être.

## Firebase

Nouveau projet Firebase entièrement séparé du client existant. Région proposée : europe-west1, à confirmer selon la localisation et les contraintes des futurs clients. Séparer développement et production avant exploitation commerciale. L’activation d’un compte de facturation nécessite de connaître le compte à utiliser ; ne pas réutiliser implicitement celui du client actuel.
