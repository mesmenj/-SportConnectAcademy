import { getApps, initializeApp } from 'firebase-admin/app';
import { FieldValue, Timestamp, getFirestore, type DocumentSnapshot } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { setGlobalOptions } from 'firebase-functions/v2/options';
import { BOOKING_STATUSES, assertAgeEligible, assertBookable, bookingCreationEffect, bookingDeletionEffect, bookingId, bookingIntervalsOverlap, canTransitionBooking, optionalNote, requiredId, sessionType, shouldDebitCourseOnCompletion } from './domain.js';
import { requirePermission } from './authorization.js';
import { queueBookingNotification } from './notifications/outbox.js';
export { expandNotificationEvent, deliverNotificationMail, retryNotificationQueue, brevoDeliveryWebhook, listNotificationDeliveries, retryNotificationDelivery } from './notifications/functions.js';
export { createAdministrator, updateAdministratorAccess, createAcademy, updateAcademyBranding, updateValidatedRevenue, createStadium, createCoach, resendCoachPasswordLink, deleteCoach, createTournament, updateTournament, softDeleteTournament, updateSessionConfiguration, deleteSessionConfiguration, upsertPadelSlotTemplate, deletePadelSlotTemplate, createSession, createCommunity, updateCommunity, createCommunityCourse, updateCommunityCourse, softDeleteCommunity, softDeleteCommunityCourse, assignPlayerCommunity, createPlayerForUser, assignPlayerToUser, confirmCashPlayerPayment, adjustPlayerSessionQuota, updatePlayerPackage, softDeletePlayer, decideBooking, rejectScheduledBooking, updateMyProfile, submitCoachEvaluation, recordPlayerAttendance } from './management.js';

if (!getApps().length) initializeApp();
const db = getFirestore();
setGlobalOptions({ region: 'europe-west1', maxInstances: 20, concurrency: 40, memory: '256MiB' });
const emailCallableOptions = { enforceAppCheck: false };

function authenticated(uid?: string): string {
  if (!uid) throw new HttpsError('unauthenticated', 'Authentification requise.');
  return uid;
}

function invalidArgument(error: unknown): never {
  const message = error instanceof Error ? error.message : 'Données invalides.';
  throw new HttpsError('invalid-argument', message);
}

export const registerUserProfile = onCall({ enforceAppCheck: false }, async request => {
  const uid = authenticated(request.auth?.uid);
  const displayName = typeof request.data?.displayName === 'string' ? request.data.displayName.trim() : '';
  const accountType = request.data?.accountType;
  const preferredLanguage = request.data?.preferredLanguage === 'fr' ? 'fr' : 'en';
  if (!displayName || displayName.length > 150) throw new HttpsError('invalid-argument', 'Nom invalide.');
  if (!['parent', 'student'].includes(accountType)) throw new HttpsError('invalid-argument', 'Type de compte invalide.');

  const ref = db.collection('users').doc(uid);
  const snapshot = await ref.get();
  if (snapshot.exists) {
    if (!['parent', 'student'].includes(snapshot.get('role'))) {
      throw new HttpsError('permission-denied', 'Ce profil est géré par votre académie.');
    }
    return { uid, role: snapshot.get('role'), alreadyExisted: true };
  }
  await ref.create({
    email: request.auth?.token.email ?? null,
    displayName,
    role: accountType,
    status: 'active',
    academyIds: [],
    permissions: [],
    preferredLanguage,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  return { uid, role: accountType, alreadyExisted: false };
});

export const createPlayerProfile = onCall({ enforceAppCheck: false }, async request => {
  const uid = authenticated(request.auth?.uid);
  const firstName = typeof request.data?.firstName === 'string' ? request.data.firstName.trim() : '';
  const lastName = typeof request.data?.lastName === 'string' ? request.data.lastName.trim() : '';
  const age = Number(request.data?.age);
  const gender = request.data?.gender;
  const sessionConfigurationId = typeof request.data?.sessionConfigurationId === 'string' ? request.data.sessionConfigurationId.trim() : '';
  const paymentMethod = request.data?.paymentMethod;
  if (!firstName || !lastName || firstName.length > 80 || lastName.length > 80) {
    throw new HttpsError('invalid-argument', 'Le nom et le prénom du joueur sont requis.');
  }
  if (!Number.isInteger(age) || age < 3 || age > 80) {
    throw new HttpsError('invalid-argument', 'L’âge doit être compris entre 3 et 80 ans.');
  }
  if (!['female', 'male', 'woman', 'man', 'other'].includes(gender)) {
    throw new HttpsError('invalid-argument', 'Sexe invalide.');
  }
  if (!sessionConfigurationId) throw new HttpsError('invalid-argument', 'Choisissez un type de séance.');
  if (!['cash', 'card', 'payment_link', 'bank_transfer'].includes(paymentMethod)) throw new HttpsError('invalid-argument', 'Choisissez un mode de paiement.');
  const userRef = db.collection('users').doc(uid);
  const user = await userRef.get();
  if (!user.exists || !['parent', 'student'].includes(user.get('role')) || user.get('status') !== 'active') {
    throw new HttpsError('permission-denied', 'Un profil parent ou élève actif est requis.');
  }
  const configuration = await db.collection('sessionConfigurations').doc(sessionConfigurationId).get();
  if (!configuration.exists || configuration.get('active') !== true) throw new HttpsError('failed-precondition', 'Cette configuration de séance n’est plus disponible.');
  const minAge = Number(configuration.get('minAge'));
  const maximumAge = configuration.get('maximumAge');
  const maxAge = maximumAge === null ? minAge : Number(maximumAge ?? configuration.get('maxAge'));
  if (age < minAge || age > maxAge) throw new HttpsError('failed-precondition', 'Cette configuration de séance ne correspond pas à l’âge du joueur.');
  const playerRef = db.collection('players').doc();
  const linkRef = userRef.collection('players').doc(playerRef.id);
  const familyRef = playerRef.collection('family').doc(uid);
  const displayName = `${firstName} ${lastName}`;
  const sessionCount = Number(configuration.get('sessionCount')) || 1;
  const awaitsCashConfirmation = paymentMethod === 'cash';
  const batch = db.batch();
  batch.create(playerRef, {
    firstName, lastName, displayName, age, gender,
    sessionConfigurationId, sessionType: configuration.get('type'), activityType: configuration.get('activityType') ?? 'tennis',
    sessionCount,
    remainingSessions: awaitsCashConfirmation ? 0 : sessionCount,
    paymentAmount: Number(configuration.get('price')), paymentCurrency: configuration.get('currency') ?? 'AED',
    paymentMethod, paymentStatus: paymentMethod === 'cash' ? 'cash_pending' : 'payment_pending',
    academyId: null, academyName: null,
    status: awaitsCashConfirmation ? 'pending_cash_confirmation' : 'active',
    assignedUserId: uid,
    createdBy: uid, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
  });
  batch.create(linkRef, { relationship: user.get('role') === 'student' ? 'self' : 'guardian', createdAt: FieldValue.serverTimestamp() });
  batch.create(familyRef, {
    userId: uid, displayName: user.get('displayName') ?? request.auth?.token.name ?? request.auth?.token.email ?? 'Responsable',
    email: user.get('email') ?? request.auth?.token.email ?? null,
    phone: user.get('phone') ?? null,
    relationship: user.get('role') === 'student' ? 'Élève' : 'Tuteur',
    createdAt: FieldValue.serverTimestamp(),
  });
  await batch.commit();
  return { playerId: playerRef.id, displayName };
});

export const getPlayerCreationOptions = onCall({ enforceAppCheck: false }, async () => {
  const [snapshot, padelTemplates] = await Promise.all([
    db.collection('sessionConfigurations').where('active', '==', true).get(),
    db.collection('padelSlotTemplates').where('active', '==', true).get(),
  ]);
  const knownIds = new Set(snapshot.docs.map(document => document.id));
  const missingTemplates = padelTemplates.docs.filter(document => !knownIds.has(`padel_slot_${document.id}`));
  if (missingTemplates.length) {
    const batch = db.batch();
    for (const template of missingTemplates) {
      batch.set(db.collection('sessionConfigurations').doc(`padel_slot_${template.id}`), {
        academyId: template.get('academyId'), activityType: 'padel', type: 'private',
        price: Number(template.get('price')) || 0, currency: template.get('currency') ?? 'AED',
        minAge: 3, maxAge: 80, maximumAge: 80, sessionCount: 1, active: true,
        padelSlotTemplateId: template.id, dayOfWeek: template.get('dayOfWeek'),
        startTime: template.get('startTime'), durationMinutes: template.get('durationMinutes'),
        createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }
  const configurations = [
    ...snapshot.docs,
    ...missingTemplates.map(template => ({
      id: `padel_slot_${template.id}`,
      get: (field: string) => ({
        academyId: template.get('academyId'), activityType: 'padel', type: 'private',
        minAge: 3, maximumAge: 80, maxAge: 80, price: Number(template.get('price')) || 0,
        currency: template.get('currency') ?? 'AED', sessionCount: 1,
        padelSlotTemplateId: template.id, dayOfWeek: template.get('dayOfWeek'),
        startTime: template.get('startTime'), durationMinutes: template.get('durationMinutes'),
      } as Record<string, unknown>)[field],
    })),
  ];
  return {
    configurations: configurations.map(document => ({
      id: document.id,
      activityType: document.get('activityType') ?? 'tennis',
      type: document.get('type'),
      minAge: document.get('minAge'),
      maximumAge: document.get('maximumAge') === null ? null : document.get('maximumAge') ?? document.get('maxAge'),
      price: document.get('price'),
      currency: document.get('currency') ?? 'AED',
      sessionCount: Number(document.get('sessionCount')) || 1,
      padelSlotTemplateId: document.get('padelSlotTemplateId') ?? null,
      dayOfWeek: document.get('dayOfWeek') ?? null,
      startTime: document.get('startTime') ?? null,
      durationMinutes: document.get('durationMinutes') ?? null,
    })),
  };
});

export const updatePlayerProfile = onCall({ enforceAppCheck: false }, async request => {
  const uid = authenticated(request.auth?.uid);
  let playerId: string;
  try { playerId = requiredId(request.data?.playerId, 'playerId'); } catch (error) { invalidArgument(error); }
  const firstName = typeof request.data?.firstName === 'string' ? request.data.firstName.trim() : '';
  const lastName = typeof request.data?.lastName === 'string' ? request.data.lastName.trim() : '';
  const age = Number(request.data?.age);
  const gender = request.data?.gender;
  if (!firstName || !lastName || firstName.length > 80 || lastName.length > 80) throw new HttpsError('invalid-argument', 'Nom ou prénom invalide.');
  if (!Number.isInteger(age) || age < 3 || age > 80) throw new HttpsError('invalid-argument', 'L’âge doit être compris entre 3 et 80 ans.');
  if (!['female', 'male', 'woman', 'man', 'other'].includes(gender)) throw new HttpsError('invalid-argument', 'Sexe invalide.');
  const link = await db.collection('users').doc(uid).collection('players').doc(playerId).get();
  if (!link.exists) throw new HttpsError('permission-denied', 'Ce joueur ne vous est pas rattaché.');
  const ref = db.collection('players').doc(playerId);
  if (!(await ref.get()).exists) throw new HttpsError('not-found', 'Joueur introuvable.');
  await ref.update({ firstName, lastName, displayName: `${firstName} ${lastName}`, age, gender, updatedBy: uid, updatedAt: FieldValue.serverTimestamp() });
  return { playerId, displayName: `${firstName} ${lastName}` };
});

export const getAvailability = onCall({ enforceAppCheck: false }, async request => {
  authenticated(request.auth?.uid);
  let academyId: string;
  try { academyId = requiredId(request.data?.academyId, 'academyId'); } catch (error) { invalidArgument(error); }
  const from = request.data?.from;
  const to = request.data?.to;
  if (typeof from !== 'string' || typeof to !== 'string') throw new HttpsError('invalid-argument', 'Période invalide.');
  const fromDate = new Date(from); const toDate = new Date(to);
  if (!Number.isFinite(fromDate.valueOf()) || !Number.isFinite(toDate.valueOf()) || toDate <= fromDate || toDate.valueOf() - fromDate.valueOf() > 31 * 86400000) {
    throw new HttpsError('invalid-argument', 'La période doit être comprise entre 1 et 31 jours.');
  }
  const snapshot = await db.collection('sessions').where('academyId', '==', academyId)
    .where('startsAt', '>=', Timestamp.fromDate(fromDate)).where('startsAt', '<', Timestamp.fromDate(toDate)).get();
  return { sessions: snapshot.docs.map(doc => {
    const data = doc.data();
    return { id: doc.id, ...data, startsAt: data.startsAt?.toDate().toISOString(), endsAt: data.endsAt?.toDate().toISOString(), remainingPlaces: Math.max(0, data.capacity - data.bookedCount) };
  }) };
});

export const createBooking = onCall(emailCallableOptions, async request => {
  const uid = authenticated(request.auth?.uid);
  let sessionId: string; let playerId: string; let communityCourseId: string | undefined; let note: string | undefined;
  try {
    sessionId = requiredId(request.data?.sessionId, 'sessionId');
    playerId = requiredId(request.data?.playerId, 'playerId');
    communityCourseId = request.data?.communityCourseId ? requiredId(request.data.communityCourseId, 'communityCourseId') : undefined;
    note = optionalNote(request.data?.note);
  } catch (error) { invalidArgument(error); }
  const sessionRef = db.collection('sessions').doc(sessionId);
  const playerRef = db.collection('players').doc(playerId);
  const linkRef = db.collection('users').doc(uid).collection('players').doc(playerId);
  const resultRef = db.collection('bookings').doc(bookingId(sessionId, playerId));
  const adminProfile = await db.collection('users').doc(uid).get();
  const sessionPreview = await sessionRef.get();
  const playerPreview = await playerRef.get();
  if (!sessionPreview.exists || !playerPreview.exists) throw new HttpsError('not-found', 'Séance ou joueur introuvable.');
  // Administrative overrides require access to both the slot and the player.
  const canOverrideEligibility = adminProfile.get('status') === 'active'
    && ['root', 'admin', 'academy_manager', 'booking_manager'].includes(adminProfile.get('role'))
    && (adminProfile.get('role') === 'root' || Array.isArray(adminProfile.get('academyIds')) && adminProfile.get('academyIds').includes(sessionPreview.get('academyId')));
  if (playerPreview.get('isDelete') === true) throw new HttpsError('failed-precondition', 'Ce joueur a été supprimé.');
  if (!canOverrideEligibility && playerPreview.get('status') !== 'active') throw new HttpsError('failed-precondition', 'Ce profil joueur est en attente de confirmation du paiement cash par un administrateur.');
  let previewType;
  try { previewType = sessionType(sessionPreview.get('configurationType') ?? sessionPreview.get('type')); } catch { throw new HttpsError('failed-precondition', 'Cette séance n’est liée à aucune configuration valide.'); }
  const configurationCandidates = await db.collection('sessionConfigurations')
    .where('academyId', '==', sessionPreview.get('academyId')).where('type', '==', previewType).get();
  const playerAge = playerPreview.get('age');
  const matchingConfigurations = configurationCandidates.docs.filter(document => {
    const minAge = Number(document.get('minAge'));
    const maximumAge = document.get('maximumAge');
    const maxAge = maximumAge === null ? minAge : Number(maximumAge ?? document.get('maxAge'));
    return document.get('active') === true && (canOverrideEligibility || Number.isInteger(playerAge) && playerAge >= minAge && playerAge <= maxAge);
  });
  const sessionActivityType = sessionPreview.get('activityType') ?? 'tennis';
  const activityConfigurations = matchingConfigurations.filter(document => (document.get('activityType') ?? 'tennis') === sessionActivityType);
  if (!canOverrideEligibility && !Number.isInteger(playerAge)) throw new HttpsError('failed-precondition', 'L’âge du joueur doit être renseigné avant la réservation.');
  if (!activityConfigurations.length) throw new HttpsError('failed-precondition', 'Aucune configuration de séance ne correspond à l’âge de ce joueur.');
  const subscribedConfigurationId = playerPreview.get('sessionConfigurationId');
  const selectedConfigurationRef = canOverrideEligibility && activityConfigurations.some(item => item.id === subscribedConfigurationId)
    ? db.collection('sessionConfigurations').doc(subscribedConfigurationId)
    : sessionPreview.get('configurationId')
    ? db.collection('sessionConfigurations').doc(sessionPreview.get('configurationId'))
    : activityConfigurations[0]!.ref;
  if (!(canOverrideEligibility && subscribedConfigurationId) && !sessionPreview.get('configurationId') && activityConfigurations.length > 1) throw new HttpsError('failed-precondition', 'Plusieurs configurations se chevauchent pour cet âge. Corrigez le catalogue.');
  if (!activityConfigurations.some(item => item.id === selectedConfigurationRef.id)) throw new HttpsError('failed-precondition', 'La configuration de cette séance ne correspond pas à l’âge du joueur.');
  if (!canOverrideEligibility && subscribedConfigurationId && subscribedConfigurationId !== selectedConfigurationRef.id) throw new HttpsError('failed-precondition', 'Cette séance ne fait pas partie du forfait de ce joueur.');
  let communityCourse: DocumentSnapshot | undefined;
  let courseCommunityName: string | null = null;
  if (communityCourseId) {
    communityCourse = await db.collection('communityCourses').doc(communityCourseId).get();
    if (!communityCourse.exists || communityCourse.get('active') !== true || communityCourse.get('isDelete') === true || (!canOverrideEligibility && communityCourse.get('communityId') !== playerPreview.get('communityId'))) throw new HttpsError('failed-precondition', 'Ce cours ne correspond pas à la communauté du joueur.');
    const community = await db.collection('communities').doc(communityCourse.get('communityId')).get();
    courseCommunityName = community.get('name') ?? null;
  }

  const result = await db.runTransaction(async transaction => {
    const [sessionSnap, playerSnap, linkSnap, existingSnap] = await Promise.all([
      transaction.get(sessionRef), transaction.get(playerRef), transaction.get(linkRef), transaction.get(resultRef),
    ]);
    if (existingSnap.exists && existingSnap.get('isDelete') !== true) return { bookingId: existingSnap.id, status: existingSnap.get('status'), alreadyExisted: true };
    if (!sessionSnap.exists || !playerSnap.exists) throw new HttpsError('not-found', 'Séance ou joueur introuvable.');
    if (playerSnap.get('isDelete') === true) throw new HttpsError('failed-precondition', 'Ce joueur a été supprimé.');
    if (!canOverrideEligibility && playerSnap.get('status') !== 'active') throw new HttpsError('failed-precondition', 'Ce profil joueur est en attente de confirmation du paiement cash par un administrateur.');
    const session = sessionSnap.data()!;
    let configuredType;
    try { configuredType = sessionType(session.configurationType ?? session.type); } catch { throw new HttpsError('failed-precondition', 'Cette séance n’est liée à aucune configuration valide.'); }
    const configurationRef = selectedConfigurationRef;
    const configurationSnap = await transaction.get(configurationRef);
    if (!configurationSnap.exists || configurationSnap.get('active') !== true || configurationSnap.get('academyId') !== session.academyId || configurationSnap.get('type') !== configuredType || (configurationSnap.get('activityType') ?? 'tennis') !== (session.activityType ?? 'tennis') || !canOverrideEligibility && session.configurationId && session.configurationId !== configurationRef.id) throw new HttpsError('failed-precondition', 'La configuration de cette séance est absente ou incompatible.');
    const configuration = configurationSnap.data()!;
    if (!canOverrideEligibility && playerSnap.get('sessionConfigurationId') && playerSnap.get('sessionConfigurationId') !== configurationRef.id) throw new HttpsError('failed-precondition', 'Cette séance ne fait pas partie du forfait de ce joueur.');
    if (!canOverrideEligibility && Number(playerSnap.get('remainingSessions')) <= 0) throw new HttpsError('resource-exhausted', 'Le forfait de ce joueur est épuisé. Veuillez le réabonner.');
    const isStaffForAcademy = canOverrideEligibility;
    if (canOverrideEligibility && adminProfile.get('role') !== 'root' && !adminProfile.get('academyIds').includes(playerSnap.get('academyId'))) throw new HttpsError('permission-denied', 'Ce joueur ne fait pas partie des académies autorisées.');
    if (!linkSnap.exists && !isStaffForAcademy) throw new HttpsError('permission-denied', 'Ce joueur ne vous est pas rattaché.');
    if (!canOverrideEligibility) try { assertBookable({ ...session, startsAtMillis: session.startsAt?.toMillis() }); } catch (error) {
      const reason = error instanceof Error ? error.message : '';
      if (reason === 'SESSION_FULL') throw new HttpsError('resource-exhausted', 'Cette séance est complète.');
      throw new HttpsError('failed-precondition', 'Cette séance ne peut plus être réservée.');
    }
    if (!canOverrideEligibility) try { assertAgeEligible(playerSnap.get('age'), configuration.minAge, configuration.maxAge); } catch (error) {
      const reason = error instanceof Error ? error.message : '';
      throw new HttpsError('failed-precondition', reason === 'AGE_NOT_ELIGIBLE' ? `Cette séance est réservée aux joueurs de ${configuration.minAge} à ${configuration.maxAge} ans.` : 'L’âge du joueur doit être renseigné avant la réservation.');
    }
    const requestedStart = session.startsAt?.toMillis?.();
    const requestedEnd = session.endsAt?.toMillis?.();
    if (!Number.isFinite(requestedStart) || !Number.isFinite(requestedEnd)) throw new HttpsError('failed-precondition', 'La tranche horaire de cette séance est invalide.');
    if (!canOverrideEligibility) {
    const overlappingCandidates = await transaction.get(
      db.collection('bookings')
        .where('playerId', '==', playerId)
        .where('startsAt', '<', session.endsAt),
    );
    const hasConflict = overlappingCandidates.docs.some(document => {
      if (document.id === resultRef.id || document.get('isDelete') === true || ['cancelled', 'rejected'].includes(document.get('status'))) return false;
      return bookingIntervalsOverlap(document.get('startsAt')?.toMillis?.(), document.get('endsAt')?.toMillis?.(), requestedStart, requestedEnd);
    });
    if (hasConflict) throw new HttpsError('already-exists', 'Ce joueur possède déjà une réservation pendant cette tranche horaire.');
    }
    const creationEffect = bookingCreationEffect(isStaffForAcademy);
    const bookingData = {
      academyId: session.academyId, sessionId, playerId, createdBy: uid, note: note ?? null,
      notificationOwnerId: playerSnap.get('assignedUserId') ?? uid,
      coachId: session.coachId, courtId: session.courtId, startsAt: session.startsAt, endsAt: session.endsAt,
      playerName: playerSnap.get('displayName') ?? playerSnap.get('name') ?? playerId,
      playerAge: playerSnap.get('age') ?? null,
      sessionType: configuredType, activityType: configuration.activityType ?? 'tennis', sessionConfigurationId: configurationRef.id,
      communityId: communityCourse?.get('communityId') ?? null, communityName: communityCourse ? courseCommunityName : playerSnap.get('communityName') ?? null, communityCourseId: communityCourse?.id ?? null, communityCourseName: communityCourse?.get('name') ?? null,
    sessionCount: configuration.sessionCount ?? null, ageRange: { min: configuration.minAge, max: configuration.maxAge },
      coachName: session.coachName ?? session.coachId ?? null,
      courtName: session.courtName ?? session.courtId ?? null,
      amount: configuration.price, currency: configuration.currency ?? 'AED', status: creationEffect.status, clientCanReject: creationEffect.clientCanReject, isDelete: false, courseDebited: false,
      createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
    };
    if (existingSnap.exists) transaction.set(resultRef, bookingData);
    else transaction.create(resultRef, bookingData);
    if (creationEffect.reservePlace) transaction.update(sessionRef, { bookedCount: FieldValue.increment(1), updatedAt: FieldValue.serverTimestamp() });
    transaction.update(playerRef, { bookingScheduleVersion: FieldValue.increment(1), updatedAt: FieldValue.serverTimestamp() });
    queueBookingNotification(transaction, resultRef.id, 'created', bookingData, uid);
    return { bookingId: resultRef.id, status: creationEffect.status, alreadyExisted: false };
  });
  return result;
});

export const cancelBooking = onCall(emailCallableOptions, async request => {
  const uid = authenticated(request.auth?.uid);
  let id: string; try { id = requiredId(request.data?.bookingId, 'bookingId'); } catch (error) { invalidArgument(error); }
  const ref = db.collection('bookings').doc(id);
  const result = await db.runTransaction(async transaction => {
    const snap = await transaction.get(ref);
    if (!snap.exists) throw new HttpsError('not-found', 'Réservation introuvable.');
    const data = snap.data()!;
    if (data.isDelete === true) throw new HttpsError('failed-precondition', 'Cette réservation a été supprimée.');
    if (data.createdBy !== uid) await requirePermission(uid, 'bookings.approve', data.academyId);
    if (data.status === 'cancelled') return { bookingId: id, status: 'cancelled', alreadyCancelled: true };
    if (!['pending', 'confirmed'].includes(data.status)) throw new HttpsError('failed-precondition', 'Cette réservation ne peut plus être annulée.');
    transaction.update(ref, { status: 'cancelled', cancelledBy: uid, cancelledAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() });
    if (data.status === 'confirmed') {
      transaction.update(db.collection('sessions').doc(data.sessionId), { bookedCount: FieldValue.increment(-1), updatedAt: FieldValue.serverTimestamp() });
      if (data.sessionConfigurationId && data.courseDebited !== false) transaction.update(db.collection('players').doc(data.playerId), { remainingSessions: FieldValue.increment(1), updatedAt: FieldValue.serverTimestamp() });
    }
    queueBookingNotification(transaction, id, 'cancelled', { ...data, status: 'cancelled' }, uid);
    return { bookingId: id, status: 'cancelled', alreadyCancelled: false };
  });
  return result;
});

export const softDeleteBooking = onCall({ enforceAppCheck: false }, async request => {
  const uid = authenticated(request.auth?.uid);
  let id: string; try { id = requiredId(request.data?.bookingId, 'bookingId'); } catch (error) { invalidArgument(error); }
  const ref = db.collection('bookings').doc(id);
  return db.runTransaction(async transaction => {
    const snap = await transaction.get(ref);
    if (!snap.exists) throw new HttpsError('not-found', 'Réservation introuvable.');
    const data = snap.data()!;
    await requirePermission(uid, 'bookings.approve', data.academyId);
    if (data.isDelete === true) return { bookingId: id, isDelete: true, alreadyDeleted: true };
    const effect = bookingDeletionEffect(data.status, Boolean(data.sessionConfigurationId) && data.courseDebited !== false);
    transaction.update(ref, {
      isDelete: true,
      status: effect.status,
      statusBeforeDelete: data.status,
      deletedBy: uid,
      deletedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    if (effect.releasePlace) {
      transaction.update(db.collection('sessions').doc(data.sessionId), { bookedCount: FieldValue.increment(-1), updatedAt: FieldValue.serverTimestamp() });
    }
    if (effect.restorePlayerCourse) transaction.update(db.collection('players').doc(data.playerId), { remainingSessions: FieldValue.increment(1), updatedAt: FieldValue.serverTimestamp() });
    if (['pending', 'confirmed'].includes(data.status)) queueBookingNotification(transaction, id, 'cancelled', { ...data, status: 'cancelled' }, uid);
    return { bookingId: id, isDelete: true, alreadyDeleted: false };
  });
});

export const softDeletePlayerBookings = onCall({ enforceAppCheck: false }, async request => {
  const uid = authenticated(request.auth?.uid);
  let playerId: string; try { playerId = requiredId(request.data?.playerId, 'playerId'); } catch (error) { invalidArgument(error); }
  const playerRef = db.collection('players').doc(playerId);
  const player = await playerRef.get();
  if (!player.exists) throw new HttpsError('not-found', 'Joueur introuvable.');
  await requirePermission(uid, 'bookings.approve', player.get('academyId'));
  const snapshot = await db.collection('bookings').where('playerId', '==', playerId).get();
  let deletedCount = 0;
  let restoredSessions = 0;
  const candidates = snapshot.docs.filter(document => document.get('isDelete') !== true);
  // Booking + session + event + reminder writes must stay below 500 per commit.
  for (let offset = 0; offset < candidates.length; offset += 100) {
    const chunk = candidates.slice(offset, offset + 100);
    const chunkResult = await db.runTransaction(async transaction => {
    const current = await Promise.all(chunk.map(document => transaction.get(document.ref)));
    let deletedCount = 0;
    let restoredSessions = 0;
    for (const booking of current) {
      if (!booking.exists || booking.get('isDelete') === true) continue;
      const data = booking.data()!;
      if (data.academyId !== player.get('academyId')) throw new HttpsError('permission-denied', 'Réservation hors du périmètre autorisé.');
      const effect = bookingDeletionEffect(data.status, Boolean(data.sessionConfigurationId) && data.courseDebited !== false);
      transaction.update(booking.ref, {
        isDelete: true,
        status: effect.status,
        statusBeforeDelete: data.status,
        deletedBy: uid,
        deletedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      if (effect.releasePlace) {
        transaction.update(db.collection('sessions').doc(data.sessionId), { bookedCount: FieldValue.increment(-1), updatedAt: FieldValue.serverTimestamp() });
      }
      if (effect.restorePlayerCourse) restoredSessions += 1;
      if (['pending', 'confirmed'].includes(data.status)) queueBookingNotification(transaction, booking.id, 'cancelled', { ...data, status: 'cancelled' }, uid);
      deletedCount += 1;
    }
    if (restoredSessions > 0) transaction.update(playerRef, { remainingSessions: FieldValue.increment(restoredSessions), updatedAt: FieldValue.serverTimestamp() });
    return { deletedCount, restoredSessions };
    });
    deletedCount += chunkResult.deletedCount;
    restoredSessions += chunkResult.restoredSessions;
  }
  return { playerId, isDelete: true, deletedCount, restoredSessions };
});

export const updateBookingStatus = onCall(emailCallableOptions, async request => {
  const uid = authenticated(request.auth?.uid);
  let id: string; try { id = requiredId(request.data?.bookingId, 'bookingId'); } catch (error) { invalidArgument(error); }
  const status = request.data?.status;
  if (!BOOKING_STATUSES.includes(status)) throw new HttpsError('invalid-argument', 'Statut invalide.');
  const ref = db.collection('bookings').doc(id);
  const preview = await ref.get();
  if (!preview.exists) throw new HttpsError('not-found', 'Réservation introuvable.');
  if (preview.get('isDelete') === true) throw new HttpsError('failed-precondition', 'Cette réservation a été supprimée.');
  await requirePermission(uid, 'bookings.approve', preview.get('academyId'));
  const result = await db.runTransaction(async transaction => {
    const snap = await transaction.get(ref);
    if (!snap.exists) throw new HttpsError('not-found', 'Réservation introuvable.');
    if (snap.get('isDelete') === true) throw new HttpsError('failed-precondition', 'Cette réservation a été supprimée.');
    if (!canTransitionBooking(snap.get('status'), status)) {
      throw new HttpsError('failed-precondition', status === 'cancelled' ? 'Utilisez cancelBooking pour annuler.' : 'Transition de statut interdite.');
    }

    // New bookings are debited when attendance is recorded or when an admin
    // completes them. A strict false marker makes this operation idempotent;
    // legacy bookings without the marker were already debited at approval.
    const shouldDebitCourse = status === 'completed' && shouldDebitCourseOnCompletion(
      snap.get('courseDebited'),
      Boolean(snap.get('sessionConfigurationId')),
    );
    let playerRef;
    if (shouldDebitCourse) {
      playerRef = db.collection('players').doc(requiredId(snap.get('playerId'), 'playerId'));
      const player = await transaction.get(playerRef);
      if (!player.exists) throw new HttpsError('not-found', 'Joueur introuvable.');
      if (Number(player.get('remainingSessions')) <= 0) {
        throw new HttpsError('resource-exhausted', 'Le forfait de ce joueur est épuisé. Ajoutez un cours avant de terminer la réservation.');
      }
    }

    transaction.update(ref, {
      status,
      ...(shouldDebitCourse ? { courseDebited: true } : {}),
      ...(status === 'completed' ? { completedBy: uid, completedAt: FieldValue.serverTimestamp() } : {}),
      updatedBy: uid,
      updatedAt: FieldValue.serverTimestamp(),
    });
    if (shouldDebitCourse && playerRef) {
      transaction.update(playerRef, { remainingSessions: FieldValue.increment(-1), updatedAt: FieldValue.serverTimestamp() });
    }
    if (snap.get('status') !== status && (status === 'confirmed' || status === 'rejected')) {
      queueBookingNotification(transaction, id, status, { ...snap.data(), status }, uid);
    }
    return { courseConsumed: shouldDebitCourse };
  });
  return { bookingId: id, status, courseConsumed: result.courseConsumed };
});
