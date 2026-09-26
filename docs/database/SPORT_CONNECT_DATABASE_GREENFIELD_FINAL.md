# Sport Connect Academy — contrat greenfield final

Date : 26 septembre 2026. Sources : décisions humaines de la roadmap, puis
[V1.1](SPORT_CONNECT_DATABASE_DESIGN_V1_1.md), puis [V1](SPORT_CONNECT_DATABASE_DESIGN_V1.md).
Les interdictions d'implémenter contenues dans ces anciens documents décrivent leur
phase documentaire ; la demande humaine de reprise autorise maintenant la phase 3A.

## A. Principes greenfield

SportA est le workspace cible indépendant. PostgreSQL/Supabase devient le socle
cible. Aucune donnée, identité ou configuration ChallengeMe n'est importée.
Les interfaces actuelles sont des prototypes ; leur mode Firebase n'est pas une
implémentation de ce contrat. Les blocs physiques V1 §25 s'appliquent avec les
corrections V1.1 et les adaptations greenfield ci-dessous.

## B. Frontière ChallengeMeAcademy

Les repositories classcard restent en lecture seule. Aucun déploiement Firebase,
seed, import, synchronisation ou changement distant. Les copies documentaires V1
et V1.1 sont des références de conception, pas des dépendances runtime.

## C. Catalogue final

| Schéma | Tables |
|---|---|
| public — identité/catalogues | user_profiles, permissions, platform_roles, academy_roles |
| public — accès | academies, academy_memberships |
| public — sport | players, player_links, coaches, stadiums, courts, communities, community_courses, service_offers, player_packages, sessions, bookings, booking_attendance, player_evaluations |
| public — finance/SaaS | academy_payments, academy_invoices, tournaments, platform_plans, academy_subscriptions |
| private — accès | platform_user_roles, platform_role_permissions, academy_membership_roles, academy_role_permissions, academy_invitations |
| private — historique | course_ledger, booking_events, subscription_events, audit_log, command_receipts |
| private — notifications/assets | academy_notification_recipients, notification_events, notification_deliveries, notification_payloads, notification_webhook_receipts, booking_reminders, academy_assets |

Total : 24 tables public et 17 private, soit **41**. auth.users appartient à
Supabase et n'est pas une table applicative supplémentaire.

## D. Retraits V1.1

T40 legacy_identity_map, T41 legacy_entity_map, T42 migration_issues sont retirées.
Aucune FK opérationnelle du catalogue ne dépend de ces tables. command_receipts,
audit_log et academy_assets sont conservées. community_courses est conservée :
c'est un concept métier neutre, pas un mécanisme de migration.

Retrait des valeurs uniquement migration : acteur MIGRATION, LEGACY_OPENING,
événement MIGRATED, origines LEGACY, paiement LEGACY_UNVERIFIED, permission
migration.review et tournaments.legacy_registered_count. Les dates des nouveaux
événements sont obligatoires. Aucune colonne Firebase UID/mapping/quarantaine.

## E. D34 = DECIDED — HUMAN

R = remaining_sessions ; H = confirmations non consommées ; A = R − H.
R ≥ 0, H ≤ R, A ≥ 0. Confirmer exige un package résolu et A ≥ 1 après verrou et
recalcul serveur. L'override quota à A = 0 produit PENDING avec OVERRIDE_USED et
motif obligatoire. Aucun crédit fictif, credit_holds ou hold_exempt.

## F. RBAC final

Rôles plateforme SUPER_ADMIN et PLATFORM_ADMIN, séparés des rôles tenant.
Rôles tenant ACADEMY_OWNER, ACADEMY_ADMIN, MANAGER, STAFF, COACH, STUDENT, PARENT.
Bundles selon V1.1 §8–9 : Owner/Admin finance et accès ; seul Owner transfère la
propriété ; Manager gère le sport sans finance ni gestion des memberships ; Staff
opère les réservations sans override ; Coach intervient seulement sur ses
affectations ; Parent/Student sur leurs liens actifs. Cinq overrides pour
Owner/Admin/Manager. Aucune permission libre par utilisateur.
Les permissions de lecture ne dispensent jamais des projections et contrôles de
relation de 3B/3C. En 3A, aucun rôle client ne peut accéder aux tables.

## G. Invariants

FK composites tenant, contraintes package/joueur et séance/coach/terrain ;
exclusions court et coach locales OPEN/CLOSED en intervalle [début, fin) ;
CANCELLED ne bloque pas. Plusieurs guardians, un SELF/principal/contact financier
actif maximum chacun. Unique booking PENDING/CONFIRMED sans filtre deleted_at.
Offres versionnées : une publication par academy/offer_key, durées et âges pouvant
se chevaucher. Finance numeric(18,2), XAF entier, aucun taux de conversion.
Le ledger et les journaux sont append-only. Les FK de reçu sont différées pour
insérer le reçu après ses effets ; scope/academy des effets doivent correspondre.
Les invariants R/H/A, ledger/cache, capacité exacte, permissions et transitions
relèvent des transactions 3C ; le DDL seul ne les réalise pas.

## H. Ordre des dépendances

Schémas/extensions → identité/plateforme → accès académie → ressources sportives
→ offres/packages/ledger → séances/bookings → finance/SaaS → notifications/audit
→ reçus/assets → FK cycliques/intégrité/exclusions → index → catalogue RBAC
→ RLS deny-by-default. Les FK cycliques sont ajoutées après les tables.

## I. Décisions produit non bloquantes pour DDL

Fenêtre d'annulation D05, complétion anticipée D29, numérotation facture D32,
paramétrage langue/timezone, rétention, politique commerciale et identité de
facturation restent à définir pour les commandes concernées. Aucun prix, quota,
compte administrateur ou fournisseur de paiement n'est inventé.
numeric(18,2) arrondit à l'affectation : la validation de précision en entrée sera
obligatoire dans les RPC avant le cast ; les CHECK XAF ne la remplacent pas.

## J. Autorisation SQL

Reprise locale de la fondation 3A autorisée par l'utilisateur. Aucun backend
distant modifié. Revue du résultat 3A avant les policies, RPC et interfaces
connectées, conformément au point d'arrêt de la roadmap jointe.

GREENFIELD DESIGN STATUS: READY FOR DDL
CHALLENGEMEACADEMY MODIFIED: NO
LEGACY MIGRATION TABLES INCLUDED: NO
EXPECTED TABLE COUNT: 41
