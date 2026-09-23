import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';
import ts from 'typescript';

const source = ts.transpileModule(readFileSync(new URL('../src/pages/Dashboard.tsx', import.meta.url), 'utf8') + '\nexports.RevenueCard = RevenueCard;', { compilerOptions: { module: ts.ModuleKind.CommonJS, jsx: ts.JsxEmit.ReactJSX } }).outputText;
function card() {
  const state = []; let index = 0; let subscribed = false; let receive; let fail;
  const calls = [];
  const jsx = (type, props) => ({ type, props });
  const modules = {
    react: { useState: initial => { const i = index++; if (!(i in state)) state[i] = initial; return [state[i], value => { state[i] = value; }]; }, useEffect: effect => { if (!subscribed) { subscribed = true; effect(); } } },
    'react/jsx-runtime': { jsx, jsxs: jsx },
    '@mui/material': new Proxy({}, { get: (_, name) => name }),
    '@mui/icons-material': new Proxy({}, { get: (_, name) => name }),
    'firebase/firestore': { doc: (_, ...path) => path.join('/'), onSnapshot: (path, next, error) => { assert.equal(path, 'systemSettings/dashboard'); receive = next; fail = error; return () => {}; } },
    '../theme': { colors: {} }, '../i18n': { useI18n: () => ({ t: s => s, language: 'fr' }), formatMoney: (amount, currency) => `${amount} ${currency}` },
    '../store/hooks': { useAppSelector: selector => selector({ auth: { user: { role: 'root', uid: 'admin' } } }) },
    '../firebase': { db: {} }, '../services/cashPaymentService': {},
    '../services/managementService': { updateValidatedRevenue: async value => { calls.push(value); return { data: value }; } },
  };
  const exports = {};
  vm.runInNewContext(source, { exports, require: name => { assert.ok(name in modules, name); return modules[name]; } });
  return {
    render: () => { index = 0; return exports.RevenueCard({ calculated: '151750 AED', calculatedAmount: 151750, defaultCurrency: 'AED' }); },
    receive: data => receive({ exists: () => data !== null, get: key => data?.[key] }),
    fail: () => fail(new Error('permission-denied')), calls,
  };
}
function nodes(tree) { if (!tree || typeof tree !== 'object') return []; return [tree, ...[tree.props?.children].flat(Infinity).flatMap(nodes)]; }
const find = (tree, type, label) => nodes(tree).find(n => n.type === type && (!label || n.props['aria-label'] === label));

test('both administrators receive the same saved amount and live updates', () => {
  const a = card(); const b = card();
  for (const view of [a, b]) {
    assert.equal(find(view.render(), 'Typography').props.children, '—');
    view.receive({ validatedRevenueAmount: 11000, validatedRevenueCurrency: 'AED' });
    assert.equal(find(view.render(), 'Typography').props.children, '11000 AED');
    view.receive({ validatedRevenueAmount: 12000, validatedRevenueCurrency: 'AED' });
    assert.equal(find(view.render(), 'Typography').props.children, '12000 AED');
  }
});
test('read failures cannot silently display the calculated revenue', () => {
  const view = card(); view.render(); view.fail();
  const tree = view.render();
  assert.equal(find(tree, 'Typography').props.children, '—');
  assert.ok(find(tree, 'Alert'));
  assert.equal(find(tree, 'IconButton', 'Modifier le montant total').props.disabled, true);
});
test('calculated revenue is used only after confirming no shared value exists', () => {
  const view = card(); view.render(); view.receive(null);
  assert.equal(find(view.render(), 'Typography').props.children, '151750 AED');
});
test('saving calls the shared backend and empty input does not overwrite with zero', async () => {
  const view = card(); view.render(); view.receive({ validatedRevenueAmount: 11000, validatedRevenueCurrency: 'AED' });
  find(view.render(), 'IconButton', 'Modifier le montant total').props.onClick();
  find(view.render(), 'TextField').props.onChange({ target: { value: '' } });
  find(view.render(), 'IconButton', 'Enregistrer').props.onClick();
  assert.equal(view.calls.length, 0);
  find(view.render(), 'TextField').props.onChange({ target: { value: '12000' } });
  find(view.render(), 'IconButton', 'Enregistrer').props.onClick();
  await Promise.resolve();
  assert.equal(view.calls.length, 1);
  assert.equal(view.calls[0].amount, 12000);
  assert.equal(view.calls[0].currency, 'AED');
});

test('confirmed cash increases the shared total and manual edits avoid recounting it', () => {
  const view = card(); view.render();
  view.receive({ validatedRevenueAmount: 11000, validatedRevenueCurrency: 'AED', confirmedCashTotals: { AED: 500 } });
  assert.equal(find(view.render(), 'Typography').props.children, '11500 AED');
  view.receive({ validatedRevenueAmount: 15000, validatedRevenueCurrency: 'AED', confirmedCashTotals: { AED: 500 }, validatedRevenueCashBaseline: { AED: 500 } });
  assert.equal(find(view.render(), 'Typography').props.children, '15000 AED');
  view.receive({ validatedRevenueAmount: 15000, validatedRevenueCurrency: 'AED', confirmedCashTotals: { AED: 700, EUR: 100 }, validatedRevenueCashBaseline: { AED: 500 } });
  assert.equal(find(view.render(), 'Typography').props.children, '15200 AED · 100 EUR');
});
