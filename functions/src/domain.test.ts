import test from 'node:test';
import assert from 'node:assert/strict';
import { id, planInput, subscriptionIsActive } from './domain.js';
test('tenant IDs cannot inject Firestore paths', () => {
  for (const value of ['a/b', '../other', '', '*', null]) assert.throws(() => id(value));
  assert.equal(id('academy_2'), 'academy_2');
});
test('plan quotas require bounded positive integers', () => {
  for (const value of [-1, 0, 1.5, NaN, Infinity, '100', 1000001]) assert.throws(() => planInput({ name: 'Test', maxPlayers: value, maxStaff: 2 }));
  assert.equal(planInput({ name: 'Starter', maxPlayers: 100, maxStaff: 5 }).maxPlayers, 100);
});
test('subscription expires at the deadline even without scheduler', () => {
  assert.equal(subscriptionIsActive({ status: 'active', endsAt: { toMillis: () => 100 } }, 99), true);
  assert.equal(subscriptionIsActive({ status: 'active', endsAt: { toMillis: () => 100 } }, 100), false);
  assert.equal(subscriptionIsActive({ status: 'suspended', endsAt: { toMillis: () => 200 } }, 99), false);
  assert.equal(subscriptionIsActive(undefined, 99), false);
});
