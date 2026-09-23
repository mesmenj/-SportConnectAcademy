import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
async function main() {
  const projectId = process.env.GCLOUD_PROJECT;
  const email = process.argv[2]?.trim().toLowerCase();
  if (!projectId || projectId === 'classcard-79419') throw new Error('Définir GCLOUD_PROJECT avec le projet SportA.');
  if (!email || !/^\S+@\S+\.\S+$/.test(email)) throw new Error('Usage : npm run grant:operator -- email');
  initializeApp({ projectId });
  const user = await getAuth().getUserByEmail(email);
  if (user.disabled) throw new Error('Utilisateur désactivé');
  const batch = getFirestore().batch();
  batch.set(getFirestore().doc(`platformOperators/${user.uid}`), { email, status: 'active', updatedAt: FieldValue.serverTimestamp() });
  batch.create(getFirestore().collection('platformAuditLogs').doc(), { actorId: 'bootstrap-cli', action: 'operator.granted', targetId: user.uid, createdAt: FieldValue.serverTimestamp() });
  await batch.commit();
  console.info(`Opérateur SportA activé : ${email} sur ${projectId}`);
}
main().catch(error => { console.error(error.message); process.exitCode = 1; });
