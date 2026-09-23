import assert from 'node:assert/strict';
import test from 'node:test';
import { adjustPlayerCourses, assertAgeEligible, assertBookable, attendanceCourseDelta, bookingCreationEffect, bookingDeletionEffect, bookingId, bookingIntervalsOverlap, canManage, canTransitionBooking, currency, optionalNote, requiredId, scheduledBookingRejectionEffect, sessionType, shouldDebitCourseOnCompletion, updatePlayerPackage } from './domain.js';

test('booking id is deterministic for retry idempotency', () => {
  assert.equal(bookingId('session-1', 'player-2'), 'session-1_player-2');
});

test('identifiers and notes are validated', () => {
  assert.equal(requiredId('abc-_123', 'id'), 'abc-_123');
  assert.throws(() => requiredId('../admin', 'id'));
  assert.equal(optionalNote('  Raquette incluse  '), 'Raquette incluse');
  assert.throws(() => optionalNote('x'.repeat(501)));
});

test('only an open future session with capacity is bookable', () => {
  assert.doesNotThrow(() => assertBookable({ status: 'open', capacity: 4, bookedCount: 3, startsAtMillis: 2_000 }, 1_000));
  assert.throws(() => assertBookable({ status: 'open', capacity: 4, bookedCount: 4 }), /SESSION_FULL/);
  assert.throws(() => assertBookable({ status: 'cancelled', capacity: 4, bookedCount: 0 }), /SESSION_CLOSED/);
  assert.throws(() => assertBookable({ status: 'open', capacity: 4, bookedCount: 0, startsAtMillis: 500 }, 1_000), /SESSION_STARTED/);
});

test('booking status management is restricted', () => {
  assert.equal(canManage('root'), true);
  assert.equal(canManage('manager'), true);
  assert.equal(canManage('coach'), false);
});

test('status transitions cannot bypass cancellation accounting', () => {
  assert.equal(canTransitionBooking('pending', 'confirmed'), true);
  assert.equal(canTransitionBooking('confirmed', 'completed'), true);
  assert.equal(canTransitionBooking('confirmed', 'cancelled'), false);
  assert.equal(canTransitionBooking('completed', 'confirmed'), false);
});

test('session configuration types are canonicalized', () => {
  assert.equal(sessionType('Private sessions'), 'private');
  assert.equal(sessionType('semi-private session'), 'semi_private');
  assert.equal(sessionType('group'), 'group');
  assert.throws(() => sessionType('academy'));
});

test('player age must belong to the configured range', () => {
  assert.doesNotThrow(() => assertAgeEligible(8, 6, 12));
  assert.throws(() => assertAgeEligible(5, 6, 12), /AGE_NOT_ELIGIBLE/);
  assert.throws(() => assertAgeEligible(undefined, 6, 12), /AGE_REQUIRED/);
});

test('only supported international currencies are accepted', () => {
  assert.equal(currency('aed'), 'AED');
  assert.equal(currency('eur'), 'EUR');
  assert.equal(currency('USD'), 'USD');
  assert.equal(currency('xaf'), 'XAF');
  assert.equal(currency('mad'), 'MAD');
  assert.throws(() => currency('GBP'), /CURRENCY_INVALID/);
});

test('manual player course adjustments never modify the package size', () => {
  assert.deepEqual(adjustPlayerCourses(10, 7, 1), { packageSessions: 10, remainingSessions: 8 });
  assert.deepEqual(adjustPlayerCourses(10, 7, -1), { packageSessions: 10, remainingSessions: 6 });
  assert.deepEqual(adjustPlayerCourses(10, 10, 1), { packageSessions: 10, remainingSessions: 11 });
  assert.throws(() => adjustPlayerCourses(10, 0, -1), /PLAYER_COURSES_EMPTY/);
  assert.throws(() => adjustPlayerCourses(10, 7, 2), /PLAYER_COURSE_DELTA_INVALID/);
});

test('admin completion consumes a course exactly once and preserves legacy bookings', () => {
  assert.equal(shouldDebitCourseOnCompletion(false, true), true);
  assert.equal(shouldDebitCourseOnCompletion(true, true), false);
  assert.equal(shouldDebitCourseOnCompletion(undefined, true), false);
  assert.equal(shouldDebitCourseOnCompletion(false, false), false);
});

test('updating a player package preserves consumed and manually adjusted courses', () => {
  assert.deepEqual(updatePlayerPackage(10, 7, 20), { packageSessions: 20, remainingSessions: 17, packageDelta: 10 });
  assert.deepEqual(updatePlayerPackage(20, 17, 19), { packageSessions: 19, remainingSessions: 16, packageDelta: -1 });
  assert.deepEqual(updatePlayerPackage(10, 11, 20), { packageSessions: 20, remainingSessions: 21, packageDelta: 10 });
  assert.throws(() => updatePlayerPackage(10, 2, 7), /PLAYER_PACKAGE_BELOW_USED/);
  assert.throws(() => updatePlayerPackage(10, 2, -1), /PLAYER_PACKAGE_INVALID/);
});

test('soft-deleting bookings preserves capacity and player course accounting', () => {
  assert.deepEqual(bookingDeletionEffect('confirmed', true), { status: 'cancelled', releasePlace: true, restorePlayerCourse: true });
  assert.deepEqual(bookingDeletionEffect('confirmed', false), { status: 'cancelled', releasePlace: true, restorePlayerCourse: false });
  assert.deepEqual(bookingDeletionEffect('pending', false), { status: 'cancelled', releasePlace: false, restorePlayerCourse: false });
  assert.deepEqual(bookingDeletionEffect('completed', true), { status: 'completed', releasePlace: false, restorePlayerCourse: true });
});

test('a player course is debited only when coach attendance becomes present', () => {
  assert.equal(attendanceCourseDelta(false, true, true), -1);
  assert.equal(attendanceCourseDelta(true, true, true), 0);
  assert.equal(attendanceCourseDelta(true, false, true), 1);
  assert.equal(attendanceCourseDelta(false, false, true), 0);
  assert.equal(attendanceCourseDelta(false, true, false), 0);
});

test('staff bookings are confirmed immediately and client rejection releases the place', () => {
  assert.deepEqual(bookingCreationEffect(true), { status: 'confirmed', reservePlace: true, clientCanReject: true });
  assert.deepEqual(bookingCreationEffect(false), { status: 'pending', reservePlace: false, clientCanReject: false });
  assert.deepEqual(scheduledBookingRejectionEffect('confirmed', true), { status: 'rejected', releasePlace: true });
  assert.throws(() => scheduledBookingRejectionEffect('pending', true), /BOOKING_NOT_CLIENT_REJECTABLE/);
  assert.throws(() => scheduledBookingRejectionEffect('confirmed', false), /BOOKING_NOT_CLIENT_REJECTABLE/);
});

test('a player cannot have overlapping booking intervals', () => {
  assert.equal(bookingIntervalsOverlap(1_000, 2_000, 1_500, 2_500), true);
  assert.equal(bookingIntervalsOverlap(1_500, 1_800, 1_000, 2_000), true);
  assert.equal(bookingIntervalsOverlap(1_000, 2_000, 2_000, 3_000), false);
  assert.equal(bookingIntervalsOverlap(2_000, 3_000, 1_000, 2_000), false);
  assert.equal(bookingIntervalsOverlap(undefined, 3_000, 1_000, 2_000), false);
});
