import { randomUUID } from 'node:crypto';
import { FieldValue, Timestamp, getFirestore, type DocumentData, type DocumentReference, type SetOptions } from 'firebase-admin/firestore';

export type BookingEvent = 'created' | 'confirmed' | 'rejected' | 'cancelled' | 'reminder';
interface Writer {
  create(ref: DocumentReference, data: DocumentData): unknown;
  set(ref: DocumentReference, data: DocumentData, options?: SetOptions): unknown;
}

// A new occurrence gets a new identity, even when a deleted booking is recreated.
// This helper performs no reads, rendering, validation or network requests.
// Its write MUST use the transaction/batch committing the business operation.
export function queueBookingNotification(writer: Writer, bookingId: string, event: BookingEvent, booking: DocumentData, requestedBy: string): string {
  const snapshot: DocumentData = {};
  for (const field of ['academyId', 'playerId', 'createdBy', 'notificationOwnerId', 'coachId', 'startsAt', 'endsAt', 'playerName', 'coachName', 'courtName', 'courtId', 'communityCourseName', 'communityCourseId', 'status', 'clientDecision']) {
    snapshot[field] = booking[field] ?? null;
  }
  const id = queueEvent(writer, { kind: 'booking', bookingId, event, booking: snapshot, academyId: booking.academyId ?? null, requestedBy });
  if (event === 'created' || event === 'confirmed') planBookingReminder(writer, bookingId, snapshot, id);
  if (event === 'cancelled' || event === 'rejected') {
    writer.set(getFirestore().collection('bookingReminders').doc(bookingId), {
      bookingId, status: 'cancelled', nextAttemptAt: FieldValue.delete(), updatedAt: FieldValue.serverTimestamp(),
      purgeAt: Timestamp.fromMillis(Date.now() + 30 * 86400000),
    }, { merge: true });
  }
  return id;
}

export function planBookingReminder(writer: Pick<Writer, 'set'>, bookingId: string, booking: DocumentData, version: string): void {
  const due = booking.startsAt instanceof Timestamp ? booking.startsAt.toMillis() - 24 * 3600000 : 0;
  const status = due <= Date.now() ? 'skipped' : booking.status === 'confirmed' ? 'scheduled' : 'awaiting_confirmation';
  writer.set(getFirestore().collection('bookingReminders').doc(bookingId), {
    bookingId, version, academyId: booking.academyId ?? null, status, startsAt: booking.startsAt ?? null,
    ...(status === 'scheduled' ? { nextAttemptAt: Timestamp.fromMillis(due) } : {}),
    reason: status === 'skipped' ? 'less_than_24_hours' : null, updatedAt: FieldValue.serverTimestamp(),
    purgeAt: Timestamp.fromMillis(Math.max(Date.now(), due + 24 * 3600000) + 30 * 86400000),
  });
}

export interface InvitationEvent {
  kind: 'invitation';
  audience: 'coach' | 'administrator';
  userId: string;
  academyId: string | null;
  recipientEmail: string;
  recipientName: string;
  actionUrl: string;
  language: 'en' | 'fr';
  requestedBy: string;
}

export function queueEvent(writer: Writer, input: DocumentData | InvitationEvent, id = randomUUID()): string {
  writer.create(getFirestore().collection('notificationEvents').doc(id), {
    ...input, schemaVersion: 1, status: 'queued',
    nextAttemptAt: Timestamp.now(), createdAt: FieldValue.serverTimestamp(),
  });
  return id;
}
