import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';
import vm from 'node:vm';
import ts from 'typescript';
import * as domain from './domain.js';
const source = ts.transpileModule(readFileSync(join(__dirname, '../src/management.ts'), 'utf8'), { compilerOptions: { module: ts.ModuleKind.CommonJS } }).outputText;
type Data = Record<string, any>;
function fixture(change: (rows: Data) => void = () => {}, role = 'root') {
  const rows: Data = {
    'players/player': { status: 'pending_cash_confirmation', paymentStatus: 'cash_pending', paymentMethod: 'cash', sessionCount: 10, remainingSessions: 0, paymentAmount: 500, paymentCurrency: 'AED', academyId: 'academy', sessionConfigurationId: 'package' },
    'sessionConfigurations/package': { price: 600, currency: 'AED' },
    'systemSettings/dashboard': { validatedRevenueAmount: 11000, validatedRevenueCurrency: 'AED' },
  };
  change(rows);
  const db = {
    collection: (path: string) => ({ doc: (id: string) => ({ path: `${path}/${id}` }), add: async () => {} }),
    runTransaction: async (fn: any) => {
      const writes: Array<() => void> = [];
      const write = (ref: any, data: Data) => writes.push(() => { rows[ref.path] = { ...rows[ref.path], ...data }; });
      const result = await fn({ get: async (ref: any) => ({ exists: !!rows[ref.path], get: (key: string) => rows[ref.path]?.[key] }), set: write, update: write });
      writes.forEach(write => write()); return result;
    },
  };
  class HttpsError extends Error { constructor(public code: string, message: string) { super(message); } }
  const imports: Data = {
    'node:crypto': {}, 'firebase-admin/app': { getApps: () => [true] }, 'firebase-admin/auth': {}, 'firebase-admin/storage': {},
    'firebase-admin/firestore': { getFirestore: () => db, FieldValue: { serverTimestamp: () => 'timestamp' } },
    'firebase-functions/v2/https': { HttpsError, onCall: (_: any, fn: any) => fn },
    './authorization.js': { parseString: (s: string) => s, requirePermission: async () => ({ uid: 'admin', role, academyIds: ['academy'] }) },
    './domain.js': domain, './notifications.js': {}, './notifications/outbox.js': {},
  };
  const exports: any = {};
  vm.runInNewContext(source, { exports, require: (name: string) => { assert.ok(name in imports, name); return imports[name]; } });
  return { rows, confirm: () => exports.confirmCashPlayerPayment({ auth: { uid: 'admin' }, data: { playerId: 'player' } }), edit: () => exports.updateValidatedRevenue({ auth: { uid: 'admin' }, data: { amount: 15000, currency: 'AED' } }) };
}
test('cash enters revenue only once on confirmation and preserves the registration price', async () => {
  const f = fixture();
  assert.equal(f.rows['systemSettings/dashboard'].confirmedCashTotals, undefined);
  await f.confirm();
  assert.equal(f.rows['players/player'].paymentStatus, 'confirmed');
  assert.equal(f.rows['players/player'].remainingSessions, 10);
  assert.equal(f.rows['systemSettings/dashboard'].confirmedCashTotals.AED, 500);
  assert.equal((await f.confirm()).alreadyConfirmed, true);
  assert.equal(f.rows['systemSettings/dashboard'].confirmedCashTotals.AED, 500);
});
test('legacy pending payments capture the package price at confirmation', async () => {
  const f = fixture(rows => { delete rows['players/player'].paymentAmount; });
  await f.confirm(); assert.equal(f.rows['systemSettings/dashboard'].confirmedCashTotals.AED, 600);
});
test('different currencies are never added together', async () => {
  const f = fixture(rows => { rows['players/player'].paymentCurrency = 'EUR'; rows['systemSettings/dashboard'].confirmedCashTotals = { AED: 100 }; });
  await f.confirm(); assert.equal(f.rows['systemSettings/dashboard'].confirmedCashTotals.AED, 100); assert.equal(f.rows['systemSettings/dashboard'].confirmedCashTotals.EUR, 500);
});
test('manual total changes establish a new cash baseline', async () => {
  const f = fixture(); await f.confirm(); await f.edit();
  assert.equal(f.rows['systemSettings/dashboard'].validatedRevenueAmount, 15000);
  assert.equal(f.rows['systemSettings/dashboard'].validatedRevenueCashBaseline.AED, 500);
});
for (const [name, change] of Object.entries<Data>({ deleted: { isDelete: true }, 'non-cash': { paymentMethod: 'card' }, 'invalid amount': { paymentAmount: -1 }, 'other academy': { academyId: 'other' } })) {
  test(`rejects ${name} without accounting changes`, async () => {
    const f = fixture(rows => Object.assign(rows['players/player'], change), 'booking_manager');
    await assert.rejects(f.confirm());
    assert.equal(f.rows['systemSettings/dashboard'].confirmedCashTotals, undefined);
    assert.equal(f.rows['players/player'].paymentStatus, 'cash_pending');
  });
}

test('confirmation freezes invoice details and repeated confirmation preserves them', async () => {
  const f = fixture(rows => {
    Object.assign(rows['players/player'], { displayName: 'Alice', assignedUserId: 'parent', activityType: 'tennis' });
    rows['users/parent'] = { displayName: 'Parent', email: 'parent@example.com', phone: '+123' };
    rows['academies/academy'] = { name: 'Academy', city: 'Dubai', country: 'UAE' };
  });
  await f.confirm();
  const invoice = f.rows['players/player'].invoice;
  assert.equal(invoice.number, 'CASH-player');
  assert.equal(invoice.amount, 500);
  assert.equal(invoice.currency, 'AED');
  assert.equal(invoice.customerName, 'Parent');
  assert.equal(invoice.customerEmail, 'parent@example.com');
  assert.equal(invoice.issuerName, 'Academy');
  assert.equal(invoice.issuerAddress, 'Dubai, UAE');
  assert.ok(Number.isFinite(Date.parse(invoice.issuedAt)));
  f.rows['players/player'].sessionCount = 20;
  f.rows['players/player'].displayName = 'Updated';
  f.rows['users/parent'].displayName = 'Changed';
  await f.confirm();
  assert.equal(f.rows['players/player'].invoice, invoice);
  assert.equal(invoice.sessionCount, 10);
  assert.equal(invoice.playerName, 'Alice');
  assert.equal(invoice.customerName, 'Parent');
});

test('missing academy and customer do not prevent cash confirmation', async () => {
  const f = fixture(rows => { rows['players/player'].academyId = null; });
  await f.confirm();
  assert.equal(f.rows['players/player'].invoice.issuerName, '');
  assert.equal(f.rows['players/player'].invoice.customerName, '');
});
