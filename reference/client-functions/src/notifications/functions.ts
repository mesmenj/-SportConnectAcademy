import { getFirestore, FieldValue, Timestamp } from 'firebase-admin/firestore';
import { getAuth } from 'firebase-admin/auth';
import { defineSecret, defineString } from 'firebase-functions/params';
import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { HttpsError, onCall, onRequest } from 'firebase-functions/v2/https';
import { parseString, requirePermission } from '../authorization.js';
import { expandEvent, millis } from './queue.js';
import { deliverMail } from './delivery.js';
import { recordDeliveryWebhook, validWebhookAuthorization } from './webhook.js';
import { queueDueReminder } from './reminders.js';

export const BREVO_API_KEY = defineSecret('BREVO_API_KEY');
export const BREVO_WEBHOOK_TOKEN = defineSecret('BREVO_WEBHOOK_TOKEN');
const fallbackAdmin = defineString('NOTIFICATION_ADMIN_EMAIL', { default: 'jikongcarl@gmail.com' });
const options = { region: 'europe-west1', timeoutSeconds: 60, memory: '256MiB' as const, maxInstances: 5, concurrency: 5 };

const send = (id: string) => deliverMail(getFirestore(), id, BREVO_API_KEY.value(), {
  checkInvitation: async (uid, email) => {
    try {
      const user = await getAuth().getUser(uid);
      return !user.disabled && user.email?.toLowerCase() === email;
    } catch (error) {
      if ((error as { code?: string }).code === 'auth/user-not-found') return false;
      throw error;
    }
  },
});

export const expandNotificationEvent = onDocumentCreated({ ...options, document: 'notificationEvents/{eventId}', retry: true }, event =>
  expandEvent(getFirestore(), event.params.eventId, fallbackAdmin.value()));

export const deliverNotificationMail = onDocumentCreated({ ...options, document: 'mail/{deliveryId}', secrets: [BREVO_API_KEY], retry: true }, event => send(event.params.deliveryId));

// A durable due date also covers lost triggers, crashed workers and provider outages.
// Single-field queries work with Firestore's default indexes.
export const retryNotificationQueue = onSchedule({ ...options, timeoutSeconds: 300, schedule: 'every 1 minutes', secrets: [BREVO_API_KEY], maxInstances: 1 }, async () => {
  const db = getFirestore();
  for (const [collection, process] of [
    ['bookingReminders', (id: string) => queueDueReminder(db, id)],
    ['notificationEvents', (id: string) => expandEvent(db, id, fallbackAdmin.value())],
    ['mail', send],
  ] as const) {
    const due = await db.collection(collection).where('nextAttemptAt', '<=', Timestamp.now()).orderBy('nextAttemptAt').limit(50).get();
    for (let offset = 0; offset < due.docs.length; offset += 5) {
      const results = await Promise.allSettled(due.docs.slice(offset, offset + 5).map(document => process(document.id)));
      results.forEach((result, index) => {
        if (result.status === 'rejected') console.error('Notification queue processing failed', { collection, id: due.docs[offset + index]?.id });
      });
    }
  }
});

export const brevoDeliveryWebhook = onRequest({ ...options, secrets: [BREVO_WEBHOOK_TOKEN], invoker: 'public', cors: false }, async (request, response) => {
  if (request.method !== 'POST') { response.status(405).send('Method not allowed'); return; }
  if (!validWebhookAuthorization(request.get('authorization'), BREVO_WEBHOOK_TOKEN.value())) { response.status(401).send('Unauthorized'); return; }
  if (request.rawBody.length > 65536) { response.status(413).send('Payload too large'); return; }
  const events = Array.isArray(request.body) ? request.body : [request.body];
  if (events.length > 50) { response.status(413).send('Too many events'); return; }
  try {
    for (const event of events) await recordDeliveryWebhook(getFirestore(), event);
    response.status(204).send();
  } catch (error) {
    const invalid = error instanceof Error && error.message === 'invalid_webhook';
    response.status(invalid ? 400 : 503).send(invalid ? 'Invalid event' : 'Please retry');
  }
});

export const listNotificationDeliveries = onCall({ region: 'europe-west1', enforceAppCheck: false }, async request => {
  const actor = await requirePermission(request.auth?.uid, 'admins.manage');
  const academyId = request.data?.academyId;
  if (actor.role !== 'root') {
    if (typeof academyId !== 'string' || !actor.academyIds?.includes(academyId)) throw new HttpsError('permission-denied', 'Choisissez une académie autorisée.');
  }
  let query = getFirestore().collection('mail').orderBy('createdAt', 'desc');
  if (typeof academyId === 'string' && academyId) query = query.where('academyId', '==', academyId);
  const beforeId = request.data?.beforeId;
  if (beforeId) {
    const cursor = await getFirestore().collection('mail').doc(parseString(beforeId, 'beforeId', 128)).get();
    if (cursor.exists) {
      if (actor.role !== 'root' && cursor.get('academyId') !== academyId) throw new HttpsError('permission-denied', 'Académie non autorisée.');
      query = query.startAfter(cursor);
    }
  }
  const snapshot = await query.limit(50).get();
  return { deliveries: snapshot.docs.map(document => ({
    id: document.id, eventId: document.get('eventId') ?? null, bookingId: document.get('bookingId') ?? null,
    recipient: document.get('recipient') ?? null, template: document.get('template') ?? '',
    status: document.get('status'), attempts: document.get('attempts') ?? 0,
    lastError: document.get('schemaVersion') === 2 ? document.get('lastError') ?? null : 'legacy_delivery',
    providerMessageId: document.get('providerMessageId') ?? null, retryable: document.get('retryable') === true,
    createdAt: millis(document.get('createdAt')), updatedAt: millis(document.get('updatedAt')),
  })), nextCursor: snapshot.size === 50 ? snapshot.docs.at(-1)!.id : null };
});

export const retryNotificationDelivery = onCall({ region: 'europe-west1', enforceAppCheck: false }, async request => {
  const actor = await requirePermission(request.auth?.uid, 'admins.manage');
  const id = parseString(request.data?.deliveryId, 'deliveryId', 128);
  const ref = getFirestore().collection('mail').doc(id);
  const preview = await ref.get();
  if (!preview.exists) throw new HttpsError('not-found', 'Notification introuvable.');
  if (actor.role !== 'root' && !actor.academyIds.includes(preview.get('academyId'))) throw new HttpsError('permission-denied', 'Académie non autorisée.');
  return getFirestore().runTransaction(async transaction => {
    const mail = await transaction.get(ref);
    if (mail.get('schemaVersion') !== 2 || mail.get('status') !== 'failed' || mail.get('retryable') !== true || mail.get('uncertainSince')) {
      throw new HttpsError('failed-precondition', 'Cette notification ne peut pas être relancée automatiquement.');
    }
    if (mail.get('expiresAt') && millis(mail.get('expiresAt')) <= Date.now()) throw new HttpsError('failed-precondition', 'Générez une nouvelle invitation.');
    const payload = await transaction.get(getFirestore().collection('notificationPayloads').doc(id));
    if (!payload.exists) throw new HttpsError('failed-precondition', 'Le contenu de cette notification a expiré.');
    transaction.update(ref, { status: 'queued', attempts: 0, retryable: false, nextAttemptAt: Timestamp.now(), updatedAt: FieldValue.serverTimestamp() });
    transaction.create(getFirestore().collection('auditLogs').doc(), { actorId: actor.uid, action: 'notification.retry_requested', targetType: 'mail', targetId: id, createdAt: FieldValue.serverTimestamp() });
    return { deliveryId: id, status: 'queued' };
  });
});
