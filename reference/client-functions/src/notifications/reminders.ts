import { randomUUID } from 'node:crypto';
import { FieldValue, Timestamp, type Firestore, type QueryDocumentSnapshot } from 'firebase-admin/firestore';
import { planBookingReminder, queueEvent } from './outbox.js';
import { millis } from './queue.js';

export async function queueDueReminder(db: Firestore, bookingId: string, now = Date.now()): Promise<void> {
  const ref = db.collection('bookingReminders').doc(bookingId);
  await db.runTransaction(async transaction => {
    const [reminder, booking] = await Promise.all([transaction.get(ref), transaction.get(db.collection('bookings').doc(bookingId))]);
    if (!reminder.exists || reminder.get('status') !== 'scheduled' || millis(reminder.get('nextAttemptAt')) > now) return;
    const startsAt = millis(booking.get('startsAt'));
    if (!booking.exists || booking.get('isDelete') === true || booking.get('status') !== 'confirmed' || startsAt <= now || startsAt !== millis(reminder.get('startsAt'))) {
      transaction.update(ref, { status: 'skipped', reason: 'booking_no_longer_eligible', nextAttemptAt: FieldValue.delete(), updatedAt: FieldValue.serverTimestamp() });
      return;
    }
    const eventId = queueEvent(transaction, {
      kind: 'booking', event: 'reminder', bookingId, academyId: booking.get('academyId') ?? null,
      // Snapshot only fields needed by the notification, never arbitrary booking metadata.
      booking: Object.fromEntries(['academyId', 'playerId', 'createdBy', 'notificationOwnerId', 'coachId', 'startsAt', 'endsAt', 'playerName', 'coachName', 'courtName', 'courtId', 'communityCourseName', 'communityCourseId', 'status'].map(field => [field, booking.get(field) ?? null])),
      reminderVersion: reminder.get('version'), requestedBy: 'system:booking-reminder',
    });
    transaction.update(ref, { status: 'queued', eventId, nextAttemptAt: FieldValue.delete(), updatedAt: FieldValue.serverTimestamp() });
  });
}

// One-time migration for bookings created before the reminder feature. Dry-run
// by default, paginated, and safe to repeat alongside live booking transactions.
export async function backfillBookingReminders(db: Firestore, apply = false, now = Date.now()): Promise<{ eligible: number; planned: number }> {
  const cutoff = Timestamp.fromMillis(now + 24 * 3600000);
  let cursor: QueryDocumentSnapshot | undefined;
  let eligible = 0; let planned = 0;
  while (true) {
    let query = db.collection('bookings').where('status', '==', 'confirmed').where('startsAt', '>', cutoff).orderBy('startsAt').limit(100);
    if (cursor) query = query.startAfter(cursor);
    const page = await query.get();
    for (const snapshot of page.docs) {
      const ref = db.collection('bookingReminders').doc(snapshot.id);
      if (snapshot.get('isDelete') === true) continue;
      if (!apply) { if (!(await ref.get()).exists) eligible++; continue; }
      const added = await db.runTransaction(async transaction => {
        const [booking, reminder] = await Promise.all([transaction.get(snapshot.ref), transaction.get(ref)]);
        if (reminder.exists || !booking.exists || booking.get('isDelete') === true || booking.get('status') !== 'confirmed' || millis(booking.get('startsAt')) <= Date.now() + 24 * 3600000) return false;
        planBookingReminder(transaction, booking.id, booking.data()!, randomUUID());
        return true;
      });
      if (added) { eligible++; planned++; }
    }
    if (page.size < 100) break;
    cursor = page.docs.at(-1);
  }
  return { eligible, planned };
}
