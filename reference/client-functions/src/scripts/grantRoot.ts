import { applicationDefault, getApps, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { ROLE_PERMISSIONS } from '../authorization.js';

const EXPECTED_PROJECT_ID = 'sporta-unconfigured';
const DEFAULT_ROOT_EMAIL = 'operator@example.invalid';
const DEFAULT_ACADEMY_ID = 'tennis-club-bonanjo';

async function main(): Promise<void> {
  const email = (process.argv[2] || DEFAULT_ROOT_EMAIL).trim().toLowerCase();
  const academyId = (process.argv[3] || DEFAULT_ACADEMY_ID).trim();
  const projectId = process.env.GOOGLE_CLOUD_PROJECT || process.env.GCLOUD_PROJECT || EXPECTED_PROJECT_ID;

  if (projectId !== EXPECTED_PROJECT_ID) {
    throw new Error(`Projet refusé : ${projectId}. Projet attendu : ${EXPECTED_PROJECT_ID}.`);
  }
  if (!/^\S+@\S+\.\S+$/.test(email)) throw new Error('Adresse e-mail invalide.');
  if (!/^[A-Za-z0-9_-]{1,100}$/.test(academyId)) throw new Error('Identifiant académie invalide.');

  if (!getApps().length) initializeApp({ credential: applicationDefault(), projectId });
  const auth = getAuth();
  const user = await auth.getUserByEmail(email);
  const profileRef = getFirestore().collection('users').doc(user.uid);
  const existing = await profileRef.get();
  const existingAcademies = existing.exists && Array.isArray(existing.get('academyIds')) ? existing.get('academyIds') as string[] : [];
  const academyIds = Array.from(new Set([...existingAcademies, academyId]));
  await profileRef.set({
    email, displayName: user.displayName || email.split('@')[0], role: 'root', status: 'active',
    academyIds, permissions: ROLE_PERMISSIONS.root,
    createdAt: existing.exists ? existing.get('createdAt') ?? FieldValue.serverTimestamp() : FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });

  console.info(`Profil Firestore root créé pour ${email} (${user.uid}) sur ${projectId}.`);
  console.info(`Académies autorisées : ${academyIds.join(', ')}.`);
  console.info('Les autorisations sont actives immédiatement.');
}

main().catch(error => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
