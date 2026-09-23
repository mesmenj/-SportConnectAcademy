# Notifications transactionnelles

## Garanties et limites

Les callables de réservation écrivent un document `notificationEvents` dans **la même transaction** que le changement métier. Les invitations coach et administrateur sont enregistrées dans le batch créant leurs profils et leur audit. Aucun appel à Brevo n'est effectué dans ces requêtes utilisateur. La réponse d'invitation conserve `resetLink` et `emailDeliveryId`, avec `emailStatus: queued` et `emailEventId`.

Un déclencheur transforme atomiquement chaque événement en livraisons `mail` et contenus privés `notificationPayloads`. Les événements contiennent un instantané de la réservation ; leur identifiant distingue chaque occurrence, y compris après suppression et recréation. Les coordonnées sont résolues lors de cette première expansion puis figées. Les anciens enregistrements sans `notificationOwnerId` utilisent le rattachement joueur au moment de l'expansion.

Un deuxième déclencheur envoie les emails. Une transaction acquiert un bail de 120 secondes, chaque requête Brevo dispose d'un délai de 15 secondes et utilise une clé UUID persistée dans `body.headers.idempotencyKey`. Les échecs temporaires sont repris avec attente exponentielle, dispersion et respect de `Retry-After`, jusqu'à 10 tentatives par cycle. Le balayage chaque minute reprend les déclencheurs perdus, les baux abandonnés et les envois différés. Chaque passage traite au maximum 50 rappels dus, 50 événements et 50 emails, par groupes de 5.

Une réponse réseau perdue ou un échec de journalisation après l'envoi conserve l'incertitude. La même clé et le même contenu sont réutilisés dans une fenêtre conservatrice de 14 minutes. Au-delà, le statut devient `unknown` : aucun renvoi automatique ni bouton de relance n'est permis. Il faut vérifier l'historique Brevo. Il n'existe pas de garantie universelle d'envoi exactement une fois entre Firestore et un fournisseur HTTP ayant une déduplication temporaire.

Firebase Authentication et Firestore ne partagent pas de transaction : la création du compte Auth précède le batch de profil/invitation. Une erreur avant la tentative de commit déclenche la compensation du compte Auth. Si la confirmation du commit est perdue, la présence de l’événement est vérifiée ; le compte Auth n’est jamais supprimé sur un résultat de commit incertain. Une panne de processus entre ces systèmes peut nécessiter une réconciliation du compte Auth ; la file garantit la reprise **après le commit du profil**.

## Couverture

| Événement                                                                | Responsable | Coach          | Administration |
| ------------------------------------------------------------------------ | ----------- | -------------- | -------------- |
| Création                                                                 | Oui         | Oui si affecté | Oui            |
| Confirmation                                                             | Oui         | Oui si affecté | Non            |
| Rappel 24 h avant le cours confirmé                                      | Oui         | Non            | Non            |
| Refus administratif ou client                                            | Oui         | Oui si affecté | Oui            |
| Annulation                                                               | Oui         | Oui si affecté | Oui            |
| Suppression d'une réservation pending/confirmed, individuelle ou groupée | Oui         | Oui si affecté | Oui            |

Les créations administratives déjà confirmées utilisent le texte de confirmation. Un même email présent dans plusieurs rôles reçoit une seule notification par événement. Une adresse invalide ou manquante produit une livraison `failed` sans bloquer les autres. Le lieu utilise en priorité le nom du cours de la communauté enregistré dans la réservation, puis celui du document de cours pour les anciennes données. Un terrain renseigné reste le repli si aucun cours n’est disponible ; les valeurs « À définir » sont ignorées. Sans lieu connu, un tiret est affiché. Les réservations restent volontairement en anglais, avec le fuseau `Asia/Dubai`.

Les destinataires administratifs sont ceux de `academies/{id}.notificationEmails`, si configurés. Sinon, ce sont les administrateurs actifs de l'académie disposant de la gestion des réservations. En l'absence de destinataire, `NOTIFICATION_ADMIN_EMAIL` conserve l'adresse historique par défaut. Vérifier ce routage pour chaque environnement avant activation. La limite est de 200 destinataires distincts par événement ; un dépassement est journalisé comme `recipient_limit_exceeded`, sans envoi partiel ni destinataire silencieusement ignoré.

Les liens d'invitation ne sont envoyés que pendant les 30 minutes suivant la création de l'événement, et uniquement si le compte Auth existe, est actif et possède toujours la même adresse. Une invitation expirée nécessite un nouveau lien depuis la fiche coach. Un délai de 60 secondes limite les demandes de renvoi répétées. Les mots de passe oubliés côté Flutter continuent à utiliser Firebase Authentication directement.

## Rappels 24 heures avant le cours

L’email de création reste immédiat via la file. Un document `bookingReminders/{bookingId}` est planifié dans la transaction métier pour `startsAt - 24 heures`, si la réservation est confirmée et si cette échéance est encore future. Une réservation en attente devient éligible lors de sa confirmation. Si elle est créée ou confirmée moins de 24 heures avant le cours, aucun rappel immédiat en double n’est ajouté.

Le balayage chaque minute crée atomiquement un seul événement de rappel par version de réservation. Seul l’utilisateur responsable reçoit ce rappel. Les annulations, refus et suppressions invalident le rappel dans leur transaction. Juste avant l’envoi, le worker revérifie le statut, la date et la version de la réservation : un rappel déjà mis en file ne part pas après une annulation connue, une recréation ou le début du cours. Une annulation strictement simultanée à un email déjà confié au fournisseur ne peut pas rappeler cet email.

La précision nominale est d’une minute, hors indisponibilité du scheduler ou de Brevo. Un retard est récupéré tant que le cours n’a pas commencé. Les dates de réservation sont des timestamps absolus ; le fuseau n’intervient que dans l’affichage du message.

Pour les réservations confirmées créées **avant** le déploiement, une migration paginée et répétable prépare les rappels, sans rejouer les emails de création. Depuis `classcard-functions`, avec les identifiants administratifs du projet :

```bash
npm run reminders:plan -- --project sporta-unconfigured
npm run reminders:plan -- --project sporta-unconfigured --apply
```

La première commande ne fait qu’un inventaire. La deuxième crée uniquement les rappels manquants dont le cours commence dans plus de 24 heures. Elle doit être exécutée après le déploiement de l’index `bookings(status, startsAt)` et des workers. Ne pas exécuter la migration avec `--apply` avant d’avoir vérifié le projet et l’inventaire.

## États et exploitation

- `queued`, `sending`, `retry` : gérés par les workers.
- `accepted` : Brevo a accepté la requête, ou confirmé une clé déjà traitée. Cela ne prouve pas la livraison.
- `delivered`, `deferred`, `bounced`, `blocked`, `complained` : mis à jour par webhook.
- `failed` : erreur permanente, invitation expirée ou tentatives épuisées. La relance est possible seulement lorsque `retryable` vaut `true`, sans résultat incertain et avec un contenu encore disponible.
- Les refus Brevo conservent le code HTTP et le code d'erreur fournisseur dans `lastError` (sans son texte libre). Un manque de crédits ou un compte en cours de validation permet une relance manuelle après correction. Une réponse HTTP de succès sans `messageId` conserve le contenu et l'incertitude : elle est reprise avec la même clé, puis passe à `unknown` si la fenêtre de reprise expire.
- `skipped` : rappel annulé, périmé ou devenu inutile.
- `unknown` : résultat incertain hors fenêtre de déduplication. Vérification manuelle dans Brevo ; ne pas remettre arbitrairement l'envoi en file.
- Les anciens journaux `sent/pending/failed` sans `schemaVersion: 2` ne sont jamais rejoués automatiquement. Ils ne contiennent pas nécessairement le contenu nécessaire à une reprise. Réinviter explicitement les coachs concernés ; ne pas rejouer en masse les anciennes réservations.

L'écran **Administration → Suivi des emails** permet de consulter, actualiser, paginer et relancer les échecs récupérables. Les callables vérifient `admins.manage` et le périmètre académie ; seul root peut consulter toutes les académies. Les collections de travail sont interdites en lecture et écriture aux clients. Les callables ne renvoient que les métadonnées nécessaires.

Le contenu privé est supprimé après acceptation ou webhook. Les TTL nettoient les contenus abandonnés (30 minutes pour les invitations, 30 jours pour les réservations), les événements développés et les reçus de webhook. L'expiration d'une invitation est vérifiée par le code indépendamment du nettoyage TTL asynchrone.

Configurer une alerte Cloud Logging sur les erreurs de traitement de la file et surveiller les états `failed/unknown`, l'âge des entrées dues et les quotas Brevo. Un état `deferred` appartient au traitement de livraison Brevo : l'application ne renvoie pas un second email.

## Activation en production

Les changements locaux ne déploient ni fonctions ni secrets, et n'enregistrent pas automatiquement de webhook chez Brevo.

1. Exécuter les vérifications ci-dessous. Construire puis publier l'administration mise à jour **avant** les nouvelles callables : elle accepte les réponses historiques `sent/failed` et le nouveau statut `queued`.
2. Conserver/configurer le secret existant `BREVO_API_KEY`. Créer un secret indépendant `BREVO_WEBHOOK_TOKEN` contenant une valeur aléatoire forte ; ne jamais réutiliser la clé API. Utiliser `firebase functions:secrets:set BREVO_WEBHOOK_TOKEN --project sporta-unconfigured` en saisie interactive.
3. Déployer les index, TTL et règles de la racine : `firebase deploy --only firestore --project sporta-unconfigured`. Les données privées ne doivent jamais devenir accessibles par une règle générique plus permissive.
4. Déployer les fonctions depuis la racine : `firebase deploy --only functions --project sporta-unconfigured`. Le hook `predeploy` compile le backend. Le script npm `deploy` compile et déploie désormais toutes les fonctions, pas uniquement `createAdministrator`.
5. Vérifier les fonctions `expandNotificationEvent`, `deliverNotificationMail`, `retryNotificationQueue`, `brevoDeliveryWebhook`, `listNotificationDeliveries`, `retryNotificationDelivery`. Vérifier l'activation du job Cloud Scheduler et ses permissions d'invocation. Le projet doit disposer de la facturation nécessaire aux fonctions/scheduler.
6. Dans Brevo, créer un webhook transactionnel vers l'URL HTTPS déployée de `brevoDeliveryWebhook`, avec l'en-tête `Authorization: Bearer <BREVO_WEBHOOK_TOKEN>`. Activer les événements d'envoi, livraison, report, soft/hard bounce, blocage, adresse invalide, erreur et spam. Le serveur valide le secret, le destinataire, la référence fournisseur et la corrélation `X-Mailin-custom`. Les doublons et événements anciens n'écrasent pas un état plus récent.
7. Avec des destinataires de test autorisés, vérifier une invitation, une création, une confirmation, un refus client et une suppression. Vérifier la réception réelle et le passage à `delivered`. Vérifier la configuration expéditeur/DKIM/SPF/DMARC dans Brevo et le domaine ; les tests locaux ne prouvent pas la délivrabilité.

Le déploiement de plusieurs fonctions n'est pas atomique. Les nouveaux producteurs sont sûrs même si les workers arrivent ensuite : leurs événements restent en file. Éviter un retour aux anciens producteurs synchrones pendant qu'il reste des événements actifs, car ils contournent cette file.

## Diagnostic des emails absents ou classés en spam

L'acceptation HTTP par Brevo ne prouve pas la réception. Même `delivered` signifie que le serveur destinataire a accepté le message, pas qu'il apparaît dans la boîte principale. Pour un incident, rapprocher le destinataire et l'heure de l'événement des logs **Brevo → Transactionnel → Logs** et du suivi des emails dans l'administration.

- `failed` avec `invalid_recipient` : vérifier l'adresse dans le profil utilisateur responsable ; aucun appel Brevo n'a été effectué pour cette livraison.
- `queued/retry/sending` durable : vérifier les workers, le scheduler et le dernier échec HTTP (notamment authentification, quota ou limitation fournisseur).
- `accepted` durable : vérifier les logs Brevo et la configuration du webhook ; l'absence de webhook ne signifie pas que l'email est perdu.
- `deferred/bounced/blocked` : relever le motif exact chez Brevo (adresse inexistante, rejet du serveur, blocage ou autre). Ne pas relancer en masse les rejets permanents.
- `delivered` mais absent : vérifier spam/quarantaine et les en-têtes du message reçu, notamment `Authentication-Results` et le domaine `d=` de `DKIM-Signature`.

Contrôle DNS public réalisé le 17 septembre 2026 pour l'expéditeur configuré `info@sporta.example.invalid` :

| Requête | Réponse observée |
| --- | --- |
| TXT `sporta.example.invalid` | `v=spf1 include:_spf.mail.hostinger.com ~all` |
| TXT `_dmarc.sporta.example.invalid` | `v=DMARC1; p=none` |
| CNAME `brevo1._domainkey.sporta.example.invalid` | Aucune réponse |
| CNAME `brevo2._domainkey.sporta.example.invalid` | Aucune réponse |
| TXT `mail._domainkey.sporta.example.invalid` | Aucune réponse |

Ces sélecteurs ne couvrent pas toutes les configurations DKIM : leur absence est une piste, pas une preuve d'échec d'authentification. Le SPF Hostinger seul ne permet pas non plus de conclure au résultat SPF d'un message Brevo, qui dépend de son domaine d'enveloppe.

Dans **Brevo → Domaines**, vérifier `sporta.example.invalid` et publier les valeurs exactes fournies pour le code Brevo et DKIM chez le gestionnaire DNS autoritaire, puis vérifier l'authentification dans Brevo. Conserver un seul enregistrement DMARC et un seul SPF par nom ; ne pas remplacer le SPF Hostinger ni inventer de clé DKIM. Le DMARC `p=none` présent n'est pas en soi une erreur. Après validation, contrôler un nouvel email et son authentification DKIM/DMARC ; une authentification correcte améliore la délivrabilité sans garantir la boîte principale.

Référence : [authentification du domaine Brevo](https://help.brevo.com/hc/en-us/articles/12163873383186-Authenticate-your-domain-with-Brevo-Brevo-code-DKIM-DMARC). Ce diagnostic n'a modifié ni le DNS ni le compte Brevo ; les logs fournisseur et les en-têtes d'un message restent nécessaires pour attribuer la cause de chaque incident.

## Vérifications reproductibles

Depuis `classcard-functions` :

```bash
npm test
npm run test:emulators
```

Les tests d'intégration exigent un projet `demo-*`, Firestore et Auth émulés. Le fournisseur email est simulé : aucun email réel n'est envoyé. Ils exécutent les véritables callables et transactions pour vérifier annulation, refus, suppression/recréation, quotas, concurrence, perte de réponse, panne de journalisation, reprise, expiration, webhooks et permissions.

Depuis `classcard-admin` :

```bash
npm test
npm run build
```

Documentation fournisseur : [idempotence Brevo](https://developers.brevo.com/docs/heterogenous-versions-batch-emails), [webhooks Brevo](https://developers.brevo.com/docs/transactional-webhooks).
