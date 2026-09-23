import assert from 'node:assert/strict';
import test from 'node:test';
import { bookingTemplate, invitationTemplate } from '../notifications.js';
import { normalizedEmail } from './queue.js';
import { retryDelay } from './delivery.js';
import { validWebhookAuthorization } from './webhook.js';

test('notification addresses tolerate legacy data without throwing', () => {
  for (const value of [null, undefined, {}, 42, '', 'bad', 'a@@b.test', 'a@b.test\nb@c.test']) assert.equal(normalizedEmail(value), null);
  assert.equal(normalizedEmail(' Coach@Example.Test '), 'coach@example.test');
});

test('templates escape user HTML and preserve readable plain text', () => {
  const result = bookingTemplate({ recipientName: '<img src=x>', playerName: 'Alice & Bob', event: 'confirmed', startsAt: new Date('2026-10-01T10:00:00Z'), locationName: 'Court A', coachName: 'Coach', actionUrl: 'https://example.test/?a=1&b=2', locale: 'en' });
  assert.ok(result.html.includes('&lt;img src=x&gt;'));
  assert.ok(result.html.includes('Alice &amp; Bob'));
  assert.ok(result.text.includes('Location: Court A'));
  assert.ok(result.text.includes('14:00'));
  assert.equal(result.subject, 'Booking confirmed');
  assert.ok(invitationTemplate('Admin', 'https://example.test/reset', 'fr', 'administrator').text.includes('administrateur'));
});

test('backoff honors Retry-After seconds and dates', () => {
  const now = Date.now();
  assert.ok(retryDelay(1, '3600', now) >= 3600000);
  assert.ok(retryDelay(1, new Date(now + 7200000).toUTCString(), now) >= 7199000);
  assert.ok(retryDelay(3, 'invalid', now) >= 240000);
});

test('webhooks require the exact configured bearer secret', () => {
  assert.equal(validWebhookAuthorization('Bearer secret', 'secret'), true);
  for (const header of [undefined, '', 'secret', 'Bearer wrong', 'Bearer secret extra']) assert.equal(validWebhookAuthorization(header, 'secret'), false);
  assert.equal(validWebhookAuthorization('Bearer ', ''), false);
});
