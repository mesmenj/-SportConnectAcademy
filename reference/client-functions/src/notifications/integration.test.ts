import assert from 'node:assert/strict';
import test from 'node:test';
import { randomUUID } from 'node:crypto';
import { getApps, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, Timestamp, type Firestore, type DocumentData } from 'firebase-admin/firestore';
import { queueBookingNotification, queueEvent } from './outbox.js';
import { expandEvent } from './queue.js';
import { deliverMail, SAFE_RETRY_WINDOW_MS } from './delivery.js';
import { recordDeliveryWebhook } from './webhook.js';
import { backfillBookingReminders, queueDueReminder } from './reminders.js';

const enabled = Boolean(process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_AUTH_EMULATOR_HOST);

test('notification pipeline on real Firestore/Auth emulators', { skip: !enabled }, async t => {
  const projectId = process.env.GCLOUD_PROJECT;
  assert.ok(projectId?.startsWith('demo-'), 'Integration tests only run on a demo project');
  if (!getApps().length) initializeApp({ projectId });
  const db = getFirestore();
  const api = await import('../index.js');
  const response = (status = 201, body: object = { messageId: '<test-message@brevo.test>' }, headers: Record<string, string> = {}) => new Response(JSON.stringify(body), { status, headers });
  const call = (uid: string, data: object): any => ({ auth: { uid, token: {} }, data });

  async function fixture(parentEmail = 'parent@example.test') {
    const key = randomUUID();
    const ids = { academy: `a-${key}`, player: `p-${key}`, parent: `u-${key}`, coach: `c-${key}`, admin: `s-${key}`, session: `slot-${key}`, configuration: `cfg-${key}` };
    const bookingId = `${ids.session}_${ids.player}`;
    const start = Date.now() + 86400000;
    const booking: DocumentData = {
      academyId: ids.academy, playerId: ids.player, notificationOwnerId: ids.parent, createdBy: ids.parent, coachId: ids.coach,
      sessionId: ids.session, sessionConfigurationId: ids.configuration, status: 'confirmed', courseDebited: false,
      playerName: 'Player <One>', courtName: 'Court A', startsAt: Timestamp.fromMillis(start), endsAt: Timestamp.fromMillis(start + 3600000),
    };
    const rows: Record<string, DocumentData> = {
      [`academies/${ids.academy}`]: { name: 'Academy' },
      [`users/${ids.parent}`]: { email: parentEmail, displayName: 'Parent', role: 'student', status: 'active' },
      [`users/${ids.admin}`]: { email: 'admin@example.test', displayName: 'Admin', role: 'root', status: 'active', permissions: ['admins.manage'], academyIds: [ids.academy] },
      [`users/${ids.coach}`]: { email: 'coach@example.test', displayName: 'Coach', role: 'coach', status: 'active', academyIds: [ids.academy] },
      [`coaches/${ids.coach}`]: { email: 'coach@example.test', displayName: 'Coach', status: 'active', academyId: ids.academy },
      [`players/${ids.player}`]: { academyId: ids.academy, assignedUserId: ids.parent, displayName: 'Player', status: 'active', age: 30, remainingSessions: 8, sessionConfigurationId: ids.configuration },
      [`users/${ids.parent}/players/${ids.player}`]: {},
      [`sessions/${ids.session}`]: { academyId: ids.academy, coachId: ids.coach, courtId: 'court', courtName: 'Court A', configurationId: ids.configuration, configurationType: 'group', type: 'group', activityType: 'tennis', status: 'open', capacity: 10, bookedCount: 0, startsAt: booking.startsAt, endsAt: booking.endsAt },
      [`sessionConfigurations/${ids.configuration}`]: { academyId: ids.academy, type: 'group', activityType: 'tennis', active: true, minAge: 18, maxAge: 80, price: 100, currency: 'AED', sessionCount: 10 },
    };
    const batch = db.batch();
    for (const [path, data] of Object.entries(rows)) batch.set(db.doc(path), data);
    await batch.commit();
    const queue = async (event: 'created' | 'confirmed' | 'rejected' | 'cancelled' = 'created') => db.runTransaction(async transaction => queueBookingNotification(transaction, bookingId, event, booking, ids.parent));
    const jobs = async (eventId: string) => (await db.collection('mail').where('eventId', '==', eventId).get()).docs;
    const events = async () => (await db.collection('notificationEvents').where('bookingId', '==', bookingId).get()).docs;
    return { ids, bookingId, booking, queue, jobs, events };
  }

  async function job() {
    const f = await fixture();
    const eventId = await f.queue();
    await expandEvent(db, eventId, 'fallback@example.test');
    return (await f.jobs(eventId))[0]!;
  }

  await t.test('business transaction rollback also rolls back its event', async () => {
    const f = await fixture();
    await assert.rejects(db.runTransaction(async transaction => {
      transaction.set(db.doc(`bookings/${f.bookingId}`), f.booking);
      queueBookingNotification(transaction, f.bookingId, 'created', f.booking, f.ids.parent);
      throw new Error('business failure');
    }));
    assert.equal((await db.doc(`bookings/${f.bookingId}`).get()).exists, false);
    assert.equal((await f.events()).length, 0);
  });

  await t.test('creation, duplicate calls, deletion and recreation preserve accounting and event identity', async () => {
    const f = await fixture();
    const input = call(f.ids.admin, { sessionId: f.ids.session, playerId: f.ids.player });
    const result = await api.createBooking.run(input);
    assert.equal(result.status, 'confirmed');
    assert.equal((await api.createBooking.run(input)).alreadyExisted, true);
    let events = await f.events();
    assert.equal(events.length, 1);
    const firstId = events[0]!.id;
    await api.softDeleteBooking.run(call(f.ids.admin, { bookingId: result.bookingId }));
    assert.equal((await db.doc(`sessions/${f.ids.session}`).get()).get('bookedCount'), 0);
    assert.equal((await db.doc(`players/${f.ids.player}`).get()).get('remainingSessions'), 8);
    await api.createBooking.run(input);
    events = await f.events();
    assert.equal(events.length, 3);
    assert.equal(events.filter(event => event.get('event') === 'created').length, 2);
    for (const event of events) await expandEvent(db, event.id, 'fallback@example.test');
    assert.equal((await f.jobs(firstId)).length, 3);
    const recreated = events.find(event => event.get('event') === 'created' && event.id !== firstId)!;
    assert.equal((await f.jobs(recreated.id)).length, 3);
    assert.equal((await db.doc(`sessions/${f.ids.session}`).get()).get('bookedCount'), 1);
  });

  await t.test('created event contains an immutable snapshot and immediate confirmation wording', async () => {
    const f = await fixture();
    const id = await f.queue();
    await db.doc(`bookings/${f.bookingId}`).set({ courtName: 'Changed court', status: 'cancelled' });
    await Promise.all([expandEvent(db, id, ''), expandEvent(db, id, '')]);
    const jobs = await f.jobs(id);
    assert.equal(jobs.length, 3);
    const payload = await db.doc(`notificationPayloads/${jobs[0]!.id}`).get();
    assert.match(payload.get('body.textContent'), /Location: Court A/);
    assert.equal(payload.get('body.subject'), 'Booking confirmed');
    assert.equal((await db.doc(`notificationEvents/${id}`).get()).get('status'), 'expanded');
  });

  await t.test('community course venue takes priority in every booking email, preserving the snapshot', async () => {
    const f = await fixture();
    const courseId = `course-${randomUUID()}`;
    Object.assign(f.booking, { communityCourseId: courseId, communityCourseName: 'Dubai Schools Al Barsha', courtName: 'À définir' });
    await db.doc(`communityCourses/${courseId}`).set({ name: 'Renamed venue' });
    for (const event of ['created', 'confirmed', 'rejected', 'cancelled', 'reminder'] as const) {
      const batch = db.batch();
      const id = queueEvent(batch, { kind: 'booking', bookingId: f.bookingId, booking: f.booking, academyId: f.ids.academy, event, requestedBy: f.ids.parent });
      await batch.commit();
      await expandEvent(db, id, '');
      const jobs = await f.jobs(id);
      assert.ok(jobs.length > 0);
      for (const mail of jobs) {
        const body = (await db.doc(`notificationPayloads/${mail.id}`).get()).get('body');
        assert.match(body.textContent, /Location: Dubai Schools Al Barsha/);
        assert.ok(body.htmlContent.includes('Dubai Schools Al Barsha'));
        assert.ok(!body.textContent.includes('À définir'));
        assert.ok(!body.textContent.includes('Renamed venue'));
      }
    }
  });

  await t.test('legacy venue lookup skips empty names and retains real courts as fallback', async () => {
    for (const [snapshotName, courseName, courtName, expected] of [
      ['', 'Community venue', 'Court A', 'Community venue'],
      ['Snapshot venue', 'Community venue', 'Court A', 'Snapshot venue'],
      ['   ', '', 'Court A', 'Court A'],
      [null, '', 'À définir', '—'],
    ]) {
      const f = await fixture();
      const courseId = `course-${randomUUID()}`;
      Object.assign(f.booking, { communityCourseId: courseId, communityCourseName: snapshotName, courtName });
      await db.doc(`communityCourses/${courseId}`).set({ name: courseName });
      const id = await f.queue(); await expandEvent(db, id, '');
      for (const mail of await f.jobs(id)) {
        const body = (await db.doc(`notificationPayloads/${mail.id}`).get()).get('body');
        assert.ok(body.textContent.includes(`Location: ${expected}\n`));
      }
    }
  });

  await t.test('invalid recipient is journaled without preventing valid deliveries', async () => {
    const f = await fixture('invalid-email');
    const id = await f.queue(); await expandEvent(db, id, '');
    const jobs = await f.jobs(id);
    assert.equal(jobs.length, 3);
    assert.equal(jobs.filter(job => job.get('status') === 'failed').length, 1);
    assert.equal(jobs.filter(job => job.get('status') === 'queued').length, 2);
  });

  await t.test('same mailbox in multiple roles receives only one email per event', async () => {
    const f = await fixture('coach@example.test');
    const id = await f.queue(); await expandEvent(db, id, '');
    assert.equal((await f.jobs(id)).length, 2);
  });

  await t.test('client refusal informs parent, coach and scoped administrator, without consuming courses', async () => {
    const f = await fixture();
    await db.doc(`bookings/${f.bookingId}`).set({ ...f.booking, clientCanReject: true });
    await db.doc(`sessions/${f.ids.session}`).update({ bookedCount: 1 });
    await api.rejectScheduledBooking.run(call(f.ids.parent, { bookingId: f.bookingId }));
    const event = (await f.events())[0]!;
    assert.equal(event.get('event'), 'rejected');
    await expandEvent(db, event.id, 'fallback@example.test');
    assert.equal((await f.jobs(event.id)).length, 3);
    assert.equal((await db.doc(`sessions/${f.ids.session}`).get()).get('bookedCount'), 0);
    assert.equal((await db.doc(`players/${f.ids.player}`).get()).get('remainingSessions'), 8);
  });

  await t.test('approval and cancellation are durable and repeated cancellation creates no extra event', async () => {
    const f = await fixture();
    await db.doc(`bookings/${f.bookingId}`).set({ ...f.booking, status: 'pending' });
    await api.decideBooking.run(call(f.ids.admin, { bookingId: f.bookingId, decision: 'approve' }));
    await api.updateBookingStatus.run(call(f.ids.admin, { bookingId: f.bookingId, status: 'confirmed' }));
    assert.equal((await f.events()).length, 1);
    await api.cancelBooking.run(call(f.ids.admin, { bookingId: f.bookingId }));
    await api.cancelBooking.run(call(f.ids.admin, { bookingId: f.bookingId }));
    assert.equal((await f.events()).length, 2);
    assert.equal((await db.doc(`sessions/${f.ids.session}`).get()).get('bookedCount'), 0);
  });

  await t.test('bulk deletion emits cancellation only for active bookings', async () => {
    const f = await fixture();
    await db.doc(`bookings/${f.bookingId}`).set(f.booking);
    await db.doc(`bookings/completed-${f.bookingId}`).set({ ...f.booking, status: 'completed' });
    await db.doc(`sessions/${f.ids.session}`).update({ bookedCount: 1 });
    await api.softDeletePlayerBookings.run(call(f.ids.admin, { playerId: f.ids.player }));
    assert.equal((await f.events()).length, 1);
    assert.equal((await db.doc(`sessions/${f.ids.session}`).get()).get('bookedCount'), 0);
  });

  await t.test('concurrent workers acquire one lease and send one request', async () => {
    const mail = await job(); let requests = 0;
    const fakeFetch: typeof fetch = async (_url, init) => {
      requests++;
      const body = JSON.parse(String(init?.body));
      assert.match(body.headers.idempotencyKey, /^[a-f0-9-]{36}$/);
      assert.equal(body.headers['X-Mailin-custom'], `classcard-delivery:${mail.id}`);
      assert.ok(init?.signal);
      await new Promise(resolve => setTimeout(resolve, 30));
      return response();
    };
    await Promise.all([deliverMail(db, mail.id, 'fake', { fetch: fakeFetch }), deliverMail(db, mail.id, 'fake', { fetch: fakeFetch })]);
    assert.equal(requests, 1);
    assert.equal((await mail.ref.get()).get('status'), 'accepted');
    assert.equal((await db.doc(`notificationPayloads/${mail.id}`).get()).exists, false);
  });

  await t.test('401 stops immediately; 429 schedules retry respecting Retry-After', async () => {
    const unauthorized = await job(); let requests = 0;
    await deliverMail(db, unauthorized.id, 'fake', { fetch: async () => { requests++; return response(401, { code: 'unauthorized' }); } });
    assert.equal(requests, 1);
    assert.equal((await unauthorized.ref.get()).get('status'), 'failed');
    const limited = await job(); const now = Date.now();
    await deliverMail(db, limited.id, 'fake', { now: () => now, fetch: async () => response(429, {}, { 'retry-after': '3600' }) });
    const state = await limited.ref.get();
    assert.equal(state.get('status'), 'retry');
    assert.ok(state.get('nextAttemptAt').toMillis() >= now + 3600000);
    assert.equal(state.get('uncertainSince'), null);
  });

  await t.test('lost provider response reuses exact payload and key, recognizes duplicate acceptance', async () => {
    const mail = await job(); const bodies: string[] = []; let now = Date.now();
    await deliverMail(db, mail.id, 'fake', { now: () => now, fetch: async (_url, init) => { bodies.push(String(init?.body)); throw new Error('response lost'); } });
    now = (await mail.ref.get()).get('nextAttemptAt').toMillis();
    await deliverMail(db, mail.id, 'fake', { now: () => now, fetch: async (_url, init) => { bodies.push(String(init?.body)); return response(400, { code: 'duplicate_parameter' }); } });
    assert.equal(bodies.length, 2); assert.equal(bodies[0], bodies[1]);
    assert.equal((await mail.ref.get()).get('status'), 'accepted');
  });

  await t.test('incomplete success responses preserve payload and uncertainty until verified acceptance', async () => {
    for (const raw of ['null', '{}', 'not-json', '{"messageId":42}']) {
      const mail = await job(); let now = Date.now(); const bodies: string[] = [];
      await deliverMail(db, mail.id, 'fake', { now: () => now, fetch: async (_url, init) => {
        bodies.push(String(init?.body)); return new Response(raw, { status: 201 });
      } });
      const state = await mail.ref.get();
      assert.equal(state.get('status'), 'retry');
      assert.equal(state.get('lastError'), 'provider_invalid_response');
      assert.equal(state.get('uncertainSince').toMillis(), now);
      assert.equal((await db.doc(`notificationPayloads/${mail.id}`).get()).exists, true);
      now = state.get('nextAttemptAt').toMillis();
      await deliverMail(db, mail.id, 'fake', { now: () => now, fetch: async (_url, init) => {
        bodies.push(String(init?.body)); return response();
      } });
      assert.equal(bodies[0], bodies[1]);
      assert.equal((await mail.ref.get()).get('status'), 'accepted');
    }
  });

  await t.test('account issues can be manually retried after correction without exposing provider text', async () => {
    for (const code of ['not_enough_credits', 'account_under_validation']) {
      const mail = await job();
      await deliverMail(db, mail.id, 'fake', { fetch: async () => response(400, { code, message: 'private-provider-detail' }) });
      const state = await mail.ref.get();
      assert.equal(state.get('status'), 'failed');
      assert.equal(state.get('retryable'), true);
      assert.equal(state.get('uncertainSince'), null);
      assert.equal(state.get('lastError'), `provider_http_400:${code}`);
      assert.ok(!JSON.stringify(state.data()).includes('private-provider-detail'));
      assert.equal((await db.doc(`notificationPayloads/${mail.id}`).get()).exists, true);
    }
  });

  await t.test('malformed error responses and permanent address errors never count as acceptance', async () => {
    const mail = await job();
    await deliverMail(db, mail.id, 'fake', { fetch: async () => new Response('null', { status: 400 }) });
    assert.equal((await mail.ref.get()).get('status'), 'failed');
    const invalid = await job();
    await deliverMail(db, invalid.id, 'fake', { fetch: async () => response(400, { code: 'invalid_parameter' }) });
    const state = await invalid.ref.get();
    assert.equal(state.get('status'), 'failed');
    assert.equal(state.get('retryable'), false);
    assert.equal(state.get('lastError'), 'provider_http_400:invalid_parameter');
  });

  await t.test('failure to journal acceptance does not resend within the same execution', async () => {
    const mail = await job(); let requests = 0; let failNextTransaction = false;
    const faultyDb = new Proxy(db, { get(target, property) {
      if (property === 'runTransaction') return (...args: any[]) => {
        if (failNextTransaction) { failNextTransaction = false; return Promise.reject(new Error('Firestore unavailable')); }
        return (target.runTransaction as any)(...args);
      };
      const value = Reflect.get(target, property); return typeof value === 'function' ? value.bind(target) : value;
    } }) as Firestore;
    await assert.rejects(deliverMail(faultyDb, mail.id, 'fake', { fetch: async () => { requests++; failNextTransaction = true; return response(); } }));
    assert.equal(requests, 1);
    assert.equal((await mail.ref.get()).get('status'), 'sending');
    const now = (await mail.ref.get()).get('nextAttemptAt').toMillis();
    await deliverMail(db, mail.id, 'fake', { now: () => now, fetch: async () => response(400, { code: 'duplicate_parameter' }) });
    assert.equal((await mail.ref.get()).get('status'), 'accepted');
  });

  await t.test('expired uncertainty stops automatic sending beyond provider deduplication window', async () => {
    const mail = await job(); const now = Date.now();
    await mail.ref.update({ status: 'sending', nextAttemptAt: Timestamp.fromMillis(now - 1), uncertainSince: Timestamp.fromMillis(now - SAFE_RETRY_WINDOW_MS - 1) });
    await deliverMail(db, mail.id, 'fake', { fetch: async () => { throw new Error('must not send'); } });
    assert.equal((await mail.ref.get()).get('status'), 'unknown');
  });

  await t.test('authenticated webhook wins over send completion and ignores duplicates/out-of-order events', async () => {
    const mail = await job(); const ts = Math.floor(Date.now() / 1000);
    const event = { event: 'delivered', 'X-Mailin-custom': `classcard-delivery:${mail.id}`, email: mail.get('recipient.email'), 'message-id': 'test-message@brevo.test', ts_event: ts };
    await deliverMail(db, mail.id, 'fake', { fetch: async () => { await recordDeliveryWebhook(db, event); return response(); } });
    await recordDeliveryWebhook(db, event);
    await recordDeliveryWebhook(db, { ...event, event: 'sent', ts_event: ts - 1 });
    await recordDeliveryWebhook(db, { ...event, event: 'hard_bounce', email: 'other@example.test', ts_event: ts + 1 });
    assert.equal((await mail.ref.get()).get('status'), 'delivered');
    assert.equal((await db.collection('notificationWebhookReceipts').where('deliveryId', '==', mail.id).get()).size, 2);
  });

  await t.test('legacy mail logs are never automatically replayed', async () => {
    const ref = db.collection('mail').doc(randomUUID());
    await ref.set({ status: 'pending', nextAttemptAt: Timestamp.now() });
    let requests = 0;
    await deliverMail(db, ref.id, 'fake', { fetch: async () => { requests++; return response(); } });
    assert.equal(requests, 0);
  });

  await t.test('invitations are committed with profiles; reset links never appear in the mail journal', async () => {
    const f = await fixture();
    const result = await api.createCoach.run(call(f.ids.admin, { academyId: f.ids.academy, email: `${randomUUID()}@example.test`, displayName: 'New Coach', specialties: [] }));
    assert.equal(result.emailStatus, 'queued'); assert.ok(result.resetLink);
    const event = await db.doc(`notificationEvents/${result.emailEventId}`).get();
    assert.equal(event.get('kind'), 'invitation');
    assert.equal((await db.doc(`coaches/${result.uid}`).get()).exists, true);
    // Auth emulator generates local http links. Use an HTTPS fixture for rendering.
    await event.ref.update({ actionUrl: 'https://example.test/reset?oobCode=private-test-token' });
    await expandEvent(db, event.id, '');
    const mail = await db.doc(`mail/${result.emailDeliveryId}`).get();
    assert.equal(mail.get('status'), 'queued');
    assert.ok(!JSON.stringify(mail.data()).includes('private-test-token'));
    assert.equal((await event.ref.get()).get('actionUrl'), undefined);
    await deliverMail(db, mail.id, 'fake', { checkInvitation: async () => false, fetch: async () => { throw new Error('must not send'); } });
    assert.equal((await mail.ref.get()).get('lastError'), 'invitation_account_unavailable');
    const admin = await api.createAdministrator.run(call(f.ids.admin, { email: `${randomUUID()}@example.test`, displayName: 'New Admin', role: 'booking_manager', academyIds: [f.ids.academy] }));
    assert.equal(admin.emailStatus, 'queued');
    assert.equal((await db.doc(`notificationEvents/${admin.emailEventId}`).get()).get('audience'), 'administrator');
  });

  await t.test('expired invitation is not sent and cannot be blindly retried', async () => {
    const batch = db.batch();
    const id = queueEvent(batch, { kind: 'invitation', audience: 'coach', userId: 'missing', academyId: null, recipientEmail: 'a@example.test', recipientName: 'A', actionUrl: 'https://example.test/reset', language: 'en', requestedBy: 'admin' });
    await batch.commit(); await db.doc(`notificationEvents/${id}`).update({ createdAt: Timestamp.fromMillis(Date.now() - 3600000) });
    await expandEvent(db, id, '');
    const mail = (await db.collection('mail').where('eventId', '==', id).get()).docs[0]!;
    assert.equal(mail.get('status'), 'failed'); assert.equal(mail.get('lastError'), 'invitation_expired');
  });

  await t.test('notification journal and retry endpoints enforce authentication and academy scope', async () => {
    const f = await fixture();
    const id = await f.queue(); await expandEvent(db, id, '');
    const mail = (await f.jobs(id))[0]!;
    await deliverMail(db, mail.id, 'fake', { fetch: async () => response(401) });
    await assert.rejects(api.listNotificationDeliveries.run({ data: {} } as any));
    for (const data of [{}, { deliveryId: mail.id }, { deliveryId: 'missing-delivery' }]) {
      await assert.rejects(api.retryNotificationDelivery.run({ data } as any), { code: 'unauthenticated' });
    }
    await db.doc(`users/${f.ids.admin}`).update({ role: 'admin' });
    await assert.rejects(api.listNotificationDeliveries.run(call(f.ids.admin, { academyId: 'other' })));
    const list = await api.listNotificationDeliveries.run(call(f.ids.admin, { academyId: f.ids.academy }));
    assert.equal(list.deliveries.length, 3);
    await api.retryNotificationDelivery.run(call(f.ids.admin, { deliveryId: mail.id }));
    assert.equal((await mail.ref.get()).get('status'), 'queued');
    await mail.ref.update({ status: 'unknown', retryable: false });
    await assert.rejects(api.retryNotificationDelivery.run(call(f.ids.admin, { deliveryId: mail.id })));
  });

  await t.test('bulk cancellation crosses batch boundary without losing events or changing quotas', async () => {
    const f = await fixture();
    const batch = db.batch();
    for (let index = 0; index < 151; index++) batch.set(db.doc(`bookings/${f.bookingId}-${index}`), f.booking);
    batch.update(db.doc(`sessions/${f.ids.session}`), { bookedCount: 151 });
    await batch.commit();
    const result = await api.softDeletePlayerBookings.run(call(f.ids.admin, { playerId: f.ids.player }));
    assert.equal(result.deletedCount, 151);
    assert.equal((await db.collection('notificationEvents').where('academyId', '==', f.ids.academy).get()).size, 151);
    assert.equal((await db.doc(`sessions/${f.ids.session}`).get()).get('bookedCount'), 0);
    assert.equal((await db.doc(`players/${f.ids.player}`).get()).get('remainingSessions'), 8);
  });

  await t.test('coach resend is permission checked and rate limited across concurrent calls', async () => {
    const f = await fixture();
    const coach = await api.createCoach.run(call(f.ids.admin, { academyId: f.ids.academy, email: `${randomUUID()}@example.test`, displayName: 'Coach', specialties: [] }));
    await assert.rejects(api.resendCoachPasswordLink.run(call(f.ids.parent, { coachId: coach.id })));
    const [a, b] = await Promise.all([
      api.resendCoachPasswordLink.run(call(f.ids.admin, { coachId: coach.id })),
      api.resendCoachPasswordLink.run(call(f.ids.admin, { coachId: coach.id })),
    ]);
    assert.equal(a.emailEventId, b.emailEventId);
    assert.equal(a.resetLink, b.resetLink);
    assert.equal((await db.collection('notificationEvents').where('userId', '==', coach.id).get()).size, 2);
  });

  await t.test('Firestore rules deny direct access to payloads and queue, even for a root client', async () => {
    const signUp = await fetch(`http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=demo-key`, {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ email: `${randomUUID()}@example.test`, password: 'test-password-only', returnSecureToken: true }),
    });
    assert.equal(signUp.status, 200);
    const { localId, idToken } = await signUp.json() as { localId: string; idToken: string };
    await db.doc(`users/${localId}`).set({ role: 'root', status: 'active', permissions: ['admins.manage'] });
    const base = `http://${process.env.FIRESTORE_EMULATOR_HOST}/v1/projects/${projectId}/databases/(default)/documents`;
    const headers = { authorization: `Bearer ${idToken}`, 'content-type': 'application/json' };
    assert.equal((await fetch(`${base}/users/${localId}`, { headers })).status, 200);
    for (const collection of ['mail', 'notificationEvents', 'notificationPayloads', 'notificationWebhookReceipts', 'bookingReminders']) {
      const id = randomUUID(); await db.doc(`${collection}/${id}`).set({ privateValue: 'private-test-data' });
      assert.equal((await fetch(`${base}/${collection}/${id}`, { headers })).status, 403, `${collection} read`);
      assert.equal((await fetch(`${base}/${collection}/${id}`, { method: 'PATCH', headers, body: JSON.stringify({ fields: { status: { stringValue: 'queued' } } }) })).status, 403, `${collection} write`);
    }
  });

  await t.test('lost invitation commit acknowledgement preserves the committed Auth account and event', async () => {
    const f = await fixture();
    const originalBatch = db.batch.bind(db);
    db.batch = () => {
      const batch = originalBatch(); const commit = batch.commit.bind(batch);
      batch.commit = async () => { await commit(); throw new Error('commit acknowledgement lost'); };
      return batch;
    };
    try {
      const result = await api.createCoach.run(call(f.ids.admin, { academyId: f.ids.academy, email: `${randomUUID()}@example.test`, displayName: 'Coach', specialties: [] }));
      assert.equal(result.emailStatus, 'queued');
      assert.equal((await getAuth().getUser(result.uid)).disabled, false);
      assert.equal((await db.doc(`notificationEvents/${result.emailEventId}`).get()).exists, true);
    } finally { db.batch = originalBatch; }
  });

  async function futureReminder() {
    const f = await fixture();
    const startsAt = Date.now() + 72 * 3600000;
    f.booking.startsAt = Timestamp.fromMillis(startsAt);
    f.booking.endsAt = Timestamp.fromMillis(startsAt + 3600000);
    await db.doc(`bookings/${f.bookingId}`).set(f.booking);
    await db.doc(`sessions/${f.ids.session}`).update({ bookedCount: 1 });
    await f.queue();
    return { ...f, due: startsAt - 24 * 3600000 };
  }

  await t.test('one user reminder is scheduled exactly 24 hours before the lesson, never before due time', async () => {
    const f = await futureReminder();
    const reminderRef = db.doc(`bookingReminders/${f.bookingId}`);
    assert.equal((await reminderRef.get()).get('nextAttemptAt').toMillis(), f.due);
    await queueDueReminder(db, f.bookingId, f.due - 1);
    assert.equal((await f.events()).length, 1);
    await Promise.all([queueDueReminder(db, f.bookingId, f.due), queueDueReminder(db, f.bookingId, f.due)]);
    const events = await f.events();
    assert.equal(events.length, 2);
    const event = events.find(event => event.get('event') === 'reminder')!;
    await expandEvent(db, event.id, 'fallback@example.test');
    const jobs = await f.jobs(event.id);
    assert.equal(jobs.length, 1);
    assert.equal(jobs[0]!.get('recipient.email'), 'parent@example.test');
    const body = (await db.doc(`notificationPayloads/${jobs[0]!.id}`).get()).get('body');
    assert.match(body.subject, /lesson reminder/);
    let requests = 0;
    await deliverMail(db, jobs[0]!.id, 'fake', { now: () => f.due, fetch: async () => { requests++; return response(); } });
    await queueDueReminder(db, f.bookingId, f.due + 60000);
    assert.equal(requests, 1); assert.equal((await f.events()).length, 2);
    assert.equal((await db.doc(`players/${f.ids.player}`).get()).get('remainingSessions'), 8);
  });

  await t.test('cancellation suppresses an already queued reminder before sending', async () => {
    const f = await futureReminder();
    await queueDueReminder(db, f.bookingId, f.due);
    const event = (await f.events()).find(event => event.get('event') === 'reminder')!;
    await expandEvent(db, event.id, '');
    const mail = (await f.jobs(event.id))[0]!;
    await api.cancelBooking.run(call(f.ids.admin, { bookingId: f.bookingId }));
    let requests = 0;
    await deliverMail(db, mail.id, 'fake', { now: () => f.due, fetch: async () => { requests++; return response(); } });
    assert.equal(requests, 0); assert.equal((await mail.ref.get()).get('status'), 'skipped');
    assert.equal((await db.doc(`bookingReminders/${f.bookingId}`).get()).get('status'), 'cancelled');
  });

  await t.test('a reminder from an earlier booking incarnation cannot reach a recreated booking', async () => {
    const f = await futureReminder();
    await queueDueReminder(db, f.bookingId, f.due);
    const event = (await f.events()).find(event => event.get('event') === 'reminder')!;
    await expandEvent(db, event.id, '');
    const mail = (await f.jobs(event.id))[0]!;
    await f.queue(); // New occurrence/version for the same booking identity.
    let requests = 0;
    await deliverMail(db, mail.id, 'fake', { now: () => f.due, fetch: async () => { requests++; return response(); } });
    assert.equal(requests, 0); assert.equal((await mail.ref.get()).get('status'), 'skipped');
  });

  await t.test('pending bookings and bookings created within 24 hours do not send an immediate reminder', async () => {
    const f = await futureReminder();
    f.booking.status = 'pending'; await f.queue();
    await db.doc(`bookings/${f.bookingId}`).update({ status: 'pending' });
    await queueDueReminder(db, f.bookingId, f.due);
    assert.equal((await f.events()).filter(event => event.get('event') === 'reminder').length, 0);
    assert.equal((await db.doc(`bookingReminders/${f.bookingId}`).get()).get('status'), 'awaiting_confirmation');
    f.booking.status = 'confirmed'; f.booking.startsAt = Timestamp.fromMillis(Date.now() + 12 * 3600000);
    await f.queue();
    assert.equal((await db.doc(`bookingReminders/${f.bookingId}`).get()).get('status'), 'skipped');
    assert.equal((await db.doc(`bookingReminders/${f.bookingId}`).get()).get('nextAttemptAt'), undefined);
  });

  await t.test('reminders recovered after the lesson has started are discarded', async () => {
    const f = await futureReminder();
    await queueDueReminder(db, f.bookingId, f.due + 24 * 3600000 + 1);
    assert.equal((await f.events()).filter(event => event.get('event') === 'reminder').length, 0);
    assert.equal((await db.doc(`bookingReminders/${f.bookingId}`).get()).get('status'), 'skipped');
  });

  await t.test('existing future bookings can be backfilled without sending creation emails or duplicating reminders', async () => {
    const f = await fixture();
    await db.doc(`bookings/${f.bookingId}`).set({ ...f.booking, startsAt: Timestamp.fromMillis(Date.now() + 96 * 3600000) });
    const ref = db.doc(`bookingReminders/${f.bookingId}`);
    const dryRun = await backfillBookingReminders(db);
    assert.ok(dryRun.eligible >= 1); assert.equal((await ref.get()).exists, false);
    await backfillBookingReminders(db, true);
    const first = await ref.get();
    assert.equal(first.get('status'), 'scheduled');
    await backfillBookingReminders(db, true);
    assert.equal((await ref.get()).get('version'), first.get('version'));
    assert.equal((await f.events()).length, 0);
  });
});
