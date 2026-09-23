import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
async function main() {
  if (process.env.GCLOUD_PROJECT !== 'demo-sporta' || !process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST) throw new Error('Ce script exige les émulateurs et GCLOUD_PROJECT=demo-sporta.');
  initializeApp({ projectId: 'demo-sporta' });
  const auth = getAuth(); const db = getFirestore();
  for (const [uid, email] of [['sporta-operator', 'operator@sporta.test'], ['academy-owner', 'owner@sporta.test']]) {
    try { await auth.getUser(uid!); } catch { await auth.createUser({ uid, email, password: 'SportA-local-2026!', emailVerified: true }); }
  }
  await db.doc('platformOperators/sporta-operator').set({ status: 'active', email: 'operator@sporta.test' });
  await db.doc('plans/starter').set({ name: 'Starter', maxPlayers: 100, maxStaff: 5, active: true });
  await db.doc('plans/growth').set({ name: 'Growth', maxPlayers: 500, maxStaff: 20, active: true });
  await db.doc('academies/demo-academy').set({ name: 'SportA Demo Academy', country: 'Cameroun', status: 'active', ownerUid: 'academy-owner', ownerEmail: 'owner@sporta.test' });
  await db.doc('academies/demo-academy/members/academy-owner').set({ role: 'owner', status: 'active', uid: 'academy-owner', email: 'owner@sporta.test', displayName: 'Propriétaire Demo' });
  await db.doc('users/academy-owner/memberships/demo-academy').set({ name: 'SportA Demo Academy', role: 'owner', academyId: 'demo-academy' });
  await db.doc('academySubscriptions/demo-academy').set({ planId: 'starter', planName: 'Starter', maxPlayers: 100, maxStaff: 5, status: 'active', endsAt: Timestamp.fromMillis(Date.now() + 30 * 86400000) });
  const players = await db.collection('academies/demo-academy/players').count().get();
  await db.doc('academies/demo-academy/usage/current').set({ players: players.data().count, staff: 1 });
  console.info('Démonstration locale prête. Identifiants dans README.md.');
}
main().catch(error => { console.error(error.message); process.exitCode = 1; });
