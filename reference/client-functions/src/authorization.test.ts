import assert from 'node:assert/strict';
import test from 'node:test';
import { ROLE_PERMISSIONS, parseIds, parseRole } from './authorization.js';

test('root and admin receive the complete management permission set', () => {
  assert.deepEqual(ROLE_PERMISSIONS.root, ROLE_PERMISSIONS.admin);
  assert.equal(ROLE_PERMISSIONS.root.includes('admins.manage'), true);
  assert.equal(ROLE_PERMISSIONS.root.includes('bookings.approve'), true);
});

test('specialized roles use least privilege', () => {
  assert.deepEqual(ROLE_PERMISSIONS.booking_manager, ['bookings.approve']);
  assert.equal(ROLE_PERMISSIONS.academy_manager.includes('admins.manage'), false);
});

test('role and identifier lists are validated and deduplicated', () => {
  assert.equal(parseRole('admin'), 'admin');
  assert.throws(() => parseRole('root-from-client'));
  assert.deepEqual(parseIds(['academy-a', 'academy-a'], 'academyIds'), ['academy-a']);
});
