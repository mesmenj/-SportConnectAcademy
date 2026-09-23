import { randomUUID } from 'node:crypto';
import { FieldValue, Timestamp, type Firestore, type DocumentData } from 'firebase-admin/firestore';
import { millis } from './queue.js';

const LEASE_MS = 120000;
// Conservative margin, also below Brevo's former 15-minute deduplication window.
export const SAFE_RETRY_WINDOW_MS = 14 * 60000;
const MAX_ATTEMPTS = 10;
export const REQUEST_TIMEOUT_MS = 15000;
const terminal = new Set(['sent', 'accepted', 'delivered', 'bounced', 'blocked', 'complained']);

export function retryDelay(attempt: number, retryAfter: string | null, now: number): number {
  const seconds = retryAfter === null ? NaN : Number(retryAfter);
  const providerDelay = Number.isFinite(seconds) ? seconds * 1000 : retryAfter ? Date.parse(retryAfter) - now : 0;
  return Math.max(Math.min(3600000, 60000 * 2 ** Math.max(0, attempt - 1)) + Math.floor(Math.random() * 15000), Number.isFinite(providerDelay) ? providerDelay : 0);
}

export interface DeliveryDependencies {
  fetch?: typeof fetch;
  now?: () => number;
  checkInvitation?: (uid: string, email: string) => Promise<boolean>;
}

export async function deliverMail(db: Firestore, id: string, apiKey: string, dependencies: DeliveryDependencies = {}): Promise<void> {
  const now = dependencies.now ?? Date.now;
  const ref = db.collection('mail').doc(id);
  const payloadRef = db.collection('notificationPayloads').doc(id);
  const token = randomUUID();
  const claimed = await db.runTransaction(async transaction => {
    const mail = await transaction.get(ref);
    if (!mail.exists || mail.get('schemaVersion') !== 2) return null; // Never replay legacy logs.
    const data = mail.data()!;
    if (!['queued', 'retry', 'sending'].includes(data.status) || millis(data.nextAttemptAt) > now()) return null;
    if (data.reminderVersion) {
      const [booking, reminder] = await Promise.all([
        transaction.get(db.collection('bookings').doc(data.bookingId)), transaction.get(db.collection('bookingReminders').doc(data.bookingId)),
      ]);
      if (!booking.exists || booking.get('isDelete') === true || booking.get('status') !== 'confirmed' ||
          reminder.get('status') !== 'queued' || reminder.get('version') !== data.reminderVersion ||
          millis(booking.get('startsAt')) !== millis(data.expiresAt) || millis(data.expiresAt) <= now()) {
        transaction.update(ref, { status: 'skipped', lastError: 'reminder_no_longer_eligible', retryable: false, nextAttemptAt: FieldValue.delete(), updatedAt: FieldValue.serverTimestamp() });
        transaction.delete(payloadRef);
        return null;
      }
    }
    let error: string | null = null;
    if (data.expiresAt && millis(data.expiresAt) <= now()) error = 'invitation_expired';
    if (data.uncertainSince && now() - millis(data.uncertainSince) >= SAFE_RETRY_WINDOW_MS) error = 'provider_result_unknown';
    if (data.attempts >= MAX_ATTEMPTS) error = data.uncertainSince ? 'provider_result_unknown' : 'attempts_exhausted';
    if (error) {
      transaction.update(ref, { status: error === 'provider_result_unknown' ? 'unknown' : 'failed', lastError: error, retryable: error === 'attempts_exhausted', nextAttemptAt: FieldValue.delete(), updatedAt: FieldValue.serverTimestamp() });
      return null;
    }
    const payload = await transaction.get(payloadRef);
    if (!payload.exists) {
      transaction.update(ref, { status: 'failed', lastError: 'missing_payload', retryable: false, nextAttemptAt: FieldValue.delete() });
      return null;
    }
    transaction.update(ref, {
      status: 'sending', leaseToken: token, nextAttemptAt: Timestamp.fromMillis(now() + LEASE_MS),
      attempts: FieldValue.increment(1), lastAttemptAt: Timestamp.fromMillis(now()),
      // Set BEFORE crossing the network boundary. A crashed worker is uncertain.
      uncertainSince: data.uncertainSince ?? Timestamp.fromMillis(now()), updatedAt: FieldValue.serverTimestamp(),
    });
    return { ...data, attempts: data.attempts + 1, body: payload.get('body') } as DocumentData;
  });
  if (!claimed) return;

  const settle = async (patch: DocumentData, removePayload = false) => {
    await db.runTransaction(async transaction => {
      const current = await transaction.get(ref);
      // A webhook or a newer lease can already have settled this request.
      if (current.get('leaseToken') !== token || terminal.has(current.get('status'))) return;
      transaction.update(ref, { ...patch, leaseToken: FieldValue.delete(), updatedAt: FieldValue.serverTimestamp() });
      if (removePayload) transaction.delete(payloadRef);
    });
  };

  // Check account state outside the business request; failures remain recoverable.
  if (claimed.kind === 'invitation' && dependencies.checkInvitation) {
    try {
      if (!await dependencies.checkInvitation(claimed.userId, claimed.recipient.email)) {
        await settle({ status: 'failed', retryable: false, lastError: 'invitation_account_unavailable', uncertainSince: null, nextAttemptAt: FieldValue.delete() }, true);
        return;
      }
    } catch {
      await settle({ status: 'retry', lastError: 'account_check_unavailable', uncertainSince: null, nextAttemptAt: Timestamp.fromMillis(now() + retryDelay(claimed.attempts, null, now())) });
      return;
    }
  }

  let response: Response;
  let body: { messageId?: string; code?: string };
  try {
    response = await (dependencies.fetch ?? fetch)('https://api.brevo.com/v3/smtp/email', {
      method: 'POST', headers: { 'api-key': apiKey, 'content-type': 'application/json' },
      body: JSON.stringify({ ...claimed.body, headers: { ...claimed.body.headers, idempotencyKey: claimed.idempotencyKey } }),
      signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
    });
    const parsed: unknown = await response.json().catch(() => null);
    const result = parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed as Record<string, unknown> : {};
    body = {
      messageId: typeof result.messageId === 'string' && result.messageId.trim() ? result.messageId : undefined,
      // Keep only the machine code, never provider text which may contain private content.
      code: typeof result.code === 'string' && /^[a-z_]{1,80}$/.test(result.code) ? result.code : undefined,
    };
  } catch {
    await settle({ status: 'retry', lastError: 'provider_network_error', nextAttemptAt: Timestamp.fromMillis(now() + retryDelay(claimed.attempts, null, now())) });
    return;
  }

  // Deliberately outside the fetch catch: a journal failure must NOT trigger a new send.
  if ((response.ok && body.messageId) || (response.status === 400 && body.code === 'duplicate_parameter')) {
    await settle({ status: 'accepted', provider: 'brevo', providerMessageId: body.messageId ?? null,
      acceptedAt: FieldValue.serverTimestamp(), uncertainSince: null, lastError: null, retryable: false, nextAttemptAt: FieldValue.delete() }, true);
    return;
  }
  if (response.ok) {
    // An incomplete success response cannot prove acceptance or refusal. Keep the
    // payload and original uncertainty so a retry uses the same idempotency key.
    await settle({ status: 'retry', lastError: 'provider_invalid_response', nextAttemptAt: Timestamp.fromMillis(now() + retryDelay(claimed.attempts, null, now())) });
    return;
  }
  const temporary = response.status === 429 || response.status === 408 || response.status >= 500;
  const exhausted = claimed.attempts >= MAX_ATTEMPTS;
  // A timeout/5xx can be ambiguous. A definitive refusal clears only this attempt's
  // uncertainty, never an earlier network error's possible acceptance.
  const uncertainty = claimed.uncertainSince ?? (response.status >= 500 || response.status === 408 ? Timestamp.fromMillis(now()) : null);
  await settle({
    status: temporary && !exhausted ? 'retry' : uncertainty ? 'unknown' : 'failed',
    lastError: `provider_http_${response.status}${body.code ? `:${body.code}` : ''}`,
    retryable: !uncertainty && (temporary || response.status === 401 || response.status === 403 || body.code === 'not_enough_credits' || body.code === 'account_under_validation'),
    uncertainSince: uncertainty,
    nextAttemptAt: temporary && !exhausted ? Timestamp.fromMillis(now() + retryDelay(claimed.attempts, response.headers.get('retry-after'), now())) : FieldValue.delete(),
  });
}
