import assert from 'node:assert/strict';
import test from 'node:test';
import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';

test('SportA tenant isolation, roles, expiry and concurrent quotas on real emulators', { skip: !process.env.FIRESTORE_EMULATOR_HOST }, async t => {
  assert.equal(process.env.GCLOUD_PROJECT, 'demo-sporta');
  initializeApp({ projectId: 'demo-sporta' });
  const db = getFirestore(); const auth = getAuth();
  const tokens: Record<string, string> = {};
  for (const uid of ['test-operator', 'test-owner-a', 'test-owner-b', 'test-parent-a', 'test-member-a', 'test-member-b']) {
    const email = `${uid}@sporta.test`;
    try { await auth.getUser(uid); } catch { await auth.createUser({ uid, email, password: 'Local-test-only-2026!' }); }
    const response = await fetch(`http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=demo-key`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password: 'Local-test-only-2026!', returnSecureToken: true }) });
    const data = await response.json() as { idToken: string }; tokens[uid] = data.idToken;
    assert.ok(data.idToken);
  }
  await db.doc('platformOperators/test-operator').set({ status: 'active' });
  for (const suffix of ['a', 'b']) {
    await db.doc(`academies/test-${suffix}`).set({ name: `Test ${suffix}`, status: 'active' });
    await db.doc(`academies/test-${suffix}/members/test-owner-${suffix}`).set({ status: 'active', role: 'owner' });
    await db.doc(`academies/test-${suffix}/usage/current`).set({ players: 0, staff: 1 });
    await db.doc(`academySubscriptions/test-${suffix}`).set({ status: 'active', maxPlayers: 1, maxStaff: 2, endsAt: Timestamp.fromMillis(Date.now() + 86400000) });
  }
  await db.doc('academies/test-a/members/test-parent-a').set({ status: 'active', role: 'parent' });
  const call = async (uid: string, name: string, data: object) => {
    const response = await fetch(`http://127.0.0.1:5001/demo-sporta/europe-west1/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json', ...(uid ? { Authorization: `Bearer ${tokens[uid]}` } : {}) }, body: JSON.stringify({ data }) });
    return { status: response.status, body: await response.json() as { result?: unknown; error?: { status: string } } };
  };
  const read = async (uid: string, path: string) => fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/v1/projects/demo-sporta/databases/(default)/documents/${path}`, { headers: { Authorization: `Bearer ${tokens[uid]}` } });
  await t.test('unauthenticated and non-operators cannot administer plans', async () => {
    for (const uid of ['', 'test-owner-a']) assert.ok((await call(uid, 'platformSavePlan', { planId: 'basic', name: 'Basic', maxPlayers: 5, maxStaff: 2 })).status >= 400);
    assert.equal((await call('test-operator', 'platformSavePlan', { planId: 'basic', name: 'Basic', maxPlayers: 5, maxStaff: 2 })).status, 200);
  });
  await t.test('academy creation provisions owner and duplicate identifiers are rejected', async () => {
    const data = { academyId: 'new-academy', name: 'New Academy', country: 'Cameroon', ownerEmail: 'test-owner-a@sporta.test' };
    assert.equal((await call('test-operator', 'platformCreateAcademy', data)).status, 200);
    assert.equal((await db.doc('academies/new-academy/members/test-owner-a').get()).get('role'), 'owner');
    assert.ok((await call('test-operator', 'platformCreateAcademy', data)).status >= 400);
  });
  await t.test('activation is idempotent and snapshots plan quotas', async () => {
    const data = { academyId: 'new-academy', planId: 'basic', durationDays: 30, note: 'Test access', requestId: 'test-activation' };
    assert.equal((await call('test-operator', 'platformActivateSubscription', data)).status, 200);
    const first = await db.doc('academySubscriptions/new-academy').get();
    assert.equal((await call('test-operator', 'platformActivateSubscription', data)).status, 200);
    assert.equal((await db.doc('academySubscriptions/new-academy').get()).get('endsAt').toMillis(), first.get('endsAt').toMillis());
    await call('test-operator', 'platformSavePlan', { planId: 'basic', name: 'Updated', maxPlayers: 10, maxStaff: 3 });
    assert.equal((await db.doc('academySubscriptions/new-academy').get()).get('maxPlayers'), 5);
  });
  await t.test('tenant A cannot read tenant B or write players into B', async () => {
    assert.equal((await read('test-owner-a', 'academies/test-a')).status, 200);
    assert.equal((await read('test-owner-a', 'academies/test-b')).status, 403);
    assert.ok((await call('test-owner-a', 'academyCreatePlayer', { academyId: 'test-b', name: 'Unauthorized' })).status >= 400);
  });
  await t.test('parents cannot create players with staff-only API', async () => {
    assert.ok((await call('test-parent-a', 'academyCreatePlayer', { academyId: 'test-a', name: 'Unauthorized' })).status >= 400);
  });
  await t.test('concurrent creations cannot exceed the plan quota', async () => {
    const results = await Promise.all([1, 2].map(i => call('test-owner-a', 'academyCreatePlayer', { academyId: 'test-a', name: `Player ${i}` })));
    assert.equal(results.filter(result => result.status === 200).length, 1);
    assert.equal((await db.doc('academies/test-a/usage/current').get()).get('players'), 1);
  });
  await t.test('platform operator has no blanket read access to player data', async () => {
    const players = await db.collection('academies/test-a/players').get();
    assert.equal((await read('test-operator', `academies/test-a/players/${players.docs[0]!.id}`)).status, 403);
  });
  await t.test('member management requires the owner of the target academy', async () => {
    const data = { academyId: 'test-b', email: 'test-member-a@sporta.test', role: 'coach', status: 'active' };
    assert.ok((await call('test-owner-a', 'academySetMember', data)).status >= 400);
    assert.ok((await call('test-parent-a', 'academySetMember', { ...data, academyId: 'test-a' })).status >= 400);
  });
  await t.test('simultaneous staff additions respect quota and suspending frees a seat', async () => {
    const results = await Promise.all(['a', 'b'].map(suffix => call('test-owner-a', 'academySetMember', { academyId: 'test-a', email: `test-member-${suffix}@sporta.test`, role: 'coach', status: 'active' })));
    assert.equal(results.filter(result => result.status === 200).length, 1);
    assert.equal((await db.doc('academies/test-a/usage/current').get()).get('staff'), 2);
    const selected = results[0]!.status === 200 ? 'a' : 'b';
    const uid = `test-member-${selected}`;
    assert.equal((await read(uid, 'academies/test-a')).status, 200);
    const data = { academyId: 'test-a', email: `${uid}@sporta.test`, role: 'coach', status: 'suspended' };
    assert.equal((await call('test-owner-a', 'academySetMember', data)).status, 200);
    assert.equal((await read(uid, 'academies/test-a')).status, 403);
    assert.equal((await db.doc(`users/${uid}/memberships/test-a`).get()).exists, false);
    assert.equal((await db.doc('academies/test-a/usage/current').get()).get('staff'), 1);
    assert.equal((await call('test-owner-a', 'academySetMember', data)).status, 200);
    assert.equal((await db.doc('academies/test-a/usage/current').get()).get('staff'), 1);
  });
  await t.test('owner cannot be demoted or suspended through member editing', async () => {
    const data = { academyId: 'test-a', email: 'test-owner-a@sporta.test', role: 'manager', status: 'suspended' };
    assert.ok((await call('test-operator', 'platformSetMember', data)).status >= 400);
  });
  await t.test('platform can manage membership without accessing player records', async () => {
    const data = { academyId: 'test-b', email: 'test-member-a@sporta.test', role: 'parent', status: 'active' };
    assert.equal((await call('test-operator', 'platformSetMember', data)).status, 200);
    assert.equal((await read('test-operator', 'academies/test-b/members/test-member-a')).status, 200);
    assert.equal((await db.doc('academies/test-b/usage/current').get()).get('staff'), 1);
  });
  await t.test('expired subscription blocks creation immediately', async () => {
    await db.doc('academySubscriptions/test-b').update({ endsAt: Timestamp.fromMillis(Date.now() - 1000) });
    assert.ok((await call('test-owner-b', 'academyCreatePlayer', { academyId: 'test-b', name: 'Blocked' })).status >= 400);
  });
  await t.test('suspended academy loses read access', async () => {
    await db.doc('academies/test-b').update({ status: 'suspended' });
    assert.equal((await read('test-owner-b', 'academies/test-b')).status, 403);
  });
  await t.test('client writes cannot promote a member or change quotas', async () => {
    const response = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/v1/projects/demo-sporta/databases/(default)/documents/academies/test-a/members/test-owner-a`, { method: 'PATCH', headers: { Authorization: `Bearer ${tokens['test-owner-a']}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ fields: { role: { stringValue: 'owner' }, status: { stringValue: 'active' } } }) });
    assert.equal(response.status, 403);
  });
});
