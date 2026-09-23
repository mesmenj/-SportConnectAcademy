import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';
import ts from 'typescript';
const source = ts.transpileModule(readFileSync(new URL('../src/services/cashPaymentService.ts', import.meta.url), 'utf8'), { compilerOptions: { module: ts.ModuleKind.CommonJS } }).outputText;
function fixture(admin) {
  let listener; let rows; let query;
  const imports = { '../firebase': { db: {} }, 'firebase/firestore': {
    collection: (_, name) => name, where: (...args) => args, query: (...args) => args,
    onSnapshot: (q, next) => { query = q; listener = next; return () => {}; },
  } };
  const exports = {};
  vm.runInNewContext(source, { exports, require: name => imports[name] });
  exports.subscribeCashPayments(admin, data => { rows = data; }, () => assert.fail('unexpected read error'));
  return { get rows() { return rows; }, get query() { return query; }, emit: values => listener({ docs: values.map((data, i) => ({ id: String(i), get: key => data[key] })) }) };
}
test('all pending cash payments remain listed until confirmed; deleted records are omitted', () => {
  const f = fixture({ role: 'root' });
  const pending = { paymentStatus: 'cash_pending', displayName: 'Player', paymentAmount: 500, paymentCurrency: 'AED' };
  f.emit([pending, pending, { ...pending, isDelete: true }]);
  assert.equal(f.rows.filter(row => row.pending).length, 2);
  f.emit([{ ...pending, paymentStatus: 'confirmed' }, pending]);
  assert.equal(f.rows.filter(row => row.pending).length, 1);
  assert.equal(f.rows.filter(row => row.confirmed).length, 1);
});
test('cash reads remain scoped to the administrator academies', () => {
  const f = fixture({ role: 'booking_manager', academyIds: ['academy'] });
  assert.equal(JSON.stringify(f.query), JSON.stringify(['players', ['paymentMethod', '==', 'cash'], ['academyId', 'in', ['academy']]]));
  const empty = fixture({ role: 'booking_manager', academyIds: [] });
  assert.equal(empty.rows.length, 0);
  assert.equal(empty.query, undefined);
});
