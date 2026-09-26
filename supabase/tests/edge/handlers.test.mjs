import { Buffer } from 'node:buffer';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { readFile } from 'node:fs/promises';
import { createHandler, renderEmail } from '../../functions/_shared/handlers.mjs';
import { platform } from '../../functions/_shared/platform.mjs';
import { imageHeader, validateImage } from '../../functions/_shared/media.mjs';
import { decodeImage } from '../../functions/_shared/decode.mjs';
import { createAuthClient, parseInvitationFragment } from '../../auth/client.mjs';
import { boundedBytes } from '../../functions/_shared/http.mjs';
const require = createRequire(new URL('../../functions/package.json', import.meta.url));
const { PNG } = require('pngjs'); const jpeg = require('jpeg-js');
const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const config = { supabaseUrl: 'http://local.test', publicSupabaseUrl: 'http://localhost:54321', anonKey: 'anon', serviceKey: 'service',
  allowedOrigins: 'http://localhost:5173', workerSecret: 'w'.repeat(40), webhookSecret: 'h'.repeat(40), invitationSecret: 'i'.repeat(40),
  invitationUrl: 'http://localhost:5173/auth/invitation', assetTtl: '120', brevoKey: 'test-provider-secret', senderEmail: 'test@example.test' };
const req = (body = {}, headers = {}, method = 'POST') => new Request('http://local.test/function', { method, headers: { 'Content-Type': 'application/json', ...headers },
  ...(['GET','OPTIONS'].includes(method) ? {} : { body: JSON.stringify(body) }) });
const worker = () => req({}, { 'x-worker-secret': config.workerSecret });
const png = PNG.sync.write({ width: 2, height: 2, data: Buffer.alloc(16, 255) });
const jwt = { authorization: 'Bearer user-jwt' };
function dbMock() {
  const calls = [];
  return { calls, user: async token => { calls.push(['user', token]); if (!token) throw new Error('forged'); return { id: id(1) }; },
    rpc: async (name, args, token) => { calls.push([name, args, token]); return { outcome: 'OK' }; } };
}
test('all worker endpoints reject missing secret before database access', async () => {
  for (const name of ['provision-invitation','deliver-email','expand-email-outbox','schedule-notifications','cleanup-assets-and-content']) {
    const db = dbMock(); const response = await createHandler(name, config, { db })(req());
    assert.equal(response.status, 401); assert.equal(db.calls.length, 0);
  }
});
test('worker rejects user JWT and webhook secret', async () => {
  const db = dbMock(); const handler = createHandler('deliver-email', config, { db });
  assert.equal((await handler(req({}, { ...jwt, 'x-worker-secret': config.webhookSecret }))).status, 401);
  assert.equal(db.calls.length, 0);
});
test('webhook rejects worker secret and malformed bodies without DB writes', async () => {
  const db = dbMock(), handler = createHandler('brevo-webhook', config, { db });
  assert.equal((await handler(req({}, { 'x-webhook-secret': config.workerSecret }))).status, 401);
  assert.equal((await handler(req([], { 'x-webhook-secret': config.webhookSecret }))).status, 400);
  assert.equal(db.calls.length, 0);
});
test('webhook derives only delivery correlation; ignores supplied tenant', async () => {
  const db = dbMock(); const handler = createHandler('brevo-webhook', config, { db });
  const response = await handler(req({ event: 'delivered', 'message-id': 'provider-1', 'X-Mailin-custom': `delivery_id:${id(2)}`,
    ts_event: 1790000000, academy_id: id(999) }, { 'x-webhook-secret': config.webhookSecret }));
  assert.equal(response.status, 200); assert.equal(db.calls[0][1].p_delivery, id(2)); assert.equal(db.calls[0][1].p_academy, undefined);
});
test('CORS rejects unlisted origin and never reflects wildcard', async () => {
  const db = dbMock(); const handler = createHandler('read-asset-url', config, { db });
  assert.equal((await handler(req({}, { origin: 'https://evil.example' }))).status, 403);
  const response = await handler(req({}, { origin: 'http://localhost:5173' }, 'OPTIONS'));
  assert.equal(response.status, 204); assert.equal(response.headers.get('Access-Control-Allow-Origin'), 'http://localhost:5173');
  assert.equal(db.calls.length, 0);
});
test('GET does not invoke worker or mutate data', async () => {
  const db = dbMock(); assert.equal((await createHandler('schedule-notifications', config, { db })(req({}, {}, 'GET'))).status, 405);
  assert.equal(db.calls.length, 0);
});
test('chunked oversized request is rejected even without Content-Length', async () => {
  const body = new ReadableStream({ start(c) { c.enqueue(new Uint8Array(12)); c.enqueue(new Uint8Array(12)); c.close(); } });
  await assert.rejects(boundedBytes(new Request('http://test', { method: 'POST', body, duplex: 'half' }), 20), /BODY_TOO_LARGE/);
});
test('real PNG decoder validates dimensions, bytes and digest', async () => {
  const proof = await validateImage(png, 'image/png', decodeImage);
  assert.equal(proof.size, png.length); assert.match(proof.sha256, /^[a-f0-9]{64}$/);
});
test('real JPEG decoder accepts valid bounded image', async () => {
  const bytes = jpeg.encode({ width: 2, height: 2, data: Buffer.alloc(16, 255) }, 80).data;
  assert.equal((await validateImage(bytes, 'image/jpeg', decodeImage)).mime, 'image/jpeg');
});
test('real WebP WASM decoder accepts valid lossless image', async () => {
  const { default: encode, init } = await import('../../functions/node_modules/@jsquash/webp/encode.js');
  const wasm = await readFile(new URL('../../functions/node_modules/@jsquash/webp/codec/enc/webp_enc.wasm', import.meta.url));
  await init(await WebAssembly.compile(wasm));
  const bytes = new Uint8Array(await encode({ width: 2, height: 2, data: new Uint8ClampedArray(16).fill(255) }, { lossless: 1 }));
  assert.equal((await validateImage(bytes, 'image/webp', decodeImage)).mime, 'image/webp');
});
test('spoofed MIME, corrupt CRC and HTML rejected', async () => {
  await assert.rejects(validateImage(png, 'image/jpeg', decodeImage), /INVALID_MEDIA/);
  const corrupt = Buffer.from(png); corrupt[29] ^= 255;
  await assert.rejects(validateImage(corrupt, 'image/png', decodeImage), /INVALID_MEDIA/);
  await assert.rejects(validateImage(new TextEncoder().encode('<svg><script>alert(1)</script></svg>'), 'image/png', decodeImage), /INVALID_MEDIA/);
});
test('oversized pixel allocation rejected before decoder', async () => {
  const bomb = Buffer.from(png); bomb.writeUInt32BE(50000, 16); let called = false;
  await assert.rejects(validateImage(bomb, 'image/png', () => { called = true; }), /INVALID_MEDIA/); assert.equal(called, false);
});
test('upload validates storage bytes and uses verified actor rather than header', async () => {
  const db = dbMock();
  db.rpc = async (name, args, token) => { db.calls.push([name, args, token]); return name === 'prepare_asset' ? { asset_id: id(2), bucket: 'academy-private-assets', path: 'server/path.png' } : { outcome: 'READY' }; };
  db.upload = async (...args) => { db.calls.push(['upload', ...args]); }; db.download = async () => png;
  const handler = createHandler('secure-asset-upload', config, { db, decodeImage });
  const response = await handler(new Request('http://test', { method: 'POST', headers: { ...jwt, 'Content-Type': 'image/png',
    'x-academy-id': id(3), 'x-operation-key': id(4), 'x-asset-usage': 'BRANDING', 'x-user-id': id(999) }, body: png }));
  assert.equal(response.status, 200);
  const finalize = db.calls.find(x => x[0] === 'svc_finalize_asset'); assert.equal(finalize[1].p_actor, id(1));
  assert.equal(db.calls.find(x => x[0] === 'prepare_asset')[2], 'user-jwt');
});
test('corrupt stored object cannot be finalized', async () => {
  const db = dbMock(); db.rpc = async name => { db.calls.push([name]); return { asset_id: id(2), bucket: 'b', path: 'p' }; };
  db.upload = async () => {}; db.download = async () => new Uint8Array(50);
  const handler = createHandler('secure-asset-upload', config, { db, decodeImage });
  const response = await handler(new Request('http://test', { method: 'POST', headers: { ...jwt, 'Content-Type': 'image/png',
    'x-academy-id': id(3), 'x-operation-key': id(4), 'x-asset-usage': 'BRANDING' }, body: png }));
  assert.equal(response.status, 400); assert.equal(db.calls.some(x => x[0] === 'svc_finalize_asset'), false);
});
test('signed URL uses server authorization and bounded TTL', async () => {
  const db = dbMock(); db.rpc = async (name,args,token) => { db.calls.push([name,args,token]); return { bucket: 'private', path: 'authorized' }; };
  db.sign = async (...args) => { db.calls.push(['sign', ...args]); return 'signed'; };
  assert.equal((await createHandler('read-asset-url', config, { db })(req({ academy_id: id(3), asset_id: id(2), ttl: 999999, path: 'forged' }, jwt))).status, 200);
  assert.deepEqual(db.calls.at(-1), ['sign','private','authorized',120]);
  assert.equal((await createHandler('read-asset-url', { ...config, assetTtl: '3600' }, { db })(req({ academy_id: id(3), asset_id: id(2) }, jwt))).status, 503);
});
test('delivery timeout records UNKNOWN instead of retry', async () => {
  const db = dbMock(); db.rpc = async (name,args) => { db.calls.push([name,args]); return name === 'svc_claim_delivery' ? {
    id: id(1), lease_token: id(2), idempotency_key: id(3), email: 'recipient@example.test', language: 'FR', template: 'MEMBERSHIP_INVITED', body: { invitation_url: 'https://example.test/#secret' },
  } : { outcome: args.p_outcome }; };
  const response = await createHandler('deliver-email', config, { db, fetcher: async () => { throw new Error('timeout'); } })(worker());
  assert.equal((await response.json()).outcome, 'UNKNOWN'); assert.equal(db.calls.at(-1)[1].p_outcome, 'UNKNOWN');
});
test('explicit provider 429 retries; 5xx stays uncertain', async () => {
  for (const [status,outcome] of [[429,'RETRY'],[503,'UNKNOWN'],[400,'FAILED']]) {
    const db = dbMock(); db.rpc = async (name,args) => { db.calls.push([name,args]); return name === 'svc_claim_delivery' ? {
      id: id(1), lease_token: id(2), idempotency_key: id(3), email: 'recipient@example.test', language: 'FR', template: 'MEMBERSHIP_INVITED', body: { invitation_url: 'https://example.test/#secret' },
    } : { outcome: args.p_outcome }; };
    const response = await createHandler('deliver-email', config, { db, fetcher: async () => new Response('{}',{status}) })(worker());
    assert.equal((await response.json()).outcome, outcome);
  }
});
test('missing provider configuration does not claim delivery', async () => {
  const db = dbMock(); assert.equal((await createHandler('deliver-email', {...config, brevoKey: ''}, { db })(worker())).status,503); assert.equal(db.calls.length,0);
});
test('invitation link secrets occur only in fragment and private finalization', async () => {
  const db = dbMock(); db.rpc = async (name,args) => { db.calls.push([name,args]); return name === 'svc_claim_invitation' ? {id:id(1),lease_token:id(2),email:'new@example.test',existing_user:false} : {outcome:'QUEUED'}; };
  db.generateLink = async () => ({id:id(3),hashed_token:'auth-secret',verification_type:'invite'});
  const response = await createHandler('provision-invitation',config,{db})(worker());
  assert.equal(response.status,200); assert.deepEqual(await response.json(),{outcome:'QUEUED'});
  const args = db.calls.at(-1)[1], link = new URL(args.p_link); assert.equal(link.search,'');
  assert.match(args.p_digest,/^[0-9a-f]{64}$/); assert.equal(parseInvitationFragment(link.hash).tokenHash,'auth-secret');
});
test('booking template localizes time in academy timezone without HTML interpolation', () => {
  const d = {language:'FR',template:'BOOKING_APPROVED',body:{academy:'A <test>',starts_at:'2030-01-01T10:00:00Z',timezone:'Africa/Douala'}};
  const email = renderEmail(d); assert.match(email.textContent,/11:00/); assert.equal(email.htmlContent,undefined);
});
test('Storage cleanup calls HTTP deletion before database finalization', async () => {
  const db = dbMock(); db.rpc = async (name,args) => { db.calls.push([name,args]); return name === 'svc_claim_asset_cleanup' ? {asset_id:id(1),bucket:'private',path:'safe'} : {purged:0}; };
  db.remove = async () => { throw new Error('Storage offline'); };
  const response = await createHandler('cleanup-assets-and-content',config,{db})(req({asset_before:'2025-01-01T00:00:00Z'},{'x-worker-secret':config.workerSecret}));
  assert.equal(response.status,500); assert.equal(db.calls.some(x=>x[0]==='svc_finish_asset_cleanup'),false);
});
test('platform authenticates user via Auth HTTP; user RPC never uses service Authorization', async () => {
  const calls=[]; const api=platform(config,async (url,options)=>{calls.push([url,options]);return new Response(JSON.stringify({id:id(1),email_confirmed_at:'2026-01-01'}));});
  await api.user('jwt'); await api.rpc('authorize_asset_read',{},'jwt'); await api.rpc('svc_claim_delivery',{});
  assert.match(calls[0][0],/auth\/v1\/user$/); assert.equal(calls[1][1].headers.Authorization,'Bearer jwt'); assert.equal(calls[2][1].headers.Authorization,'Bearer service');
});
test('provider errors do not leak secrets or emails', async () => {
  const api=platform(config,async()=>new Response('secret recipient@example.test',{status:500}));
  await assert.rejects(api.user('jwt'), error=>error.message==='UPSTREAM_REJECTED');
});
test('Auth transport exposes invite, login, refresh, reset, password and logout with no role injection', async () => {
  const calls=[]; const client=createAuthClient({url:config.supabaseUrl,anonKey:'anon',fetcher:async(url,options)=>{calls.push([url,options]);return new Response('{}');}});
  await client.signIn('a@example.test','password'); await client.refresh('refresh'); await client.requestPasswordReset('a@example.test','http://localhost:5173/auth/recovery');
  await client.verifyEmailToken('hash','invite'); await client.updatePassword('jwt','new-password'); await client.signOut('jwt');
  assert.match(calls[0][0],/grant_type=password/); assert.match(calls[2][0],/recover\?redirect_to=/); assert.equal(calls[4][1].method,'PUT');
  assert.equal(calls[4][1].headers.Authorization,'Bearer jwt'); assert.equal(client.signUp,undefined);
  assert.throws(()=>client.verifyEmailToken('hash','admin'),/INVALID_AUTH_ACTION/);
});
