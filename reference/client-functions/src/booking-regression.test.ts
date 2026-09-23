import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';
import { join } from 'node:path';
import ts from 'typescript';
import * as domain from './domain.js';

// Execute the actual callable with an in-memory Firestore boundary. No production writes.
const source = ts.transpileModule(readFileSync(join(__dirname, '../src/index.ts'), 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
}).outputText;

type Data = Record<string, any>;
function fixture(change: (rows: Record<string, Data>) => void = () => {}) {
  const stamp = (value: number) => ({ toMillis: () => value });
  const start = Date.now() + 86400000;
  const rows: Record<string, Data> = {
    'users/staff': { status: 'active', role: 'booking_manager', academyIds: ['academy'] },
    'sessions/slot': { academyId: 'academy', configurationId: 'young', configurationType: 'group', activityType: 'tennis', status: 'open', capacity: 4, bookedCount: 0, startsAt: stamp(start), endsAt: stamp(start + 3600000) },
    'players/player': { academyId: 'academy', communityId: 'community', status: 'active', age: 35, sessionConfigurationId: 'adult', remainingSessions: 5 },
    'sessionConfigurations/young': { academyId: 'academy', type: 'group', activityType: 'tennis', active: true, minAge: 5, maxAge: 12, price: 50, currency: 'AED' },
    'sessionConfigurations/adult': { academyId: 'academy', type: 'group', activityType: 'tennis', active: true, minAge: 18, maxAge: 80, price: 100, currency: 'AED' },
    'communityCourses/course': { communityId: 'community', academyId: 'academy', active: true },
    'communities/community': { name: 'Slot community' },
  };
  change(rows);
  const writes: Array<{ path: string; data: Data }> = [];
  const snapshot = (path: string): any => ({ id: path.split('/').at(-1), exists: !!rows[path], get: (key: string) => rows[path]?.[key], data: () => rows[path], ref: ref(path) });
  function ref(path: string): any { return { path, id: path.split('/').at(-1), get: async () => snapshot(path), collection: (name: string) => collection(`${path}/${name}`) }; }
  function collection(path: string, filters: Array<[string, string, any]> = []): any {
    return { path, doc: (id: string) => ref(`${path}/${id}`), where: (key: string, op: string, value: any) => collection(path, [...filters, [key, op, value]]), get: async () => ({ docs: Object.keys(rows).filter(key => key.startsWith(`${path}/`) && !key.slice(path.length + 1).includes('/')).filter(key => filters.every(([field, op, value]) => op === '==' ? rows[key]![field] === value : rows[key]![field]?.toMillis() < value.toMillis())).map(snapshot) }) };
  }
  const db = { collection, runTransaction: async (callback: any) => callback({ get: (target: any) => target.get(), create: (target: any, data: Data) => writes.push({ path: target.path, data }), set: (target: any, data: Data) => writes.push({ path: target.path, data }), update: () => {} }) };
  class HttpsError extends Error { constructor(public code: string, message: string) { super(message); } }
  const exports: any = {};
  const imports: Data = {
    'firebase-admin/app': { getApps: () => [true] },
    'firebase-admin/firestore': { getFirestore: () => db, FieldValue: { serverTimestamp: () => null, increment: (n: number) => n } },
    'firebase-functions/v2/https': { HttpsError, onCall: (_: any, fn: any) => fn },
    'firebase-functions/v2/options': { setGlobalOptions: () => {} },
    './domain.js': domain,
    './authorization.js': {}, './management.js': {},
    './notifications/outbox.js': { queueBookingNotification: () => 'test-event' },
    './notifications/functions.js': {},
  };
  vm.runInNewContext(source, { exports, require: (name: string) => { assert.ok(name in imports, name); return imports[name]; } });
  return { run: () => exports.createBooking({ auth: { uid: 'staff' }, data: { sessionId: 'slot', playerId: 'player', communityCourseId: 'course' } }), writes };
}

test('admin groups different ages and preserves the player package and price', async () => {
  const f = fixture();
  assert.equal((await f.run()).status, 'confirmed');
  assert.equal(f.writes[0]?.data.sessionConfigurationId, 'adult');
  assert.equal(f.writes[0]?.data.amount, 100);
  assert.equal(f.writes[0]?.data.courseDebited, false);
});
test('same-package booking remains supported', async () => {
  const f = fixture(rows => { rows['players/player']!.sessionConfigurationId = 'young'; rows['players/player']!.age = 8; });
  await f.run();
  assert.equal(f.writes[0]?.data.amount, 50);
});
for (const [name, change] of Object.entries<Record<string, any>>({
  'different academy': { 'players/player': { academyId: 'other' } },
  'deleted player': { 'players/player': { isDelete: true } },
  'inactive course': { 'communityCourses/course': { active: false } },
  'deleted course': { 'communityCourses/course': { isDelete: true } },
  'unauthorized academy': { 'users/staff': { academyIds: ['other'] } },
  'suspended administrator': { 'users/staff': { status: 'suspended' } },
  'client cannot bypass age restriction': { 'users/staff': { role: 'student' }, 'users/staff/players/player': {} },
})) {
  test(`rejects ${name}`, async () => {
    const f = fixture(rows => { for (const [path, data] of Object.entries(change)) rows[path] = { ...rows[path], ...data }; });
    await assert.rejects(f.run());
    assert.equal(f.writes.length, 0);
  });
}
test('admin can create an overlapping reservation', async () => {
  const f = fixture(rows => { rows['bookings/overlap'] = { playerId: 'player', status: 'confirmed', startsAt: rows['sessions/slot']!.startsAt, endsAt: rows['sessions/slot']!.endsAt }; });
  assert.equal((await f.run()).status, 'confirmed');
  assert.equal(f.writes.length, 1);
});
test('client same-package booking retains pending status', async () => {
  const f = fixture(rows => { rows['users/staff']!.role = 'student'; rows['users/staff']!.academyIds = []; rows['users/staff/players/player'] = {}; rows['sessions/slot']!.configurationId = 'adult'; });
  assert.equal((await f.run()).status, 'pending');
});

test('admin can book a player from another community on the same slot', async () => {
  const f = fixture(rows => { rows['players/player']!.communityId = 'other'; rows['players/player']!.communityName = 'Player community'; });
  assert.equal((await f.run()).status, 'confirmed');
  assert.equal(f.writes[0]?.data.communityId, 'community');
  assert.equal(f.writes[0]?.data.communityName, 'Slot community');
});
test('client cannot book a course from another community', async () => {
  const f = fixture(rows => {
    rows['users/staff']!.role = 'student'; rows['users/staff']!.academyIds = [];
    rows['users/staff/players/player'] = {}; rows['sessions/slot']!.configurationId = 'adult';
    rows['players/player']!.communityId = 'other';
  });
  await assert.rejects(f.run(), /communauté/);
  assert.equal(f.writes.length, 0);
});

for (const [name, change] of Object.entries<Record<string, any>>({
  'exhausted quota': { 'players/player': { remainingSessions: 0 } },
  'different sport': { 'sessionConfigurations/adult': { activityType: 'padel' } },
  'different session type': { 'sessionConfigurations/adult': { type: 'private' } },
  'inactive package': { 'sessionConfigurations/adult': { active: false } },
  'full slot': { 'sessions/slot': { bookedCount: 4 } },
  'closed slot': { 'sessions/slot': { status: 'closed' } },
  'course from another academy': { 'communityCourses/course': { academyId: 'other' } },
  'no package': { 'players/player': { sessionConfigurationId: null, remainingSessions: 0 } },
  'missing age': { 'players/player': { age: null } },
  'pending cash payment': { 'players/player': { status: 'pending_cash_confirmation', paymentStatus: 'cash_pending', remainingSessions: 0 } },
  'another authorized academy': { 'users/staff': { academyIds: ['academy', 'other'] }, 'players/player': { academyId: 'other' } },
})) {
  test(`admin can override ${name}`, async () => {
    const f = fixture(rows => { for (const [path, data] of Object.entries(change)) rows[path] = { ...rows[path], ...data }; });
    assert.equal((await f.run()).status, 'confirmed');
    assert.equal(f.writes.length, 1);
  });
}
for (const [name, change] of Object.entries<Record<string, any>>({
  'quota': { 'players/player': { remainingSessions: 0 } },
  'capacity': { 'sessions/slot': { bookedCount: 4 } },
  'package': { 'players/player': { sessionConfigurationId: 'young' } },
  'payment status': { 'players/player': { status: 'pending_cash_confirmation' } },
})) {
  test(`client still respects ${name}`, async () => {
    const f = fixture(rows => {
      rows['users/staff']!.role = 'student'; rows['users/staff']!.academyIds = [];
      rows['users/staff/players/player'] = {}; rows['sessions/slot']!.configurationId = 'adult';
      for (const [path, data] of Object.entries(change)) rows[path] = { ...rows[path], ...data };
    });
    await assert.rejects(f.run());
    assert.equal(f.writes.length, 0);
  });
}
test('client still cannot create an overlapping reservation', async () => {
  const f = fixture(rows => {
    rows['users/staff']!.role = 'student'; rows['users/staff']!.academyIds = [];
    rows['users/staff/players/player'] = {}; rows['sessions/slot']!.configurationId = 'adult';
    rows['bookings/overlap'] = { playerId: 'player', status: 'confirmed', startsAt: rows['sessions/slot']!.startsAt, endsAt: rows['sessions/slot']!.endsAt };
  });
  await assert.rejects(f.run(), /tranche horaire/);
  assert.equal(f.writes.length, 0);
});
