# SportA Functions

Backend transactionnel des réservations. Les clients ne modifient jamais directement les séances ou réservations : ils passent par les fonctions appelables protégées par Auth et App Check.

## Modèle minimal

- `users/{uid}` : `role`, `academyIds`
- `users/{uid}/players/{playerId}` : rattachement parent-joueur
- `players/{playerId}` : `academyId`
- `sessions/{sessionId}` : `academyId`, `coachId`, `courtId`, `startsAt`, `endsAt`, `capacity`, `bookedCount`, `price`, `currency`, `status: open|closed|cancelled`
- `bookings/{sessionId}_{playerId}` : réservation idempotente

## Démarrage

```bash
npm install
npm test
cd .. && firebase emulators:start
```

App Check est imposé par les fonctions. Pour les émulateurs, utilisez un jeton de debug App Check côté client. Les claims `role` et `academyIds` doivent être attribués depuis un environnement administrateur de confiance.

## Provisionner le premier root

Créez d'abord `operator@example.invalid` dans Firebase Authentication, puis authentifiez localement l'Admin SDK avec des Application Default Credentials. Le script refuse de travailler sur un projet différent de `sporta-unconfigured` et crée son profil d'autorisation dans Firestore sans custom claims.

```bash
gcloud auth application-default login
npm run grant:root
```

Pour choisir une autre académie :

```bash
npm run grant:root -- operator@example.invalid autre-academie
```

## Notifications email

Voir [NOTIFICATIONS.md](NOTIFICATIONS.md) pour l’architecture de la file, les états, les tests par émulateurs et la procédure d’activation des workers et du webhook Brevo.
