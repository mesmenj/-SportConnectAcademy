import { randomBytes, randomUUID } from 'node:crypto';
import { getApps, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { FieldValue, Timestamp, getFirestore } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { ROLE_PERMISSIONS, parseIds, parseRole, parseString, requirePermission } from './authorization.js';
import { SESSION_TYPES, adjustPlayerCourses, attendanceCourseDelta, currency as parseCurrency, scheduledBookingRejectionEffect, sessionType, updatePlayerPackage as calculatePlayerPackage } from './domain.js';
import { deliveryId } from './notifications.js';
import { queueBookingNotification, queueEvent } from './notifications/outbox.js';

if (!getApps().length) initializeApp();
const db = getFirestore();
// Temporary development setting until App Check is configured in every client.
// Firebase Authentication, RBAC and academy scoping remain mandatory.
const callableOptions = { region: 'europe-west1', enforceAppCheck: false } as const;
const emailCallableOptions = callableOptions;

function audit(actorId: string, action: string, targetType: string, targetId: string, details: Record<string, unknown> = {}) {
  return db.collection('auditLogs').add({ actorId, action, targetType, targetId, details, createdAt: FieldValue.serverTimestamp() });
}

export const createAdministrator = onCall(callableOptions, async request => {
  const actor = await requirePermission(request.auth?.uid, 'admins.manage');
  const email = parseString(request.data?.email, 'email').toLowerCase();
  const displayName = parseString(request.data?.displayName, 'displayName');
  const role = parseRole(request.data?.role);
  const academyIds = parseIds(request.data?.academyIds ?? [], 'academyIds');
  if (!/^\S+@\S+\.\S+$/.test(email)) throw new HttpsError('invalid-argument', 'E-mail invalide.');
  if (role === 'root') throw new HttpsError('permission-denied', 'Un compte root ne peut pas être créé depuis l’application.');
  if (actor.role !== 'root' && role === 'admin') throw new HttpsError('permission-denied', 'Seul le root peut créer un administrateur global.');

  let user;
  let resetLink = '';
  const emailEventId = randomUUID();
  let commitAttempted = false;
  try {
    user = await getAuth().createUser({ email, displayName, password: randomBytes(24).toString('base64url'), disabled: false });
    resetLink = await getAuth().generatePasswordResetLink(email);
    const batch = db.batch();
    batch.create(db.collection('users').doc(user.uid), {
      email, displayName, role, status: 'active', academyIds,
      permissions: ROLE_PERMISSIONS[role], createdBy: actor.uid,
      createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
    });
    queueEvent(batch, { kind: 'invitation', audience: 'administrator', userId: user.uid, academyId: academyIds[0] ?? null, recipientEmail: email, recipientName: displayName, actionUrl: resetLink, language: 'en', requestedBy: actor.uid }, emailEventId);
    batch.create(db.collection('auditLogs').doc(), { actorId: actor.uid, action: 'administrator.created', targetType: 'user', targetId: user.uid, details: { email, role, academyIds }, createdAt: FieldValue.serverTimestamp() });
    commitAttempted = true;
    await batch.commit();
  } catch (error) {
    // A lost commit acknowledgement does not mean Firestore rolled back.
    // Never delete Auth after an ambiguous commit: that could orphan a valid profile.
    const committed = commitAttempted && user
      ? await db.collection('notificationEvents').doc(emailEventId).get().then(event => event.exists).catch(() => false)
      : false;
    if (!committed) {
      if (user && !commitAttempted) await getAuth().deleteUser(user.uid).catch(() => undefined);
      if (commitAttempted) console.error('Invitation creation requires reconciliation', { userId: user?.uid, eventId: emailEventId });
      throw error;
    }
  }
  return { uid: user!.uid, email, resetLink, emailStatus: 'queued', emailEventId, emailDeliveryId: deliveryId(emailEventId, 'administrator_invitation', email) };
});

export const updateAdministratorAccess = onCall(callableOptions, async request => {
  const actor = await requirePermission(request.auth?.uid, 'admins.manage');
  const uid = parseString(request.data?.uid, 'uid', 128);
  const role = parseRole(request.data?.role);
  const status = request.data?.status;
  const academyIds = parseIds(request.data?.academyIds ?? [], 'academyIds');
  if (!['active', 'suspended'].includes(status)) throw new HttpsError('invalid-argument', 'Statut invalide.');
  const targetRef = db.collection('users').doc(uid); const target = await targetRef.get();
  if (!target.exists) throw new HttpsError('not-found', 'Administrateur introuvable.');
  if (target.get('role') === 'root' || role === 'root') throw new HttpsError('permission-denied', 'Le rôle root est protégé.');
  if (actor.role !== 'root' && (target.get('role') === 'admin' || role === 'admin')) throw new HttpsError('permission-denied', 'Seul le root peut gérer un administrateur global.');
  if (uid === actor.uid && status === 'suspended') throw new HttpsError('failed-precondition', 'Vous ne pouvez pas suspendre votre propre compte.');
  await targetRef.update({ role, status, academyIds, permissions: ROLE_PERMISSIONS[role], updatedBy: actor.uid, updatedAt: FieldValue.serverTimestamp() });
  await getAuth().updateUser(uid, { disabled: status === 'suspended' });
  await audit(actor.uid, 'administrator.access_updated', 'user', uid, { role, status, academyIds });
  return { uid, role, status, academyIds };
});

export const createAcademy = onCall(callableOptions, async request => {
  const actor = await requirePermission(request.auth?.uid, 'academies.manage');
  const name = parseString(request.data?.name, 'name');
  const city = parseString(request.data?.city, 'city');
  const country = parseString(request.data?.country ?? 'Cameroun', 'country');
  const ref = db.collection('academies').doc();
  await ref.create({ name, city, country, status: 'active', createdBy: actor.uid, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() });
  await audit(actor.uid, 'academy.created', 'academy', ref.id, { name, city });
  return { id: ref.id, name, city, country };
});

export const updateAcademyBranding = onCall(callableOptions, async request => {
  const academyId = parseString(request.data?.academyId, 'academyId', 100);
  const actor = await requirePermission(request.auth?.uid, 'academies.manage', academyId);
  const academyRef = db.collection('academies').doc(academyId);
  if (!(await academyRef.get()).exists) throw new HttpsError('not-found', 'Académie introuvable.');
  const logoDataUrl = parseString(request.data?.logoDataUrl, 'logoDataUrl', 3_000_000);
  const match = /^data:(image\/(?:png|jpeg|webp));base64,([A-Za-z0-9+/=]+)$/.exec(logoDataUrl);
  if (!match) throw new HttpsError('invalid-argument', 'Le logo doit être une image PNG, JPEG ou WebP.');
  const bytes = Buffer.from(match[2]!, 'base64');
  if (!bytes.length || bytes.length > 2_000_000) throw new HttpsError('invalid-argument', 'Le logo ne doit pas dépasser 2 Mo.');
  const contentType = match[1]!;
  const extension = contentType === 'image/png' ? 'png' : contentType === 'image/webp' ? 'webp' : 'jpg';
  const token = randomBytes(24).toString('hex');
  const bucket = getStorage().bucket();
  const path = `academy-branding/${academyId}/logo.${extension}`;
  await bucket.file(path).save(bytes, { resumable: false, contentType, metadata: { metadata: { firebaseStorageDownloadTokens: token }, cacheControl: 'public,max-age=3600' } });
  const logoUrl = `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(path)}?alt=media&token=${token}`;
  await academyRef.update({ logoUrl, brandingUpdatedBy: actor.uid, brandingUpdatedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() });
  await audit(actor.uid, 'academy.branding_updated', 'academy', academyId, { logoUrl });
  return { academyId, logoUrl };
});

export const updateValidatedRevenue = onCall(callableOptions, async request => {
  const actor = await requirePermission(request.auth?.uid, 'admins.manage');
  if (actor.role !== 'root') throw new HttpsError('permission-denied', 'Seul l’administrateur root peut modifier le montant total.');
  const amount = Number(request.data?.amount);
  if (!Number.isFinite(amount) || amount < 0 || amount > 1_000_000_000) throw new HttpsError('invalid-argument', 'Montant invalide.');
  let currency: string;
  try { currency = parseCurrency(request.data?.currency); } catch { throw new HttpsError('invalid-argument', 'Devise invalide.'); }
  const settingsRef = db.collection('systemSettings').doc('dashboard');
  await db.runTransaction(async transaction => {
    const settings = await transaction.get(settingsRef);
    transaction.set(settingsRef, { validatedRevenueAmount: amount, validatedRevenueCurrency: currency, validatedRevenueCashBaseline: settings.get('confirmedCashTotals') ?? {}, validatedRevenueUpdatedBy: actor.uid, validatedRevenueUpdatedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  });
  await audit(actor.uid, 'dashboard.validated_revenue_updated', 'systemSettings', 'dashboard', { amount, currency });
  return { amount, currency };
});

export const createStadium = onCall(callableOptions, async request => {
  const academyId = parseString(request.data?.academyId, 'academyId', 100);
  const actor = await requirePermission(request.auth?.uid, 'stadiums.manage', academyId);
  const name = parseString(request.data?.name, 'name');
  const address = parseString(request.data?.address, 'address', 300);
  const courtCount = Number(request.data?.courtCount);
  if (!Number.isInteger(courtCount) || courtCount < 1 || courtCount > 100) throw new HttpsError('invalid-argument', 'Nombre de terrains invalide.');
  const ref = db.collection('stadiums').doc();
  await ref.create({ academyId, name, address, courtCount, status: 'active', createdBy: actor.uid, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() });
  await audit(actor.uid, 'stadium.created', 'stadium', ref.id, { academyId, name, courtCount });
  return { id: ref.id, academyId, name, address, courtCount };
});

export const createCoach = onCall(emailCallableOptions, async request => {
  const academyId = parseString(request.data?.academyId, 'academyId', 100);
  const actor = await requirePermission(request.auth?.uid, 'coaches.manage', academyId);
  const displayName = parseString(request.data?.displayName, 'displayName');
  const email = parseString(request.data?.email, 'email').toLowerCase();
  const specialties = parseIds(request.data?.specialties ?? [], 'specialties');
  if (!/^\S+@\S+\.\S+$/.test(email)) throw new HttpsError('invalid-argument', 'E-mail invalide.');
  let user;
  let resetLink = '';
  const emailEventId = randomUUID();
  let commitAttempted = false;
  try {
    user = await getAuth().createUser({
      email,
      displayName,
      password: randomBytes(24).toString('base64url'),
      disabled: false,
    });
    resetLink = await getAuth().generatePasswordResetLink(email);
    const batch = db.batch();
    batch.create(db.collection('users').doc(user.uid), {
      email, displayName, role: 'coach', status: 'active', academyIds: [academyId],
      permissions: [], coachId: user.uid, preferredLanguage: 'en', createdBy: actor.uid,
      createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
    });
    batch.create(db.collection('coaches').doc(user.uid), {
      uid: user.uid, academyId, displayName, email, specialties, preferredLanguage: 'en', status: 'active',
      createdBy: actor.uid, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
    });
    queueEvent(batch, { kind: 'invitation', audience: 'coach', userId: user.uid, academyId, recipientEmail: email, recipientName: displayName, actionUrl: resetLink, language: 'en', requestedBy: actor.uid }, emailEventId);
    batch.create(db.collection('auditLogs').doc(), { actorId: actor.uid, action: 'coach.created', targetType: 'coach', targetId: user.uid, details: { academyId, email }, createdAt: FieldValue.serverTimestamp() });
    commitAttempted = true;
    await batch.commit();
  } catch (error) {
    // A lost commit acknowledgement does not mean Firestore rolled back.
    // Never delete Auth after an ambiguous commit: that could orphan a valid profile.
    const committed = commitAttempted && user
      ? await db.collection('notificationEvents').doc(emailEventId).get().then(event => event.exists).catch(() => false)
      : false;
    if (!committed) {
      if (user && !commitAttempted) await getAuth().deleteUser(user.uid).catch(() => undefined);
      if (commitAttempted) console.error('Invitation creation requires reconciliation', { userId: user?.uid, eventId: emailEventId });
      if ((error as { code?: string }).code === 'auth/email-already-exists') {
        throw new HttpsError('already-exists', 'Cette adresse e-mail possède déjà un compte.');
      }
      throw error;
    }
  }
  return { id: user!.uid, uid: user!.uid, academyId, displayName, email, specialties, resetLink, emailStatus: 'queued', emailEventId, emailDeliveryId: deliveryId(emailEventId, 'coach_invitation', email) };
});

export const resendCoachPasswordLink = onCall(emailCallableOptions, async request => {
  const coachId = parseString(request.data?.coachId, 'coachId', 128);
  const coach = await db.collection('coaches').doc(coachId).get();
  if (!coach.exists) throw new HttpsError('not-found', 'Coach introuvable.');
  const academyId = parseString(coach.get('academyId'), 'academyId', 100);
  const actor = await requirePermission(request.auth?.uid, 'coaches.manage', academyId);
  const email = parseString(coach.get('email'), 'email').toLowerCase();
  try {
    const user = await getAuth().getUser(coachId);
    if (user.disabled) throw new HttpsError('failed-precondition', 'Le compte de ce coach est désactivé.');
    if (user.email?.toLowerCase() !== email) throw new HttpsError('failed-precondition', 'L’adresse e-mail du coach est incohérente.');
    const resetLink = await getAuth().generatePasswordResetLink(email);
    return db.runTransaction(async transaction => {
      const current = await transaction.get(coach.ref);
      if (!current.exists || current.get('status') !== 'active') throw new HttpsError('failed-precondition', 'Le compte de ce coach est désactivé.');
      const previousId = current.get('lastInvitationEventId');
      if (previousId && Date.now() - (current.get('lastInvitationRequestedAt')?.toMillis() ?? 0) < 60000) {
        const previous = await transaction.get(db.collection('notificationEvents').doc(previousId));
        if (previous.exists && previous.get('actionUrl')) return { coachId, email, resetLink: previous.get('actionUrl'), emailStatus: 'queued', emailEventId: previousId, emailDeliveryId: deliveryId(previousId, 'coach_invitation', email) };
        throw new HttpsError('resource-exhausted', 'Patientez une minute avant de demander une nouvelle invitation.');
      }
      const eventId = queueEvent(transaction, { kind: 'invitation', audience: 'coach', userId: coachId, academyId, recipientEmail: email, recipientName: String(current.get('displayName') ?? user.displayName ?? 'Coach'), actionUrl: resetLink, language: current.get('preferredLanguage') === 'fr' ? 'fr' : 'en', requestedBy: actor.uid });
      transaction.update(coach.ref, { lastInvitationEventId: eventId, lastInvitationRequestedAt: FieldValue.serverTimestamp() });
      transaction.create(db.collection('auditLogs').doc(), { actorId: actor.uid, action: 'coach.password_link_regenerated', targetType: 'coach', targetId: coachId, details: { academyId, email }, createdAt: FieldValue.serverTimestamp() });
      return { coachId, email, resetLink, emailStatus: 'queued', emailEventId: eventId, emailDeliveryId: deliveryId(eventId, 'coach_invitation', email) };
    });
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    if ((error as { code?: string }).code === 'auth/user-not-found') throw new HttpsError('not-found', 'Le compte Firebase du coach est introuvable.');
    throw error;
  }
});

export const deleteCoach = onCall(callableOptions, async request => {
  const coachId = parseString(request.data?.coachId, 'coachId', 128);
  const coachRef = db.collection('coaches').doc(coachId);
  const coach = await coachRef.get();
  if (!coach.exists) throw new HttpsError('not-found', 'Coach introuvable.');
  const academyId = parseString(coach.get('academyId'), 'academyId', 100);
  const actor = await requirePermission(request.auth?.uid, 'coaches.manage', academyId);
  const assignedSessions = await db.collection('sessions').where('coachId', '==', coachId).get();
  const now = Timestamp.now().toMillis();
  const hasFutureSession = assignedSessions.docs.some(session => {
    const startsAt = session.get('startsAt');
    return startsAt instanceof Timestamp && startsAt.toMillis() >= now && session.get('status') !== 'cancelled';
  });
  if (hasFutureSession) throw new HttpsError('failed-precondition', 'Ce coach possède encore une séance future. Réattribuez ou annulez ses séances avant de le supprimer.');
  try {
    await getAuth().deleteUser(coachId);
  } catch (error) {
    if ((error as { code?: string }).code !== 'auth/user-not-found') throw error;
  }
  const batch = db.batch();
  batch.delete(coachRef);
  batch.delete(db.collection('users').doc(coachId));
  batch.set(db.collection('auditLogs').doc(), { actorId: actor.uid, action: 'coach.deleted', targetType: 'coach', targetId: coachId, details: { academyId, email: coach.get('email') ?? null }, createdAt: FieldValue.serverTimestamp() });
  await batch.commit();
  return { coachId, deleted: true };
});

async function uploadTournamentImage(tournamentId: string, imageDataUrl: unknown): Promise<string> {
  if (typeof imageDataUrl !== 'string' || imageDataUrl.length > 3_000_000) throw new HttpsError('invalid-argument', 'Image de tournoi invalide.');
  const match = /^data:(image\/(?:png|jpeg|webp));base64,([A-Za-z0-9+/=]+)$/.exec(imageDataUrl);
  if (!match) throw new HttpsError('invalid-argument', 'L’image doit être au format PNG, JPEG ou WebP.');
  const bytes = Buffer.from(match[2]!, 'base64');
  if (!bytes.length || bytes.length > 2_000_000) throw new HttpsError('invalid-argument', 'L’image ne doit pas dépasser 2 Mo.');
  const contentType = match[1]!;
  const extension = contentType === 'image/png' ? 'png' : contentType === 'image/webp' ? 'webp' : 'jpg';
  const token = randomBytes(24).toString('hex');
  const bucket = getStorage().bucket();
  const path = `tournaments/${tournamentId}/cover.${extension}`;
  await bucket.file(path).save(bytes, { resumable: false, contentType, metadata: { metadata: { firebaseStorageDownloadTokens: token }, cacheControl: 'public,max-age=3600' } });
  return `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(path)}?alt=media&token=${token}`;
}

function parseTournamentFields(data: Record<string, unknown>, allowPastDate = false) {
  const name = parseString(data.name, 'name', 150);
  const venue = parseString(data.venue, 'venue', 200);
  const category = parseString(data.category, 'category', 100);
  const description = typeof data.description === 'string' ? data.description.trim() : '';
  if (description.length > 1000) throw new HttpsError('invalid-argument', 'Description trop longue.');
  const startsAtDate = new Date(data.startsAt as string);
  if (!Number.isFinite(startsAtDate.getTime()) || (!allowPastDate && startsAtDate.getTime() < Date.now() - 300_000)) throw new HttpsError('invalid-argument', 'Date du tournoi invalide.');
  const capacity = Number(data.capacity);
  if (!Number.isInteger(capacity) || capacity < 2 || capacity > 10000) throw new HttpsError('invalid-argument', 'La capacité doit être comprise entre 2 et 10000 joueurs.');
  return { name, venue, category, description, startsAtDate, capacity };
}

export const createTournament = onCall(callableOptions, async request => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Authentification requise.');
  const { name, venue, category, description, startsAtDate, capacity } = parseTournamentFields(request.data ?? {});
  const academyId = typeof request.data?.academyId === 'string' && request.data.academyId.trim() ? parseString(request.data.academyId, 'academyId', 100) : null;
  if (!academyId) throw new HttpsError('invalid-argument', 'Choisissez une académie.');
  const actor = await requirePermission(uid, 'sessions.manage', academyId);
  if (!(await db.collection('academies').doc(academyId).get()).exists) throw new HttpsError('not-found', 'Académie introuvable.');
  const ref = db.collection('tournaments').doc();
  let imageUrl: string | null = null;
  const imageDataUrl = request.data?.imageDataUrl;
  if (imageDataUrl !== undefined && imageDataUrl !== null && imageDataUrl !== '') {
    imageUrl = await uploadTournamentImage(ref.id, imageDataUrl);
  }
  await ref.create({
    name, venue, category, description, startsAt: Timestamp.fromDate(startsAtDate), capacity,
    registeredCount: 0, academyId, imageUrl, status: 'open', isDelete: false, createdBy: uid,
    creatorRole: actor.role, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
  });
  await audit(uid, 'tournament.created', 'tournament', ref.id, { academyId, name, startsAt: startsAtDate.toISOString(), capacity, hasImage: Boolean(imageUrl) });
  return { id: ref.id, name, imageUrl, status: 'open' };
});

export const updateTournament = onCall(callableOptions, async request => {
  const tournamentId = parseString(request.data?.tournamentId, 'tournamentId', 128);
  const ref = db.collection('tournaments').doc(tournamentId);
  const tournament = await ref.get();
  if (!tournament.exists || tournament.get('isDelete') === true) throw new HttpsError('not-found', 'Tournoi introuvable.');
  const academyId = parseString(tournament.get('academyId'), 'academyId', 100);
  const actor = await requirePermission(request.auth?.uid, 'sessions.manage', academyId);
  const fields = parseTournamentFields(request.data ?? {}, true);
  const registeredCount = Number(tournament.get('registeredCount') ?? 0);
  if (fields.capacity < registeredCount) throw new HttpsError('failed-precondition', `La capacité ne peut pas être inférieure aux ${registeredCount} joueurs déjà inscrits.`);
  let imageUrl = tournament.get('imageUrl') ?? null;
  if (request.data?.imageDataUrl) imageUrl = await uploadTournamentImage(tournamentId, request.data.imageDataUrl);
  await ref.update({
    name: fields.name, venue: fields.venue, category: fields.category, description: fields.description,
    startsAt: Timestamp.fromDate(fields.startsAtDate), capacity: fields.capacity, imageUrl,
    updatedBy: actor.uid, updatedAt: FieldValue.serverTimestamp(),
  });
  await audit(actor.uid, 'tournament.updated', 'tournament', tournamentId, { academyId, name: fields.name, startsAt: fields.startsAtDate.toISOString(), capacity: fields.capacity, imageChanged: Boolean(request.data?.imageDataUrl) });
  return { tournamentId, updated: true, imageUrl };
});

export const softDeleteTournament = onCall(callableOptions, async request => {
  const tournamentId = parseString(request.data?.tournamentId, 'tournamentId', 128);
  const ref = db.collection('tournaments').doc(tournamentId);
  const tournament = await ref.get();
  if (!tournament.exists || tournament.get('isDelete') === true) throw new HttpsError('not-found', 'Tournoi introuvable.');
  const academyId = parseString(tournament.get('academyId'), 'academyId', 100);
  const actor = await requirePermission(request.auth?.uid, 'sessions.manage', academyId);
  await ref.update({ isDelete: true, status: 'deleted', deletedBy: actor.uid, deletedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() });
  await audit(actor.uid, 'tournament.deleted', 'tournament', tournamentId, { academyId, name: tournament.get('name') ?? null });
  return { tournamentId, isDelete: true };
});

export const createCommunity = onCall(callableOptions, async request => {
  const academyId = parseString(request.data?.academyId, 'academyId', 100);
  const name = parseString(request.data?.name, 'name');
  const description = typeof request.data?.description === 'string' ? request.data.description.trim() : '';
  if (description.length > 500) throw new HttpsError('invalid-argument', 'Description trop longue.');
  const actor = await requirePermission(request.auth?.uid, 'sessions.manage', academyId);
  const duplicate = await db.collection('communities').where('academyId', '==', academyId).where('name', '==', name).get();
  if (duplicate.docs.some(document => document.get('isDelete') !== true)) throw new HttpsError('already-exists', 'Une communauté porte déjà ce nom.');
  const ref = db.collection('communities').doc();
  await ref.create({ academyId, name, description, active: true, createdBy: actor.uid, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() });
  await audit(actor.uid, 'community.created', 'community', ref.id, { academyId, name });
  return { id: ref.id, academyId, name };
});

export const updateCommunity = onCall(callableOptions, async request => {
  const communityId = parseString(request.data?.communityId, 'communityId', 120);
  const name = parseString(request.data?.name, 'name');
  const description = typeof request.data?.description === 'string' ? request.data.description.trim().slice(0, 1000) : '';
  const active = request.data?.active;
  if (typeof active !== 'boolean') throw new HttpsError('invalid-argument', 'Visibilité invalide.');
  const ref = db.collection('communities').doc(communityId);
  const community = await ref.get();
  if (!community.exists) throw new HttpsError('not-found', 'Communauté introuvable.');
  const academyId = community.get('academyId');
  const actor = await requirePermission(request.auth?.uid, 'sessions.manage', academyId);
  const duplicate = await db.collection('communities').where('academyId', '==', academyId).where('name', '==', name).get();
  if (duplicate.docs.some(document => document.id !== communityId && document.get('isDelete') !== true)) throw new HttpsError('already-exists', 'Une communauté porte déjà ce nom.');
  await ref.update({ name, description, active, updatedBy: actor.uid, updatedAt: FieldValue.serverTimestamp() });
  if (name !== community.get('name')) {
    const players = await db.collection('players').where('communityId', '==', communityId).get();
    const writer = db.bulkWriter();
    players.docs.forEach(player => writer.update(player.ref, { communityName: name, updatedAt: FieldValue.serverTimestamp() }));
    await writer.close();
  }
  await audit(actor.uid, 'community.updated', 'community', communityId, { academyId, name, active });
  return { id: communityId, academyId, name, description, active };
});

export const createCommunityCourse = onCall(callableOptions, async request => {
  const communityId = parseString(request.data?.communityId, 'communityId', 120);
  const name = parseString(request.data?.name, 'name');
  const description = typeof request.data?.description === 'string' ? request.data.description.trim() : '';
  if (description.length > 500) throw new HttpsError('invalid-argument', 'Description trop longue.');
  const community = await db.collection('communities').doc(communityId).get();
  if (!community.exists || community.get('active') !== true || community.get('isDelete') === true) throw new HttpsError('failed-precondition', 'Communauté absente ou inactive.');
  const academyId = community.get('academyId');
  const actor = await requirePermission(request.auth?.uid, 'sessions.manage', academyId);
  const duplicate = await db.collection('communityCourses').where('communityId', '==', communityId).where('name', '==', name).get();
  if (duplicate.docs.some(document => document.get('isDelete') !== true)) throw new HttpsError('already-exists', 'Un cours de cette communauté porte déjà ce nom.');
  const ref = db.collection('communityCourses').doc();
  await ref.create({ academyId, communityId, name, description, active: true, createdBy: actor.uid, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() });
  await audit(actor.uid, 'community_course.created', 'communityCourse', ref.id, { academyId, communityId, name });
  return { id: ref.id, academyId, communityId, name };
});

export const updateCommunityCourse = onCall(callableOptions, async request => {
  const courseId = parseString(request.data?.courseId, 'courseId', 120);
  const name = parseString(request.data?.name, 'name');
  const description = typeof request.data?.description === 'string' ? request.data.description.trim() : '';
  if (description.length > 500) throw new HttpsError('invalid-argument', 'Description trop longue.');
  const ref = db.collection('communityCourses').doc(courseId);
  const course = await ref.get();
  if (!course.exists) throw new HttpsError('not-found', 'Cours communautaire introuvable.');
  const academyId = course.get('academyId');
  const communityId = course.get('communityId');
  const actor = await requirePermission(request.auth?.uid, 'sessions.manage', academyId);
  const duplicate = await db.collection('communityCourses').where('communityId', '==', communityId).where('name', '==', name).get();
  if (duplicate.docs.some(document => document.id !== courseId && document.get('isDelete') !== true)) throw new HttpsError('already-exists', 'Un cours de cette communauté porte déjà ce nom.');
  await ref.update({ name, description, updatedBy: actor.uid, updatedAt: FieldValue.serverTimestamp() });
  await audit(actor.uid, 'community_course.updated', 'communityCourse', courseId, { academyId, communityId, name });
  return { id: courseId, academyId, communityId, name, description };
});

export const softDeleteCommunity = onCall(callableOptions, async request => {
  const communityId = parseString(request.data?.communityId, 'communityId', 120);
  const ref = db.collection('communities').doc(communityId);
  const community = await ref.get();
  if (!community.exists) throw new HttpsError('not-found', 'Communauté introuvable.');
  const academyId = community.get('academyId');
  const actor = await requirePermission(request.auth?.uid, 'sessions.manage', academyId);
  if (community.get('isDelete') === true) return { communityId, isDelete: true, alreadyDeleted: true };
  const courses = await db.collection('communityCourses').where('communityId', '==', communityId).get();
  const batch = db.batch();
  batch.update(ref, { isDelete: true, active: false, deletedBy: actor.uid, deletedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() });
  courses.docs.forEach(course => batch.update(course.ref, { isDelete: true, active: false, deletedBy: actor.uid, deletedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() }));
  await batch.commit();
  await audit(actor.uid, 'community.soft_deleted', 'community', communityId, { academyId, deletedCourseCount: courses.size });
  return { communityId, isDelete: true, deletedCourseCount: courses.size, alreadyDeleted: false };
});

export const softDeleteCommunityCourse = onCall(callableOptions, async request => {
  const courseId = parseString(request.data?.courseId, 'courseId', 120);
  const ref = db.collection('communityCourses').doc(courseId);
  const course = await ref.get();
  if (!course.exists) throw new HttpsError('not-found', 'Cours communautaire introuvable.');
  const academyId = course.get('academyId');
  const actor = await requirePermission(request.auth?.uid, 'sessions.manage', academyId);
  if (course.get('isDelete') === true) return { courseId, isDelete: true, alreadyDeleted: true };
  await ref.update({ isDelete: true, active: false, deletedBy: actor.uid, deletedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() });
  await audit(actor.uid, 'community_course.soft_deleted', 'communityCourse', courseId, { academyId, communityId: course.get('communityId') });
  return { courseId, isDelete: true, alreadyDeleted: false };
});

export const assignPlayerCommunity = onCall(callableOptions, async request => {
  const playerId = parseString(request.data?.playerId, 'playerId', 220);
  const communityId = request.data?.communityId ? parseString(request.data.communityId, 'communityId', 120) : null;
  const playerRef = db.collection('players').doc(playerId);
  const [player, community] = await Promise.all([playerRef.get(), communityId ? db.collection('communities').doc(communityId).get() : Promise.resolve(null)]);
  if (!player.exists) throw new HttpsError('not-found', 'Joueur introuvable.');
  const academyId = player.get('academyId') ?? null;
  const actor = await requirePermission(request.auth?.uid, 'sessions.manage');
  if (community && (!community.exists || community.get('active') !== true)) throw new HttpsError('failed-precondition', 'Communauté absente ou inactive.');
  await playerRef.update({ communityId, communityName: community?.get('name') ?? null, updatedBy: actor.uid, updatedAt: FieldValue.serverTimestamp() });
  await audit(actor.uid, 'player.community_assigned', 'player', playerId, { academyId, communityId });
  return { playerId, communityId };
});

export const createPlayerForUser = onCall(callableOptions, async request => {
  const actor = await requirePermission(request.auth?.uid, 'sessions.manage');
  const firstName = parseString(request.data?.firstName, 'firstName', 80);
  const lastName = parseString(request.data?.lastName, 'lastName', 80);
  const age = Number(request.data?.age);
  const gender = request.data?.gender;
  const sessionConfigurationId = parseString(request.data?.sessionConfigurationId, 'sessionConfigurationId', 220);
  const paymentMethod = request.data?.paymentMethod;
  const userId = request.data?.userId ? parseString(request.data.userId, 'userId', 220) : null;
  if (!Number.isInteger(age) || age < 3 || age > 80) throw new HttpsError('invalid-argument', 'L’âge doit être compris entre 3 et 80 ans.');
  if (!['female', 'male', 'woman', 'man', 'other'].includes(gender)) throw new HttpsError('invalid-argument', 'Sexe invalide.');
  if (!['cash', 'card', 'payment_link', 'bank_transfer'].includes(paymentMethod)) throw new HttpsError('invalid-argument', 'Mode de paiement invalide.');
  const [configuration, user] = await Promise.all([
    db.collection('sessionConfigurations').doc(sessionConfigurationId).get(),
    userId ? db.collection('users').doc(userId).get() : Promise.resolve(null),
  ]);
  if (!configuration.exists || configuration.get('active') !== true) throw new HttpsError('failed-precondition', 'Cette configuration de séance n’est plus disponible.');
  const minAge = Number(configuration.get('minAge'));
  const maximumAge = configuration.get('maximumAge');
  const maxAge = maximumAge === null ? minAge : Number(maximumAge ?? configuration.get('maxAge'));
  if (age < minAge || age > maxAge) throw new HttpsError('failed-precondition', 'Cette configuration de séance ne correspond pas à l’âge du joueur.');
  if (userId && (!user?.exists || !['parent', 'student'].includes(user.get('role')) || user.get('status') !== 'active')) throw new HttpsError('failed-precondition', 'Choisissez un utilisateur parent ou élève actif.');
  const playerRef = db.collection('players').doc();
  const displayName = `${firstName} ${lastName}`;
  const sessionCount = Number(configuration.get('sessionCount')) || 1;
  const awaitsCashConfirmation = paymentMethod === 'cash';
  const batch = db.batch();
  batch.create(playerRef, {
    firstName, lastName, displayName, age, gender,
    sessionConfigurationId, sessionType: configuration.get('type'), activityType: configuration.get('activityType') ?? 'tennis',
    sessionCount, remainingSessions: awaitsCashConfirmation ? 0 : sessionCount,
    paymentAmount: Number(configuration.get('price')), paymentCurrency: configuration.get('currency') ?? 'AED',
    paymentMethod, paymentStatus: awaitsCashConfirmation ? 'cash_pending' : 'payment_pending',
    academyId: null, academyName: null,
    status: awaitsCashConfirmation ? 'pending_cash_confirmation' : 'active',
    createdBy: actor.uid, createdForUserId: userId, assignedUserId: userId,
    createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
  });
  if (userId && user) {
    batch.create(user.ref.collection('players').doc(playerRef.id), { relationship: user.get('role') === 'student' ? 'self' : 'guardian', assignedBy: actor.uid, createdAt: FieldValue.serverTimestamp() });
    batch.create(playerRef.collection('family').doc(userId), {
      userId, displayName: user.get('displayName') ?? user.get('email') ?? 'Responsable', email: user.get('email') ?? null,
      phone: user.get('phone') ?? null, relationship: user.get('role') === 'student' ? 'Élève' : 'Tuteur',
      assignedBy: actor.uid, createdAt: FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();
  await audit(actor.uid, 'player.created_by_admin', 'player', playerRef.id, { userId, sessionConfigurationId, paymentMethod });
  return { playerId: playerRef.id, displayName, userId };
});

export const assignPlayerToUser = onCall(callableOptions, async request => {
  const playerId = parseString(request.data?.playerId, 'playerId', 220);
  const userId = parseString(request.data?.userId, 'userId', 220);
  const playerRef = db.collection('players').doc(playerId);
  const userRef = db.collection('users').doc(userId);
  const preview = await playerRef.get();
  if (!preview.exists) throw new HttpsError('not-found', 'Joueur introuvable.');
  const academyId = preview.get('academyId');
  const actor = await requirePermission(request.auth?.uid, 'sessions.manage', typeof academyId === 'string' && academyId ? academyId : undefined);
  const result = await db.runTransaction(async transaction => {
    const [player, user, existingLinks] = await Promise.all([
      transaction.get(playerRef),
      transaction.get(userRef),
      transaction.get(playerRef.collection('family')),
    ]);
    if (!player.exists) throw new HttpsError('not-found', 'Joueur introuvable.');
    if (!user.exists || !['parent', 'student'].includes(user.get('role')) || user.get('status') !== 'active') throw new HttpsError('failed-precondition', 'Choisissez un utilisateur parent ou élève actif.');
    const assignedUserId = typeof player.get('assignedUserId') === 'string' ? player.get('assignedUserId') : null;
    const existingUserIds = existingLinks.docs.map(document => document.id);
    const currentUserId = assignedUserId ?? existingUserIds[0] ?? null;
    if (currentUserId && currentUserId !== userId) throw new HttpsError('already-exists', 'Ce joueur est déjà attribué à un autre utilisateur.');
    if (existingUserIds.some(existingUserId => existingUserId !== userId)) throw new HttpsError('already-exists', 'Ce joueur possède déjà une attribution. Corrigez ses liaisons existantes avant de continuer.');
    if (currentUserId === userId) {
      if (!assignedUserId) transaction.update(playerRef, { assignedUserId: userId, updatedBy: actor.uid, updatedAt: FieldValue.serverTimestamp() });
      return { alreadyAssigned: true };
    }
    transaction.set(userRef.collection('players').doc(playerId), { relationship: user.get('role') === 'student' ? 'self' : 'guardian', assignedBy: actor.uid, createdAt: FieldValue.serverTimestamp() });
    transaction.set(playerRef.collection('family').doc(userId), {
      userId, displayName: user.get('displayName') ?? user.get('email') ?? 'Responsable', email: user.get('email') ?? null,
      phone: user.get('phone') ?? null, relationship: user.get('role') === 'student' ? 'Élève' : 'Tuteur',
      assignedBy: actor.uid, createdAt: FieldValue.serverTimestamp(),
    });
    transaction.update(playerRef, { assignedUserId: userId, updatedBy: actor.uid, updatedAt: FieldValue.serverTimestamp() });
    return { alreadyAssigned: false };
  });
  if (!result.alreadyAssigned) await audit(actor.uid, 'player.assigned_to_user', 'player', playerId, { userId });
  return { playerId, userId, alreadyAssigned: result.alreadyAssigned };
});

export const submitCoachEvaluation = onCall(callableOptions, async request => {
  const coachUid = request.auth?.uid;
  if (!coachUid) throw new HttpsError('unauthenticated', 'Authentification requise.');
  const bookingId = parseString(request.data?.bookingId, 'bookingId', 220);
  const comment = typeof request.data?.comment === 'string' ? request.data.comment.trim() : '';
  if (comment.length > 1000) throw new HttpsError('invalid-argument', 'Commentaire trop long.');
  const ratings = ['technical', 'tactical', 'physical', 'behavior'].reduce<Record<string, number>>((result, key) => {
    const value = Number(request.data?.ratings?.[key]);
    if (!Number.isInteger(value) || value < 1 || value > 5) {
      throw new HttpsError('invalid-argument', 'Chaque note doit être comprise entre 1 et 5.');
    }
    result[key] = value;
    return result;
  }, {});
  const [coach, booking] = await Promise.all([
    db.collection('users').doc(coachUid).get(),
    db.collection('bookings').doc(bookingId).get(),
  ]);
  if (!coach.exists || coach.get('role') !== 'coach' || coach.get('status') !== 'active') {
    throw new HttpsError('permission-denied', 'Compte coach actif requis.');
  }
  if (!booking.exists || booking.get('coachId') !== coachUid) {
    throw new HttpsError('permission-denied', 'Cette réservation ne vous est pas assignée.');
  }
  if (!['confirmed', 'completed'].includes(booking.get('status'))) {
    throw new HttpsError('failed-precondition', 'La réservation doit être confirmée.');
  }
  const startsAt = booking.get('startsAt');
  if (!(startsAt instanceof Timestamp) || startsAt.toMillis() > Date.now()) {
    throw new HttpsError('failed-precondition', 'La séance doit avoir commencé avant son évaluation.');
  }
  const playerId = parseString(booking.get('playerId'), 'playerId', 220);
  const ref = db.collection('playerEvaluations').doc(bookingId);
  await ref.set({
    bookingId, playerId, coachId: coachUid, academyId: booking.get('academyId') ?? null,
    sessionId: booking.get('sessionId') ?? null,
    playerName: booking.get('playerName') ?? playerId,
    sessionTitle: booking.get('title') ?? booking.get('sessionType') ?? 'Séance',
    startsAt: booking.get('startsAt') ?? null,
    ratings, average: Object.values(ratings).reduce((sum, value) => sum + value, 0) / 4,
    comment, evaluatedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  await audit(coachUid, 'player.evaluated', 'player', playerId, { bookingId, ratings });
  return { id: ref.id, bookingId, playerId, ratings };
});

export const recordPlayerAttendance = onCall(callableOptions, async request => {
  const coachUid = request.auth?.uid;
  if (!coachUid) throw new HttpsError('unauthenticated', 'Authentification requise.');
  const bookingId = parseString(request.data?.bookingId, 'bookingId', 220);
  const attended = request.data?.attended;
  if (typeof attended !== 'boolean') throw new HttpsError('invalid-argument', 'Confirmez la présence ou l’absence du joueur.');
  const coach = await db.collection('users').doc(coachUid).get();
  if (!coach.exists || coach.get('role') !== 'coach' || coach.get('status') !== 'active') throw new HttpsError('permission-denied', 'Compte coach actif requis.');
  const bookingRef = db.collection('bookings').doc(bookingId);
  const result = await db.runTransaction(async transaction => {
    const booking = await transaction.get(bookingRef);
    if (!booking.exists || booking.get('coachId') !== coachUid) throw new HttpsError('permission-denied', 'Cette réservation ne vous est pas assignée.');
    if (booking.get('isDelete') === true) throw new HttpsError('failed-precondition', 'Cette réservation a été supprimée.');
    if (!['confirmed', 'completed'].includes(booking.get('status'))) throw new HttpsError('failed-precondition', 'La réservation doit être confirmée.');
    const startsAt = booking.get('startsAt');
    if (!(startsAt instanceof Timestamp) || startsAt.toMillis() > Date.now()) throw new HttpsError('failed-precondition', 'La séance doit avoir commencé.');
    const playerRef = db.collection('players').doc(parseString(booking.get('playerId'), 'playerId', 220));
    const player = await transaction.get(playerRef);
    if (!player.exists) throw new HttpsError('not-found', 'Joueur introuvable.');
    // Legacy confirmed bookings have no marker because the course was debited at approval.
    const courseWasDebited = booking.get('courseDebited') === true || booking.get('courseDebited') == null;
    const courseDelta = attendanceCourseDelta(courseWasDebited, attended, Boolean(booking.get('sessionConfigurationId')));
    if (courseDelta < 0 && Number(player.get('remainingSessions')) <= 0) throw new HttpsError('resource-exhausted', 'Le forfait de ce joueur est épuisé. Demandez son réabonnement.');
    if (courseDelta !== 0) transaction.update(playerRef, { remainingSessions: FieldValue.increment(courseDelta), updatedAt: FieldValue.serverTimestamp() });
    transaction.update(bookingRef, {
      attendanceStatus: attended ? 'present' : 'absent',
      attended,
      courseDebited: attended && Boolean(booking.get('sessionConfigurationId')),
      arrivalAt: FieldValue.delete(),
      departureAt: FieldValue.delete(),
      attendanceRecordedBy: coachUid,
      attendanceRecordedAt: FieldValue.serverTimestamp(),
      status: 'completed',
      updatedAt: FieldValue.serverTimestamp(),
    });
    return { courseDelta };
  });
  await audit(coachUid, 'booking.attendance_recorded', 'booking', bookingId, { attended, courseDelta: result.courseDelta });
  return { bookingId, attendanceStatus: attended ? 'present' : 'absent', status: 'completed', courseDelta: result.courseDelta };
});

export const confirmCashPlayerPayment = onCall(callableOptions, async request => {
  const playerId = parseString(request.data?.playerId, 'playerId', 220);
  const actor = await requirePermission(request.auth?.uid, 'bookings.approve');
  const ref = db.collection('players').doc(playerId);
  const result = await db.runTransaction(async transaction => {
    const player = await transaction.get(ref);
    if (!player.exists) throw new HttpsError('not-found', 'Joueur introuvable.');
    if (player.get('isDelete') === true) throw new HttpsError('failed-precondition', 'Ce joueur a été supprimé.');
    if (actor.role !== 'root' && !actor.academyIds.includes(player.get('academyId'))) throw new HttpsError('permission-denied', 'Académie non autorisée.');
    if (player.get('paymentMethod') !== 'cash') throw new HttpsError('failed-precondition', 'Ce joueur n’a pas choisi le paiement cash.');
    if (player.get('status') === 'active' && player.get('paymentStatus') === 'confirmed') {
      return { playerId, status: 'active', alreadyConfirmed: true };
    }
    if (player.get('status') !== 'pending_cash_confirmation' || player.get('paymentStatus') !== 'cash_pending') {
      throw new HttpsError('failed-precondition', 'Ce paiement cash ne peut pas être confirmé dans son état actuel.');
    }
    const configuration = player.get('paymentAmount') == null && player.get('sessionConfigurationId')
      ? await transaction.get(db.collection('sessionConfigurations').doc(player.get('sessionConfigurationId'))) : null;
    const amount = player.get('paymentAmount') ?? configuration?.get('price');
    let currency: string;
    try { currency = parseCurrency(player.get('paymentCurrency') ?? configuration?.get('currency') ?? 'AED'); }
    catch { throw new HttpsError('failed-precondition', 'Devise invalide.'); }
    if (typeof amount !== 'number' || !Number.isFinite(amount) || amount < 0) throw new HttpsError('failed-precondition', 'Montant invalide.');
    const academyId = player.get('academyId');
    const academy = academyId ? await transaction.get(db.collection('academies').doc(academyId)) : null;
    const userId = player.get('assignedUserId') ?? player.get('createdForUserId');
    const customer = userId ? await transaction.get(db.collection('users').doc(userId)) : null;
    const invoice = {
      number: `CASH-${playerId}`,
      issuedAt: new Date().toISOString(),
      playerName: player.get('displayName') ?? player.get('name') ?? playerId,
      issuerName: academy?.get('name') ?? player.get('academyName') ?? '',
      issuerAddress: [academy?.get('address'), academy?.get('city'), academy?.get('country')].filter(Boolean).join(', '),
      customerName: customer?.get('displayName') ?? '',
      customerEmail: customer?.get('email') ?? '',
      customerPhone: customer?.get('phone') ?? '',
      sessionCount: Math.max(1, Number(player.get('sessionCount')) || 1),
      activity: player.get('activityType') ?? '',
      amount, currency, paymentMethod: 'cash',
    };
    const settingsRef = db.collection('systemSettings').doc('dashboard');
    const settings = await transaction.get(settingsRef);
    const totals = settings.get('confirmedCashTotals') ?? {};
    transaction.set(settingsRef, { confirmedCashTotals: { ...totals, [currency]: (Number(totals[currency]) || 0) + amount }, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    const sessionCount = Math.max(1, Number(player.get('sessionCount')) || 1);
    transaction.update(ref, {
      invoice,
      paymentAmount: amount, paymentCurrency: currency,
      status: 'active',
      paymentStatus: 'confirmed',
      remainingSessions: sessionCount,
      paymentConfirmedBy: actor.uid,
      paymentConfirmedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return { playerId, status: 'active', alreadyConfirmed: false };
  });
  await audit(actor.uid, 'player.cash_payment_confirmed', 'player', playerId);
  return result;
});

export const adjustPlayerSessionQuota = onCall(callableOptions, async request => {
  const playerId = parseString(request.data?.playerId, 'playerId', 220);
  const delta = Number(request.data?.delta);
  if (delta !== -1 && delta !== 1) throw new HttpsError('invalid-argument', 'L’ajustement doit être égal à +1 ou -1.');
  const ref = db.collection('players').doc(playerId);
  const preview = await ref.get();
  if (!preview.exists) throw new HttpsError('not-found', 'Joueur introuvable.');
  const academyId = preview.get('academyId');
  const actor = await requirePermission(request.auth?.uid, 'sessions.manage', typeof academyId === 'string' ? academyId : undefined);
  const result = await db.runTransaction(async transaction => {
    const player = await transaction.get(ref);
    if (!player.exists) throw new HttpsError('not-found', 'Joueur introuvable.');
    const packageSessions = Math.max(0, Number(player.get('sessionCount')) || 0);
    let adjustment;
    try {
      adjustment = adjustPlayerCourses(packageSessions, player.get('remainingSessions'), delta);
    } catch (reason) {
      if (reason instanceof Error && reason.message === 'PLAYER_COURSES_EMPTY') {
        throw new HttpsError('failed-precondition', 'Le nombre de cours restants est déjà à zéro.');
      }
      throw reason;
    }
    transaction.update(ref, {
      remainingSessions: adjustment.remainingSessions,
      manualSessionAdjustment: FieldValue.increment(delta),
      quotaAdjustedBy: actor.uid,
      quotaAdjustedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return { playerId, remainingSessions: adjustment.remainingSessions, totalSessions: adjustment.packageSessions };
  });
  await audit(actor.uid, 'player.session_quota_adjusted', 'player', playerId, { academyId: academyId ?? null, delta, remainingSessions: result.remainingSessions, totalSessions: result.totalSessions });
  return result;
});

export const updatePlayerPackage = onCall(callableOptions, async request => {
  const playerId = parseString(request.data?.playerId, 'playerId', 220);
  const requestedSessionCount = Number(request.data?.sessionCount);
  const ref = db.collection('players').doc(playerId);
  const preview = await ref.get();
  if (!preview.exists) throw new HttpsError('not-found', 'Joueur introuvable.');
  const academyId = preview.get('academyId');
  const actor = await requirePermission(request.auth?.uid, 'sessions.manage', typeof academyId === 'string' ? academyId : undefined);
  const result = await db.runTransaction(async transaction => {
    const player = await transaction.get(ref);
    if (!player.exists) throw new HttpsError('not-found', 'Joueur introuvable.');
    let packageUpdate;
    try {
      packageUpdate = calculatePlayerPackage(player.get('sessionCount'), player.get('remainingSessions'), requestedSessionCount);
    } catch (reason) {
      if (reason instanceof Error && reason.message === 'PLAYER_PACKAGE_BELOW_USED') throw new HttpsError('failed-precondition', 'Le package ne peut pas être inférieur au nombre de cours déjà consommés.');
      throw new HttpsError('invalid-argument', 'Le nombre de cours du package doit être un entier compris entre 0 et 10000.');
    }
    transaction.update(ref, {
      sessionCount: packageUpdate.packageSessions,
      remainingSessions: packageUpdate.remainingSessions,
      packageAdjustedBy: actor.uid,
      packageAdjustedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return { playerId, sessionCount: packageUpdate.packageSessions, remainingSessions: packageUpdate.remainingSessions, packageDelta: packageUpdate.packageDelta };
  });
  await audit(actor.uid, 'player.package_updated', 'player', playerId, { academyId: academyId ?? null, sessionCount: result.sessionCount, remainingSessions: result.remainingSessions, packageDelta: result.packageDelta });
  return result;
});

export const softDeletePlayer = onCall(callableOptions, async request => {
  const playerId = parseString(request.data?.playerId, 'playerId', 220);
  const ref = db.collection('players').doc(playerId);
  const player = await ref.get();
  if (!player.exists) throw new HttpsError('not-found', 'Joueur introuvable.');
  const academyId = player.get('academyId');
  const actor = await requirePermission(request.auth?.uid, 'sessions.manage', typeof academyId === 'string' ? academyId : undefined);
  if (player.get('isDelete') === true) return { playerId, isDelete: true, alreadyDeleted: true };
  await ref.update({ isDelete: true, deletedBy: actor.uid, deletedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() });
  await audit(actor.uid, 'player.soft_deleted', 'player', playerId, { academyId: academyId ?? null });
  return { playerId, isDelete: true, alreadyDeleted: false };
});

export const updateSessionConfiguration = onCall(callableOptions, async request => {
  const academyId = parseString(request.data?.academyId, 'academyId', 100);
  const actor = await requirePermission(request.auth?.uid, 'sessions.manage', academyId);
  const activityType = request.data?.activityType;
  if (!['tennis', 'padel'].includes(activityType)) throw new HttpsError('invalid-argument', 'Session invalide.');
  let type;
  try { type = sessionType(request.data?.type); } catch { throw new HttpsError('invalid-argument', 'Type de séance invalide.'); }
  const price = Number(request.data?.price);
  const sessionCount = Number(request.data?.sessionCount);
  const minAge = Number(request.data?.minAge);
  const maximumAge = request.data?.maxAge === null || request.data?.maxAge === undefined || request.data?.maxAge === '' ? null : Number(request.data.maxAge);
  const maxAge = maximumAge ?? minAge;
  let currency;
  try { currency = parseCurrency(request.data?.currency ?? 'AED'); } catch { throw new HttpsError('invalid-argument', 'Devise invalide.'); }
  if (!Number.isInteger(price) || price < 0 || price > 100000000) throw new HttpsError('invalid-argument', 'Prix invalide.');
  if (!Number.isInteger(sessionCount) || sessionCount < 1 || sessionCount > 1000) throw new HttpsError('invalid-argument', 'Le nombre de séances doit être compris entre 1 et 1000.');
  if (!Number.isInteger(minAge) || maximumAge !== null && !Number.isInteger(maximumAge) || minAge < 2 || maxAge > 100 || minAge > maxAge) {
    throw new HttpsError('invalid-argument', 'Tranche d’âge invalide.');
  }
  if (!SESSION_TYPES.includes(type)) throw new HttpsError('invalid-argument', 'Type de séance invalide.');
  const configurations = db.collection('sessionConfigurations');
  const sameType = await configurations.where('academyId', '==', academyId).where('type', '==', type).get();
  const sameActivity = sameType.docs.filter(document => (document.get('activityType') ?? 'tennis') === activityType);
  const exact = sameActivity.find(document => document.get('minAge') === minAge);
  if (maximumAge !== null) {
    const overlap = sameActivity.find(document => document.id !== exact?.id && document.get('active') === true && minAge <= Number(document.get('maxAge') ?? 100) && maxAge >= Number(document.get('minAge')));
    if (overlap) throw new HttpsError('already-exists', 'Cette configuration chevauche une tranche d’âge existante.');
  }
  // The age range is part of the stable business identity. The type is kept at
  // the end to make Firestore documents immediately recognizable.
  const id = exact?.id ?? `${academyId}_${activityType}_${minAge}_${type}`;
  const ref = configurations.doc(id);
  const previous = exact ?? await ref.get();
  await ref.set({ academyId, activityType, type, price, currency, minAge, maxAge, maximumAge, sessionCount, active: true, version: FieldValue.delete(), updatedBy: actor.uid, updatedAt: FieldValue.serverTimestamp(), ...(previous.exists ? {} : { createdBy: actor.uid, createdAt: FieldValue.serverTimestamp() }) }, { merge: true });
  await audit(actor.uid, 'session_configuration.updated', 'sessionConfiguration', id, { academyId, activityType, type, price, currency, minAge, maximumAge, sessionCount });
  return { id, academyId, activityType, type, price, currency, minAge, maxAge: maximumAge, sessionCount, active: true };
});

export const deleteSessionConfiguration = onCall(callableOptions, async request => {
  const configurationId = parseString(request.data?.configurationId, 'configurationId', 220);
  const ref = db.collection('sessionConfigurations').doc(configurationId);
  const configuration = await ref.get();
  if (!configuration.exists) throw new HttpsError('not-found', 'Configuration introuvable.');
  const actor = await requirePermission(request.auth?.uid, 'sessions.manage', configuration.get('academyId'));
  await ref.update({ active: false, deletedBy: actor.uid, deletedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() });
  await audit(actor.uid, 'session_configuration.deleted', 'sessionConfiguration', configurationId, { academyId: configuration.get('academyId') });
  return { id: configurationId, deleted: true };
});

export const upsertPadelSlotTemplate = onCall(callableOptions, async request => {
  const academyId = parseString(request.data?.academyId, 'academyId', 100);
  const actor = await requirePermission(request.auth?.uid, 'sessions.manage', academyId);
  const templateId = request.data?.templateId ? parseString(request.data.templateId, 'templateId', 220) : null;
  const durationMinutes = Number(request.data?.durationMinutes);
  const price = Number(request.data?.price);
  let currency;
  try { currency = parseCurrency(request.data?.currency ?? 'AED'); } catch { throw new HttpsError('invalid-argument', 'Devise invalide.'); }
  if (!Number.isInteger(durationMinutes) || durationMinutes < 15 || durationMinutes > 480) throw new HttpsError('invalid-argument', 'La durée doit être comprise entre 15 et 480 minutes.');
  if (!Number.isInteger(price) || price < 0 || price > 100000000) throw new HttpsError('invalid-argument', 'Prix invalide.');

  const collection = db.collection('padelSlotTemplates');
  const ref = templateId ? collection.doc(templateId) : collection.doc();
  if (templateId) {
    const current = await ref.get();
    if (!current.exists) throw new HttpsError('not-found', 'Créneau Paddle introuvable.');
    if (current.get('academyId') !== academyId) throw new HttpsError('permission-denied', 'Académie non autorisée.');
  }
  // A single academy query avoids requiring a composite index for this small
  // settings catalogue while keeping duplicate validation server-side.
  const academyTemplates = await collection.where('academyId', '==', academyId).get();
  if (academyTemplates.docs.some(document => document.id !== templateId && document.get('active') === true && document.get('durationMinutes') === durationMinutes)) {
    throw new HttpsError('already-exists', 'Un créneau Paddle existe déjà pour cette durée.');
  }
  await ref.set({
    academyId, activityType: 'padel', durationMinutes, price, currency, active: true,
    dayOfWeek: FieldValue.delete(), startTime: FieldValue.delete(),
    updatedBy: actor.uid, updatedAt: FieldValue.serverTimestamp(),
    ...(templateId ? {} : { createdBy: actor.uid, createdAt: FieldValue.serverTimestamp() }),
  }, { merge: true });
  // Player profiles and bookings use sessionConfigurations as their stable
  // contract. Link a one-course configuration to every Padel duration.
  await db.collection('sessionConfigurations').doc(`padel_slot_${ref.id}`).set({
    academyId, activityType: 'padel', type: 'private', price, currency,
    minAge: 3, maxAge: 80, maximumAge: 80, sessionCount: 1, active: true,
    padelSlotTemplateId: ref.id, durationMinutes,
    dayOfWeek: FieldValue.delete(), startTime: FieldValue.delete(),
    updatedBy: actor.uid, updatedAt: FieldValue.serverTimestamp(),
    ...(templateId ? {} : { createdBy: actor.uid, createdAt: FieldValue.serverTimestamp() }),
  }, { merge: true });
  await audit(actor.uid, templateId ? 'padel_slot_template.updated' : 'padel_slot_template.created', 'padelSlotTemplate', ref.id, { academyId, durationMinutes, price, currency });
  return { id: ref.id, academyId, durationMinutes, price, currency, active: true };
});

export const deletePadelSlotTemplate = onCall(callableOptions, async request => {
  const templateId = parseString(request.data?.templateId, 'templateId', 220);
  const ref = db.collection('padelSlotTemplates').doc(templateId);
  const template = await ref.get();
  if (!template.exists) throw new HttpsError('not-found', 'Créneau Paddle introuvable.');
  const actor = await requirePermission(request.auth?.uid, 'sessions.manage', template.get('academyId'));
  if (template.get('active') !== false) {
    const batch = db.batch();
    batch.update(ref, { active: false, deletedBy: actor.uid, deletedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() });
    batch.set(db.collection('sessionConfigurations').doc(`padel_slot_${templateId}`), { active: false, deletedBy: actor.uid, deletedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    await batch.commit();
    await audit(actor.uid, 'padel_slot_template.deleted', 'padelSlotTemplate', templateId, { academyId: template.get('academyId') });
  }
  return { id: templateId, deleted: true };
});

export const createSession = onCall(callableOptions, async request => {
  const configurationId = parseString(request.data?.configurationId, 'configurationId', 220);
  const coachId = parseString(request.data?.coachId, 'coachId', 120);
  const stadiumId = request.data?.stadiumId ? parseString(request.data.stadiumId, 'stadiumId', 120) : null;
  const courtNumber = request.data?.courtNumber === null || request.data?.courtNumber === undefined || request.data?.courtNumber === '' ? null : Number(request.data.courtNumber);
  const capacity = Number(request.data?.capacity);
  const startsAt = new Date(request.data?.startsAt);
  const endsAt = new Date(request.data?.endsAt);
  if (!Number.isFinite(startsAt.valueOf()) || !Number.isFinite(endsAt.valueOf()) || startsAt <= new Date() || endsAt <= startsAt) throw new HttpsError('invalid-argument', 'La date et les heures du créneau sont invalides.');
  if (endsAt.valueOf() - startsAt.valueOf() > 8 * 60 * 60 * 1000) throw new HttpsError('invalid-argument', 'La durée du créneau ne peut pas dépasser 8 heures.');
  if (!Number.isInteger(capacity) || capacity < 1 || capacity > 100) throw new HttpsError('invalid-argument', 'Capacité invalide.');
  if (courtNumber !== null && (!Number.isInteger(courtNumber) || courtNumber < 1)) throw new HttpsError('invalid-argument', 'Terrain invalide.');
  if (!stadiumId && courtNumber !== null) throw new HttpsError('invalid-argument', 'Choisissez un stade avant le numéro de terrain.');
  const [configuration, coach, stadium] = await Promise.all([
    db.collection('sessionConfigurations').doc(configurationId).get(),
    db.collection('coaches').doc(coachId).get(),
    stadiumId ? db.collection('stadiums').doc(stadiumId).get() : Promise.resolve(null),
  ]);
  if (!configuration.exists || configuration.get('active') !== true) throw new HttpsError('failed-precondition', 'Configuration absente ou inactive.');
  const academyId = configuration.get('academyId');
  const type = configuration.get('type');
  if ((type === 'private' && capacity !== 1) || (type === 'semi_private' && (capacity < 2 || capacity > 4)) || (type === 'group' && capacity < 3)) throw new HttpsError('invalid-argument', 'Capacité incompatible avec le type de séance.');
  let actor;
  try {
    actor = await requirePermission(request.auth?.uid, 'sessions.manage', academyId);
  } catch {
    // Booking managers also need to create a one-off slot from the booking form.
    actor = await requirePermission(request.auth?.uid, 'bookings.approve', academyId);
  }
  if (!coach.exists || coach.get('status') !== 'active' || coach.get('academyId') !== academyId) throw new HttpsError('failed-precondition', 'Coach incompatible avec cette configuration.');
  if (stadium && (!stadium.exists || stadium.get('status') !== 'active' || stadium.get('academyId') !== academyId || courtNumber !== null && courtNumber > Number(stadium.get('courtCount')))) throw new HttpsError('failed-precondition', 'Stade ou terrain incompatible avec cette configuration.');
  if (stadiumId && courtNumber !== null) {
    const conflict = await db.collection('sessions').where('stadiumId', '==', stadiumId).get();
    if (conflict.docs.some(document => document.get('status') === 'open' && document.get('courtNumber') === courtNumber && document.get('startsAt')?.toMillis() < endsAt.valueOf() && document.get('endsAt')?.toMillis() > startsAt.valueOf())) throw new HttpsError('already-exists', 'Ce terrain est déjà occupé pendant cette période.');
  }
  const ref = db.collection('sessions').doc();
  await ref.create({
    academyId, configurationId, configurationType: type, activityType: configuration.get('activityType') ?? 'tennis',
    title: `${configuration.get('activityType') === 'padel' ? 'Paddle session' : 'Tennis session'} · ${type === 'private' ? 'Séance privée' : type === 'semi_private' ? 'Séance semi-privée' : 'Séance de groupe'} · ${configuration.get('maximumAge') === null ? `${configuration.get('minAge')} ans` : `${configuration.get('minAge')}–${configuration.get('maximumAge') ?? configuration.get('maxAge')} ans`}`,
    coachId, coachName: coach.get('displayName'), stadiumId, stadiumName: stadium?.get('name') ?? null,
    courtNumber, courtId: stadiumId && courtNumber !== null ? `${stadiumId}_court_${courtNumber}` : null,
    courtName: stadium ? `${stadium.get('name')}${courtNumber !== null ? ` · Terrain ${courtNumber}` : ''}` : 'À définir',
    startsAt: Timestamp.fromDate(startsAt), endsAt: Timestamp.fromDate(endsAt), capacity, bookedCount: 0, status: 'open',
    createdBy: actor.uid, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
  });
  await audit(actor.uid, 'session.created', 'session', ref.id, { academyId, configurationId, coachId, stadiumId, courtNumber, capacity });
  return { id: ref.id, academyId, status: 'open' };
});

export const decideBooking = onCall(emailCallableOptions, async request => {
  const bookingId = parseString(request.data?.bookingId, 'bookingId', 220);
  const decision = request.data?.decision;
  if (!['approve', 'reject'].includes(decision)) throw new HttpsError('invalid-argument', 'Décision invalide.');
  const ref = db.collection('bookings').doc(bookingId);
  const result = await db.runTransaction(async transaction => {
    const booking = await transaction.get(ref);
    if (!booking.exists) throw new HttpsError('not-found', 'Réservation introuvable.');
    const data = booking.data()!;
    if (data.isDelete === true) throw new HttpsError('failed-precondition', 'Cette réservation a été supprimée.');
    const actor = await requirePermission(request.auth?.uid, 'bookings.approve', data.academyId);
    if (data.status !== 'pending') throw new HttpsError('failed-precondition', 'Cette réservation a déjà été traitée.');
    if (decision === 'reject') {
      transaction.update(ref, { status: 'rejected', decidedBy: actor.uid, decidedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() });
      queueBookingNotification(transaction, bookingId, 'rejected', { ...data, status: 'rejected' }, actor.uid);
      return { bookingId, status: 'rejected' };
    }
    const sessionRef = db.collection('sessions').doc(data.sessionId); const playerRef = db.collection('players').doc(data.playerId);
    const [session, player] = await Promise.all([transaction.get(sessionRef), transaction.get(playerRef)]);
    if (!session.exists || session.get('status') !== 'open' || session.get('bookedCount') >= session.get('capacity')) throw new HttpsError('resource-exhausted', 'La séance est complète ou fermée.');
    if (!player.exists) throw new HttpsError('not-found', 'Joueur introuvable.');
    transaction.update(sessionRef, { bookedCount: FieldValue.increment(1), updatedAt: FieldValue.serverTimestamp() });
    transaction.update(ref, { status: 'confirmed', courseDebited: false, decidedBy: actor.uid, decidedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() });
    queueBookingNotification(transaction, bookingId, 'confirmed', { ...data, status: 'confirmed' }, actor.uid);
    return { bookingId, status: 'confirmed' };
  });
  return result;
});

export const rejectScheduledBooking = onCall(emailCallableOptions, async request => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Authentification requise.');
  const bookingId = parseString(request.data?.bookingId, 'bookingId', 220);
  const bookingRef = db.collection('bookings').doc(bookingId);
  const result = await db.runTransaction(async transaction => {
    const booking = await transaction.get(bookingRef);
    if (!booking.exists) throw new HttpsError('not-found', 'Réservation introuvable.');
    const data = booking.data()!;
    if (data.isDelete === true) throw new HttpsError('failed-precondition', 'Cette réservation a été supprimée.');
    const playerId = parseString(data.playerId, 'playerId', 220);
    const link = await transaction.get(db.collection('users').doc(uid).collection('players').doc(playerId));
    if (!link.exists) throw new HttpsError('permission-denied', 'Ce joueur ne vous est pas rattaché.');
    try { scheduledBookingRejectionEffect(data.status, data.clientCanReject); } catch { throw new HttpsError('failed-precondition', 'Cette réservation ne peut plus être refusée.'); }
    const sessionRef = db.collection('sessions').doc(parseString(data.sessionId, 'sessionId', 220));
    transaction.update(sessionRef, { bookedCount: FieldValue.increment(-1), updatedAt: FieldValue.serverTimestamp() });
    transaction.update(bookingRef, { status: 'rejected', clientCanReject: false, clientDecision: 'rejected', clientDecidedBy: uid, clientDecidedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() });
    queueBookingNotification(transaction, bookingId, 'rejected', { ...data, status: 'rejected', clientDecision: 'rejected' }, uid);
    return { bookingId, status: 'rejected' };
  });
  return result;
});

export const updateMyProfile = onCall(callableOptions, async request => {
  if (!request.auth?.uid) throw new HttpsError('unauthenticated', 'Authentification requise.');
  const uid = request.auth.uid;
  const preferredLanguage = request.data?.preferredLanguage;
  if (!['fr', 'en'].includes(preferredLanguage)) throw new HttpsError('invalid-argument', 'Langue invalide.');
  const ref = db.collection('users').doc(uid); const snapshot = await ref.get();
  if (!snapshot.exists || snapshot.get('status') !== 'active') throw new HttpsError('permission-denied', 'Profil utilisateur inactif.');
  const displayName = request.data?.displayName == null
    ? parseString(snapshot.get('displayName'), 'displayName')
    : parseString(request.data.displayName, 'displayName');
  const phone = request.data?.phone == null
    ? String(snapshot.get('phone') ?? '')
    : request.data.phone ? parseString(request.data.phone, 'phone', 30) : '';
  await Promise.all([
    ref.update({ displayName, phone, preferredLanguage, updatedAt: FieldValue.serverTimestamp() }),
    getAuth().updateUser(uid, { displayName }),
    audit(uid, 'profile.updated', 'user', uid, { displayName, preferredLanguage }),
  ]);
  return { uid, displayName, phone, preferredLanguage };
});
