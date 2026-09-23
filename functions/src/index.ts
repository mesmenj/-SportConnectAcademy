import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { FieldValue, Timestamp, getFirestore } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { setGlobalOptions } from 'firebase-functions/v2/options';
import { id, text, planInput, positiveInteger, subscriptionIsActive } from './domain.js';

initializeApp();
setGlobalOptions({ region: 'europe-west1', maxInstances: 10 });
const db = getFirestore();
const options = { enforceAppCheck: process.env.FUNCTIONS_EMULATOR !== 'true' };
const signedIn = (uid?: string) => { if (!uid) throw new HttpsError('unauthenticated', 'Connexion requise'); return uid; };
function input<T>(parse: () => T): T { try { return parse(); } catch (e) { throw new HttpsError('invalid-argument', e instanceof Error ? e.message : 'Entrée invalide'); } }
async function operator(uid?: string) {
  const actor = signedIn(uid);
  const profile = await db.doc(`platformOperators/${actor}`).get();
  if (profile.get('status') !== 'active') throw new HttpsError('permission-denied', 'Accès opérateur requis');
  return actor;
}
function audit(actorId: string, action: string, targetId: string, details: Record<string, unknown> = {}) {
  return { actorId, action, targetId, details, createdAt: FieldValue.serverTimestamp() };
}
export const platformSavePlan = onCall(options, async request => {
  const actor = await operator(request.auth?.uid);
  const plan = input(() => planInput(request.data));
  const planId = input(() => id(request.data.planId));
  const batch = db.batch();
  batch.set(db.doc(`plans/${planId}`), { ...plan, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  batch.create(db.collection('platformAuditLogs').doc(), audit(actor, 'plan.saved', planId, plan));
  await batch.commit();
  return { planId };
});
export const platformCreateAcademy = onCall(options, async request => {
  const actor = await operator(request.auth?.uid);
  const data = input(() => ({ academyId: id(request.data.academyId), name: text(request.data.name, 'Nom'), ownerEmail: text(request.data.ownerEmail, 'Email', 254).toLowerCase(), country: text(request.data.country, 'Pays') }));
  let owner;
  try { owner = await getAuth().getUserByEmail(data.ownerEmail); }
  catch { throw new HttpsError('failed-precondition', 'Le propriétaire doit d’abord posséder un compte Firebase Authentication SportA.'); }
  if (owner.disabled) throw new HttpsError('failed-precondition', 'Compte propriétaire désactivé');
  const ref = db.doc(`academies/${data.academyId}`);
  await db.runTransaction(async tx => {
    if ((await tx.get(ref)).exists) throw new HttpsError('already-exists', 'Identifiant académie déjà utilisé');
    tx.create(ref, { name: data.name, country: data.country, ownerUid: owner.uid, ownerEmail: data.ownerEmail, status: 'active', createdAt: FieldValue.serverTimestamp(), createdBy: actor });
    tx.create(ref.collection('members').doc(owner.uid), { uid: owner.uid, email: data.ownerEmail, displayName: owner.displayName ?? '', role: 'owner', status: 'active' });
    tx.set(db.doc(`users/${owner.uid}/memberships/${data.academyId}`), { academyId: data.academyId, name: data.name, role: 'owner' });
    tx.create(ref.collection('usage').doc('current'), { players: 0, staff: 1 });
    tx.create(db.collection('platformAuditLogs').doc(), audit(actor, 'academy.created', data.academyId));
  });
  return { academyId: data.academyId };
});
export const platformSetAcademyStatus = onCall(options, async request => {
  const actor = await operator(request.auth?.uid);
  const academyId = input(() => id(request.data.academyId));
  const status = request.data.status;
  if (!['active', 'suspended'].includes(status)) throw new HttpsError('invalid-argument', 'Statut invalide');
  const batch = db.batch();
  batch.update(db.doc(`academies/${academyId}`), { status, updatedAt: FieldValue.serverTimestamp() });
  batch.create(db.collection('platformAuditLogs').doc(), audit(actor, 'academy.status_changed', academyId, { status }));
  await batch.commit();
  return { academyId, status };
});
export const platformActivateSubscription = onCall(options, async request => {
  const actor = await operator(request.auth?.uid);
  const academyId = input(() => id(request.data.academyId));
  const planId = input(() => id(request.data.planId));
  const requestId = input(() => id(request.data.requestId));
  const durationDays = input(() => positiveInteger(request.data.durationDays, 'Durée'));
  if (durationDays > 3660) throw new HttpsError('invalid-argument', 'Durée trop longue');
  const note = input(() => text(request.data.note, 'Motif', 500));
  await db.runTransaction(async tx => {
    const operationRef = db.doc(`subscriptionOperations/${requestId}`);
    const operation = await tx.get(operationRef);
    if (operation.exists) {
      if (operation.get('academyId') !== academyId || operation.get('planId') !== planId || operation.get('durationDays') !== durationDays) throw new HttpsError('already-exists', 'Référence déjà utilisée pour une autre opération');
      return;
    }
    const academy = await tx.get(db.doc(`academies/${academyId}`));
    const plan = await tx.get(db.doc(`plans/${planId}`));
    const previous = await tx.get(db.doc(`academySubscriptions/${academyId}`));
    const usage = await tx.get(db.doc(`academies/${academyId}/usage/current`));
    if (!academy.exists || plan.get('active') !== true) throw new HttpsError('failed-precondition', 'Académie ou forfait indisponible');
    if ((usage.get('players') ?? 0) > plan.get('maxPlayers') || (usage.get('staff') ?? 0) > plan.get('maxStaff')) throw new HttpsError('failed-precondition', 'Le forfait est inférieur à l’utilisation actuelle');
    const start = Math.max(Date.now(), previous.get('endsAt')?.toMillis?.() ?? 0);
    tx.create(operationRef, { academyId, planId, durationDays, actor, createdAt: FieldValue.serverTimestamp() });
    tx.set(db.doc(`academySubscriptions/${academyId}`), { planId, planName: plan.get('name'), maxPlayers: plan.get('maxPlayers'), maxStaff: plan.get('maxStaff'), status: 'active', endsAt: Timestamp.fromMillis(start + durationDays * 86400000), updatedAt: FieldValue.serverTimestamp(), updatedBy: actor });
    tx.create(db.collection('platformAuditLogs').doc(), audit(actor, 'subscription.activated', academyId, { planId, durationDays, note }));
  });
  return { academyId };
});
// Tenant writes always resolve references beneath the authenticated academy.
export const academyCreatePlayer = onCall(options, async request => {
  const uid = signedIn(request.auth?.uid);
  const academyId = input(() => id(request.data.academyId));
  const name = input(() => text(request.data.name, 'Nom du joueur'));
  const ref = db.collection(`academies/${academyId}/players`).doc();
  await db.runTransaction(async tx => {
    const academy = await tx.get(db.doc(`academies/${academyId}`));
    const member = await tx.get(db.doc(`academies/${academyId}/members/${uid}`));
    const subscription = await tx.get(db.doc(`academySubscriptions/${academyId}`));
    const usageRef = db.doc(`academies/${academyId}/usage/current`);
    const usage = await tx.get(usageRef);
    if (academy.get('status') !== 'active' || member.get('status') !== 'active' || !['owner', 'manager'].includes(member.get('role'))) throw new HttpsError('permission-denied', 'Académie non autorisée');
    if (!subscriptionIsActive(subscription.data(), Date.now())) throw new HttpsError('failed-precondition', 'Abonnement expiré ou inactif');
    const count = usage.get('players') ?? 0;
    if (count >= subscription.get('maxPlayers')) throw new HttpsError('resource-exhausted', 'Limite de joueurs atteinte');
    tx.create(ref, { academyId, name, status: 'active', createdAt: FieldValue.serverTimestamp(), createdBy: uid });
    tx.set(usageRef, { players: count + 1 }, { merge: true });
    tx.create(db.collection(`academies/${academyId}/auditLogs`).doc(), audit(uid, 'player.created', ref.id));
  });
  return { playerId: ref.id };
});

async function setAcademyMember(actor: string, data: Record<string, unknown>, platform: boolean) {
  const academyId = input(() => id(data.academyId));
  const email = input(() => text(data.email, 'Email', 254).toLowerCase());
  const role = data.role;
  const status = data.status;
  if (typeof role !== 'string' || !['manager', 'coach', 'parent', 'student'].includes(role)) throw new HttpsError('invalid-argument', 'Rôle invalide');
  if (typeof status !== 'string' || !['active', 'suspended'].includes(status)) throw new HttpsError('invalid-argument', 'Statut invalide');
  // Check scope before looking up another user's identity.
  if (!platform) {
    const membership = await db.doc(`academies/${academyId}/members/${actor}`).get();
    if (membership.get('role') !== 'owner' || membership.get('status') !== 'active') throw new HttpsError('permission-denied', 'Propriétaire de cette académie requis');
  }
  let user;
  try { user = await getAuth().getUserByEmail(email); }
  catch (error) {
    if ((error as { code?: string }).code === 'auth/user-not-found') throw new HttpsError('not-found', 'Ce compte doit d’abord être créé dans Authentication SportA.');
    throw error;
  }
  if (user.disabled && status === 'active') throw new HttpsError('failed-precondition', 'Compte utilisateur désactivé');
  const memberRef = db.doc(`academies/${academyId}/members/${user.uid}`);
  const staffRoles = ['owner', 'manager', 'coach'];
  await db.runTransaction(async tx => {
    const academy = await tx.get(db.doc(`academies/${academyId}`));
    const actorMembership = await tx.get(db.doc(`academies/${academyId}/members/${actor}`));
    const current = await tx.get(memberRef);
    const subscription = await tx.get(db.doc(`academySubscriptions/${academyId}`));
    const usageRef = db.doc(`academies/${academyId}/usage/current`);
    const usage = await tx.get(usageRef);
    if (!academy.exists) throw new HttpsError('not-found', 'Académie introuvable');
    if (!platform && (academy.get('status') !== 'active' || actorMembership.get('status') !== 'active' || actorMembership.get('role') !== 'owner')) throw new HttpsError('permission-denied', 'Académie non autorisée');
    if (academy.get('ownerUid') === user.uid || current.get('role') === 'owner') throw new HttpsError('failed-precondition', 'Le propriétaire ne peut pas être modifié par cette opération.');
    const oldStaff = current.get('status') === 'active' && staffRoles.includes(current.get('role')) ? 1 : 0;
    const newStaff = status === 'active' && staffRoles.includes(role) ? 1 : 0;
    const activates = status === 'active' && (current.get('status') !== 'active' || current.get('role') !== role);
    if (activates && (!subscriptionIsActive(subscription.data(), Date.now()) || academy.get('status') !== 'active')) throw new HttpsError('failed-precondition', 'Académie ou abonnement inactif');
    const count = usage.get('staff');
    if (!Number.isSafeInteger(count) || count < 1) throw new HttpsError('failed-precondition', 'Compteur équipe indisponible');
    const nextCount = count - oldStaff + newStaff;
    if (newStaff > oldStaff && (!Number.isSafeInteger(subscription.get('maxStaff')) || nextCount > subscription.get('maxStaff'))) throw new HttpsError('resource-exhausted', 'Limite de membres d’équipe atteinte');
    tx.set(memberRef, { uid: user.uid, email, displayName: user.displayName ?? '', role, status, updatedAt: FieldValue.serverTimestamp(), updatedBy: actor });
    const link = db.doc(`users/${user.uid}/memberships/${academyId}`);
    if (status === 'active') tx.set(link, { academyId, name: academy.get('name'), role });
    else tx.delete(link);
    tx.update(usageRef, { staff: nextCount });
    tx.create(db.collection(`academies/${academyId}/auditLogs`).doc(), audit(actor, 'member.updated', user.uid, { role, status }));
    if (platform) tx.create(db.collection('platformAuditLogs').doc(), audit(actor, 'academy.member_updated', academyId, { uid: user.uid, role, status }));
  });
  return { academyId, uid: user.uid, role, status };
}
export const academySetMember = onCall(options, async request => setAcademyMember(signedIn(request.auth?.uid), request.data, false));
export const platformSetMember = onCall(options, async request => setAcademyMember(await operator(request.auth?.uid), request.data, true));
