import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';
import ts from 'typescript';
const source = ts.transpileModule(readFileSync(new URL('../src/components/CreateBooking.tsx', import.meta.url), 'utf8'), { compilerOptions: { module: ts.ModuleKind.CommonJS, jsx: ts.JsxEmit.ReactJSX } }).outputText;
function fixture() {
  const players = [
    { id: 'first', label: 'First', age: 8, academyId: 'one', communityId: 'one', sessionConfigurationId: 'package', remainingSessions: 10 },
    { id: 'second', label: 'Second', age: 60, academyId: 'two', communityId: 'two', remainingSessions: 0 },
  ];
  const state = []; let index = 0; let initialized = false;
  const jsx = (type, props) => ({ type, props });
  const imports = {
    react: { useState: initial => { const i = index++; if (!(i in state)) state[i] = initial; return [state[i], value => { state[i] = typeof value === 'function' ? value(state[i]) : value; }]; }, useMemo: fn => fn(), useEffect: fn => { if (!initialized) { initialized = true; fn(); } } },
    'react/jsx-runtime': { jsx, jsxs: jsx },
    '@mui/material': new Proxy({}, { get: (_, name) => name }), '@mui/icons-material': {},
    '../services/bookingService': { subscribeBookingOptions: (_, __, onPlayers, ___, onConfigurations) => { onPlayers(players); onConfigurations([{ id: 'package', activityType: 'tennis', minAge: 5, maxAge: 10 }]); return () => {}; } },
    '../services/managementService': {}, '../store/hooks': { useAppSelector: () => ({ uid: 'admin', role: 'root' }) },
    '../i18n': { useI18n: () => ({ t: s => s, language: 'fr' }), formatMoney: () => '' },
  };
  const exports = {};
  vm.runInNewContext(source, { exports, require: name => imports[name] });
  const render = () => { index = 0; return exports.CreateBooking({ open: true, onClose() {}, onCreated() {} }); };
  render();
  return { players, render };
}
function nodes(tree) { if (!tree || typeof tree !== 'object') return []; return [tree, ...[tree.props?.children].flat(Infinity).flatMap(nodes)]; }
const picker = tree => nodes(tree).find(n => n.type === 'Autocomplete');
test('selecting the first player never filters out other players', () => {
  const f = fixture();
  picker(f.render()).props.onChange(null, [f.players[0]]);
  assert.equal(picker(f.render()).props.options.length, 2);
  picker(f.render()).props.onChange(null, f.players);
  assert.equal(picker(f.render()).props.value.length, 2);
});
test('a player with no package, quota or matching age can select a session configuration', () => {
  const f = fixture();
  picker(f.render()).props.onChange(null, [f.players[1]]);
  const tree = f.render();
  const configuration = nodes(tree).find(n => n.type === 'Select' && n.props.label === 'Configuration de séance');
  assert.equal(configuration.props.children.length, 1);
  const container = nodes(tree).find(n => n.type === 'FormControl' && nodes(n).includes(configuration));
  assert.equal(container.props.disabled, false);
  assert.equal(picker(tree).props.options.length, 2);
});
