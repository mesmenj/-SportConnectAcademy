export const BOOKING_STATUSES = ['pending', 'confirmed', 'completed', 'cancelled'] as const;
export type BookingStatus = typeof BOOKING_STATUSES[number];

export const SESSION_TYPES = ['private', 'semi_private', 'group'] as const;
export type SessionType = typeof SESSION_TYPES[number];
export const CURRENCIES = ['AED', 'XAF', 'EUR', 'USD', 'MAD'] as const;
export type Currency = typeof CURRENCIES[number];

export function currency(value: unknown): Currency {
  const normalized = String(value ?? '').trim().toUpperCase();
  if (!CURRENCIES.includes(normalized as Currency)) throw new Error('CURRENCY_INVALID');
  return normalized as Currency;
}

export function sessionType(value: unknown): SessionType {
  const normalized = String(value ?? '').trim().toLowerCase().replace(/[ -]+/g, '_');
  const aliases: Record<string, SessionType> = {
    private: 'private', private_session: 'private', private_sessions: 'private',
    semi_private: 'semi_private', semi_private_session: 'semi_private', semi_private_sessions: 'semi_private',
    group: 'group', group_session: 'group', group_sessions: 'group',
  };
  const result = aliases[normalized];
  if (!result) throw new Error('SESSION_TYPE_INVALID');
  return result;
}

export function assertAgeEligible(age: unknown, minAge: unknown, maxAge: unknown): void {
  if (!Number.isInteger(age) || !Number.isInteger(minAge) || !Number.isInteger(maxAge)) throw new Error('AGE_REQUIRED');
  if ((age as number) < (minAge as number) || (age as number) > (maxAge as number)) throw new Error('AGE_NOT_ELIGIBLE');
}

export interface CreateBookingInput {
  sessionId: string;
  playerId: string;
  note?: string;
}

export function requiredId(value: unknown, field: string): string {
  if (typeof value !== 'string' || !/^[A-Za-z0-9_-]{1,100}$/.test(value)) {
    throw new Error(`${field} invalide`);
  }
  return value;
}

export function optionalNote(value: unknown): string | undefined {
  if (value == null || value === '') return undefined;
  if (typeof value !== 'string' || value.trim().length > 500) throw new Error('note invalide');
  return value.trim();
}

export function bookingId(sessionId: string, playerId: string): string {
  return `${sessionId}_${playerId}`;
}

export function assertBookable(session: { status?: unknown; capacity?: unknown; bookedCount?: unknown; startsAtMillis?: number }, now = Date.now()): void {
  if (session.status !== 'open') throw new Error('SESSION_CLOSED');
  if (!Number.isInteger(session.capacity) || !Number.isInteger(session.bookedCount)) throw new Error('SESSION_INVALID');
  if ((session.bookedCount as number) >= (session.capacity as number)) throw new Error('SESSION_FULL');
  if (session.startsAtMillis !== undefined && session.startsAtMillis <= now) throw new Error('SESSION_STARTED');
}

export function canManage(role: unknown): boolean {
  return role === 'root' || role === 'admin' || role === 'manager';
}

export function canTransitionBooking(from: BookingStatus, to: BookingStatus): boolean {
  if (from === to) return true;
  return (from === 'pending' && to === 'confirmed') || (from === 'confirmed' && to === 'completed');
}

export function shouldDebitCourseOnCompletion(courseDebited: unknown, hasSessionConfiguration: boolean): boolean {
  // Missing markers belong to legacy bookings whose course was debited when
  // approved. Only the explicit false marker used by new bookings is debit-able.
  return hasSessionConfiguration && courseDebited === false;
}

export function adjustPlayerCourses(packageSessions: unknown, remainingSessions: unknown, delta: unknown): {
  packageSessions: number;
  remainingSessions: number;
} {
  const immutablePackageSessions = Math.max(0, Number(packageSessions) || 0);
  const currentRemainingSessions = Math.max(0, Number(remainingSessions) || 0);
  if (delta !== -1 && delta !== 1) throw new Error('PLAYER_COURSE_DELTA_INVALID');
  const nextRemainingSessions = currentRemainingSessions + delta;
  if (nextRemainingSessions < 0) throw new Error('PLAYER_COURSES_EMPTY');
  return {
    packageSessions: immutablePackageSessions,
    remainingSessions: nextRemainingSessions,
  };
}

export function updatePlayerPackage(packageSessions: unknown, remainingSessions: unknown, nextPackageSessions: unknown): {
  packageSessions: number;
  remainingSessions: number;
  packageDelta: number;
} {
  const currentPackageSessions = Math.max(0, Number(packageSessions) || 0);
  const currentRemainingSessions = Math.max(0, Number(remainingSessions) || 0);
  const next = Number(nextPackageSessions);
  if (!Number.isInteger(next) || next < 0 || next > 10000) throw new Error('PLAYER_PACKAGE_INVALID');
  const packageDelta = next - currentPackageSessions;
  const nextRemainingSessions = currentRemainingSessions + packageDelta;
  if (nextRemainingSessions < 0) throw new Error('PLAYER_PACKAGE_BELOW_USED');
  return { packageSessions: next, remainingSessions: nextRemainingSessions, packageDelta };
}

export function bookingDeletionEffect(status: unknown, courseWasDebited: boolean): {
  status: unknown;
  releasePlace: boolean;
  restorePlayerCourse: boolean;
} {
  const isConfirmed = status === 'confirmed';
  return {
    status: status === 'pending' || isConfirmed ? 'cancelled' : status,
    releasePlace: isConfirmed,
    restorePlayerCourse: courseWasDebited,
  };
}

export function attendanceCourseDelta(courseWasDebited: boolean, attended: boolean, hasSessionConfiguration: boolean): -1 | 0 | 1 {
  if (!hasSessionConfiguration) return 0;
  if (attended && !courseWasDebited) return -1;
  if (!attended && courseWasDebited) return 1;
  return 0;
}

export function bookingCreationEffect(createdByStaff: boolean): {
  status: 'confirmed' | 'pending';
  reservePlace: boolean;
  clientCanReject: boolean;
} {
  return createdByStaff
    ? { status: 'confirmed', reservePlace: true, clientCanReject: true }
    : { status: 'pending', reservePlace: false, clientCanReject: false };
}

export function scheduledBookingRejectionEffect(status: unknown, clientCanReject: unknown): {
  status: 'rejected';
  releasePlace: true;
} {
  if (status !== 'confirmed' || clientCanReject !== true) throw new Error('BOOKING_NOT_CLIENT_REJECTABLE');
  return { status: 'rejected', releasePlace: true };
}

export function bookingIntervalsOverlap(existingStart: unknown, existingEnd: unknown, requestedStart: unknown, requestedEnd: unknown): boolean {
  const values = [existingStart, existingEnd, requestedStart, requestedEnd].map(value => Number(value));
  if (values.some(value => !Number.isFinite(value))) return false;
  const [currentStart, currentEnd, nextStart, nextEnd] = values as [number, number, number, number];
  return currentStart < nextEnd && currentEnd > nextStart;
}
