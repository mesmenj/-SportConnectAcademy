import { randomUUID } from 'node:crypto';
import { FieldValue, Timestamp, type Firestore, type DocumentData } from 'firebase-admin/firestore';
import { bookingTemplate, deliveryId, invitationTemplate, notificationConfig } from '../notifications.js';
import type { BookingEvent } from './outbox.js';

export function normalizedEmail(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const result = value.trim().toLowerCase();
  return result.length <= 254 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(result) ? result : null;
}

export const millis = (value: unknown): number => value instanceof Timestamp ? value.toMillis() : 0;
type Recipient = { kind: string; email: unknown; name: string; actionUrl: string };
const text = (value: unknown, fallback = '—'): string => typeof value === 'string' && value.trim() ? value : fallback;

// Expansion is atomic: either every recipient has a durable job, or none do.
// The event snapshot is used even if the booking has since changed or disappeared.
export async function expandEvent(db: Firestore, eventId: string, fallbackAdminEmail: string): Promise<void> {
  const eventRef = db.collection('notificationEvents').doc(eventId);
  await db.runTransaction(async transaction => {
    const eventDoc = await transaction.get(eventRef);
    if (!eventDoc.exists || eventDoc.get('status') !== 'queued') return;
    const event = eventDoc.data()!;
    const recipients: Recipient[] = [];
    const booking = event.booking ?? {};
    let player: DocumentData = {};
    let coach: DocumentData = {};
    let course: DocumentData = {};
    if (event.kind === 'booking') {
      const read = async (collection: string, id: unknown) => typeof id === 'string' && id && !id.includes('/')
        ? (await transaction.get(db.collection(collection).doc(id))).data() ?? {} : {};
      [player, coach, course] = await Promise.all([read('players', booking.playerId), read('coaches', booking.coachId), read('communityCourses', booking.communityCourseId)]);
      const [owner, coachUser, academy] = await Promise.all([
        read('users', booking.notificationOwnerId ?? player.assignedUserId ?? booking.createdBy),
        read('users', booking.coachId), read('academies', event.academyId),
      ]);
      recipients.push({ kind: 'user', email: owner.email, name: text(owner.displayName, 'Member'), actionUrl: notificationConfig.userAppUrl });
      if (booking.coachId && event.event !== 'reminder') recipients.push({ kind: 'coach', email: coachUser.email ?? coach.email, name: text(coachUser.displayName ?? coach.displayName, 'Coach'), actionUrl: notificationConfig.coachAppUrl });
      if (['created', 'cancelled', 'rejected'].includes(event.event)) {
        // Explicit academy routing wins. Otherwise use active, scoped booking administrators.
        if (Array.isArray(academy.notificationEmails) && academy.notificationEmails.length) {
          for (const address of academy.notificationEmails) recipients.push({ kind: 'admin', email: address, name: 'Administrator', actionUrl: notificationConfig.adminAppUrl });
        } else {
          const scoped = typeof event.academyId === 'string' && event.academyId
            ? await transaction.get(db.collection('users').where('academyIds', 'array-contains', event.academyId)) : null;
          const admins = scoped?.docs.filter(document => document.get('status') === 'active' &&
            (['root', 'admin', 'booking_manager'].includes(document.get('role')) || Array.isArray(document.get('permissions')) && document.get('permissions').includes('bookings.approve'))) ?? [];
          for (const admin of admins) recipients.push({ kind: 'admin', email: admin.get('email'), name: text(admin.get('displayName'), 'Administrator'), actionUrl: notificationConfig.adminAppUrl });
          if (!admins.length) recipients.push({ kind: 'admin', email: fallbackAdminEmail, name: 'Administrator', actionUrl: notificationConfig.adminAppUrl });
        }
      }
    } else if (event.kind === 'invitation') {
      recipients.push({ kind: event.audience, email: event.recipientEmail, name: text(event.recipientName, 'Member'), actionUrl: event.actionUrl });
    } else {
      transaction.update(eventRef, { status: 'failed', lastError: 'Unsupported event schema', nextAttemptAt: FieldValue.delete() });
      return;
    }

    const seen = new Set<string>();
    const ids: string[] = [];
    if (new Set(recipients.map(recipient => normalizedEmail(recipient.email) ?? `missing:${recipient.kind}`)).size > 200) {
      // Do not silently drop recipients or exceed Firestore's transaction limit.
      const id = deliveryId(eventId, 'routing_error', '');
      transaction.create(db.collection('mail').doc(id), {
        schemaVersion: 2, eventId, academyId: event.academyId ?? null, bookingId: event.bookingId ?? null,
        template: 'routing_error', status: 'failed', lastError: 'recipient_limit_exceeded', retryable: false,
        recipient: { email: null, name: 'Administrator' }, attempts: 0, createdAt: FieldValue.serverTimestamp(),
      });
      transaction.update(eventRef, { status: 'failed', lastError: 'recipient_limit_exceeded', nextAttemptAt: FieldValue.delete() });
      return;
    }
    for (const recipient of recipients) {
      const address = normalizedEmail(recipient.email);
      const key = address ?? `missing:${recipient.kind}`;
      if (seen.has(key)) continue;
      seen.add(key);
      const template = event.kind === 'booking' ? `booking_${event.event}_${recipient.kind}` : `${event.audience}_invitation`;
      const id = deliveryId(eventId, template, key);
      ids.push(id);
      let rendered: { subject: string; html: string; text: string } | undefined;
      let failure = address ? null : 'invalid_recipient';
      const expiresAt = event.kind === 'invitation' ? Timestamp.fromMillis(millis(event.createdAt) + 30 * 60000)
        : event.event === 'reminder' && booking.startsAt instanceof Timestamp ? booking.startsAt : null;
      try {
        if (event.kind === 'booking') {
          const displayEvent: BookingEvent = event.event === 'created' && booking.status === 'confirmed' ? 'confirmed' : event.event;
          rendered = bookingTemplate({
            recipientName: recipient.name, playerName: text(booking.playerName ?? player.displayName), event: displayEvent,
            startsAt: booking.startsAt instanceof Timestamp ? booking.startsAt.toDate() : null,
            // The community course represents the venue. Preserve its event
            // snapshot first, resolving legacy records from the course document.
            locationName: text([booking.communityCourseName, course.name, booking.courtName, booking.courtId]
              .find(value => typeof value === 'string' && value.trim() && !/^(à définir|to be defined|tbd)$/i.test(value.trim()))),
            coachName: text(booking.coachName ?? coach.displayName), actionUrl: recipient.actionUrl, locale: 'en',
          });
        } else {
          if (expiresAt!.toMillis() <= Date.now()) failure = 'invitation_expired';
          if (typeof event.actionUrl !== 'string' || !event.actionUrl.startsWith('https://')) failure = 'invalid_invitation_link';
          rendered = invitationTemplate(recipient.name, String(event.actionUrl ?? ''), event.language === 'fr' ? 'fr' : 'en', event.audience);
        }
      } catch {
        failure = 'invalid_template_data';
      }
      transaction.create(db.collection('mail').doc(id), {
        schemaVersion: 2, eventId, bookingId: event.bookingId ?? null, academyId: event.academyId ?? null,
        kind: event.kind, userId: event.userId ?? null, reminderVersion: event.reminderVersion ?? null, template, recipient: { email: address, name: recipient.name },
        language: event.kind === 'booking' ? 'en' : event.language, requestedBy: event.requestedBy,
        status: failure ? 'failed' : 'queued', attempts: 0, idempotencyKey: randomUUID(),
        lastError: failure, retryable: false, uncertainSince: null, providerMessageId: null,
        expiresAt, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
        ...(failure ? {} : { nextAttemptAt: Timestamp.now() }),
      });
      if (!failure && rendered) transaction.create(db.collection('notificationPayloads').doc(id), {
        // Private collection: reset links must never enter the readable mail journal.
        body: { sender: notificationConfig.sender, to: [{ email: address, name: recipient.name }], replyTo: notificationConfig.sender,
          subject: rendered.subject, htmlContent: rendered.html, textContent: rendered.text,
          tags: ['transactional', event.kind], headers: { 'X-Mailin-custom': `classcard-delivery:${id}` } },
        // TTL is only cleanup; workers independently enforce invitation expiry.
        purgeAt: expiresAt ?? Timestamp.fromMillis(Date.now() + 30 * 86400000),
      });
    }
    transaction.update(eventRef, {
      status: 'expanded', deliveryIds: ids, expandedAt: FieldValue.serverTimestamp(), nextAttemptAt: FieldValue.delete(),
      actionUrl: FieldValue.delete(), purgeAt: Timestamp.fromMillis(Date.now() + 30 * 86400000),
    });
  });
}
