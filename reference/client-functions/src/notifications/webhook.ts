import { createHash, timingSafeEqual } from 'node:crypto';
import { FieldValue, Timestamp, type Firestore } from 'firebase-admin/firestore';
import { normalizedEmail } from './queue.js';

export function validWebhookAuthorization(header: string | undefined, secret: string): boolean {
  if (!secret || !header) return false;
  const digest = (value: string) => createHash('sha256').update(value).digest();
  return timingSafeEqual(digest(header), digest(`Bearer ${secret}`));
}

const statuses: Record<string, string> = {
  request: 'accepted', sent: 'accepted', delivered: 'delivered', deferred: 'deferred', soft_bounce: 'deferred',
  hard_bounce: 'bounced', blocked: 'blocked', invalid_email: 'bounced', error: 'blocked', spam: 'complained',
};
const ranks: Record<string, number> = { accepted: 1, deferred: 2, delivered: 3, bounced: 4, blocked: 4, complained: 5 };

export async function recordDeliveryWebhook(db: Firestore, input: unknown, now = Date.now()): Promise<void> {
  if (!input || typeof input !== 'object' || Array.isArray(input)) throw new Error('invalid_webhook');
  const data = input as Record<string, unknown>;
  const custom = data['X-Mailin-custom'];
  const id = typeof custom === 'string' ? /^classcard-delivery:([a-f0-9]{64})$/.exec(custom)?.[1] : null;
  // Other transactional emails in the same Brevo account are outside this queue.
  if (!id) return;
  const status = statuses[String(data.event)];
  if (!status) return;
  const timestamp = Number(data.ts_event ?? data.ts) * 1000;
  const address = normalizedEmail(data.email);
  const messageId = typeof data['message-id'] === 'string' ? data['message-id'].replace(/^<|>$/g, '') : '';
  if (!address || !messageId || !Number.isFinite(timestamp) || timestamp <= 0 || timestamp > now + 300000) throw new Error('invalid_webhook');
  const receiptId = createHash('sha256').update(`${id}|${messageId}|${data.event}|${timestamp}`).digest('hex');
  const ref = db.collection('mail').doc(id);
  const receiptRef = db.collection('notificationWebhookReceipts').doc(receiptId);
  await db.runTransaction(async transaction => {
    const [mail, receipt] = await Promise.all([transaction.get(ref), transaction.get(receiptRef)]);
    if (!mail.exists || receipt.exists || mail.get('recipient.email') !== address) return;
    const knownMessageId = String(mail.get('providerMessageId') ?? '').replace(/^<|>$/g, '');
    if (knownMessageId && knownMessageId !== messageId) return;
    const previousTime = mail.get('providerEventAt') instanceof Timestamp ? mail.get('providerEventAt').toMillis() : 0;
    const previousStatus = mail.get('status');
    transaction.create(receiptRef, { deliveryId: id, event: data.event, messageId, receivedAt: FieldValue.serverTimestamp(), purgeAt: Timestamp.fromMillis(now + 30 * 86400000) });
    if (timestamp < previousTime || timestamp === previousTime && (ranks[previousStatus] ?? 0) >= ranks[status]!) return;
    // A late "sent" event must not undo delivery or a permanent rejection.
    if ((ranks[previousStatus] ?? 0) >= 3 && ranks[status]! < 3) return;
    transaction.update(ref, {
      status, provider: 'brevo', providerMessageId: messageId, providerEvent: data.event,
      providerEventAt: Timestamp.fromMillis(timestamp), updatedAt: FieldValue.serverTimestamp(),
      ...(status === 'delivered' ? { deliveredAt: Timestamp.fromMillis(timestamp) } : {}),
      uncertainSince: null, retryable: false, nextAttemptAt: FieldValue.delete(), leaseToken: FieldValue.delete(),
      lastError: ['bounced', 'blocked', 'complained'].includes(status) ? `provider_${data.event}` : null,
    });
    transaction.delete(db.collection('notificationPayloads').doc(id));
  });
}
