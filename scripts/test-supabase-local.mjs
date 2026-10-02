// Real Auth/PostgREST/Storage smoke test. Explicitly refuses non-loopback URLs.
// Requires a disposable Supabase stack + `supabase functions serve` already running.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { createRequire } from 'node:module';
import { readFile } from 'node:fs/promises';
import { createAuthClient, parseInvitationFragment } from '../supabase/auth/client.mjs';
const require = createRequire(new URL('../supabase/functions/package.json', import.meta.url));
const { PNG } = require('pngjs');
const base = process.env.SPORTA_LOCAL_URL ?? 'http://127.0.0.1:54321';
const parsed = new URL(base);
if (parsed.protocol !== 'http:' || !['127.0.0.1','localhost','[::1]'].includes(parsed.hostname) || parsed.port !== '54321' || parsed.pathname !== '/' || parsed.username || parsed.password)
 throw new Error('LOCAL_DISPOSABLE_STACK_REQUIRED');
const key = process.env.SPORTA_LOCAL_ANON_KEY, service = process.env.SPORTA_LOCAL_SERVICE_KEY, worker = process.env.WORKER_SECRET;
if (!key || !service || !worker) throw new Error('Set SPORTA_LOCAL_ANON_KEY, SPORTA_LOCAL_SERVICE_KEY and WORKER_SECRET from your LOCAL stack.');
const suffix = randomUUID();
const headers = token => ({apikey: key,Authorization:`Bearer ${token}`,'Content-Type':'application/json'});
async function json(path, body, token = service, expected = 200) {
 const r = await fetch(base+path,{method:'POST',headers:headers(token),body:JSON.stringify(body),signal:AbortSignal.timeout(20000),redirect:'error'});
 const data=await r.json();
 assert.equal(r.status,expected,`HTTP ${path}: ${data.code ?? data.error_code ?? ''} ${data.message ?? ''}`); return data;
}
function sql(statement) {
 const psql = process.env.SPORTA_PG_BIN ? `${process.env.SPORTA_PG_BIN}/psql` : '/usr/local/opt/postgresql@17/bin/psql';
 const result=spawnSync(psql,['-X','-At','-v','ON_ERROR_STOP=1','-h','127.0.0.1','-p','54322','-U','postgres','-d','postgres'], {
 input:statement,encoding:'utf8',env:{PATH:process.env.PATH,PGPASSWORD:'postgres',PGSERVICEFILE:'/dev/null',PGPASSFILE:'/dev/null'},
 });
 if(result.status!==0) throw new Error('LOCAL_SQL_FAILED (diagnostics suppressed to avoid token leakage)');
 return result.stdout.trim();
}
const rpc=(name,args,token)=>json(`/rest/v1/rpc/${name}`,args,token);
const signup=await fetch(`${base}/auth/v1/signup`,{method:'POST',headers:headers(key),
 body:JSON.stringify({email:`blocked-${suffix}@example.test`,password:'Local-test-only-12!'})});
assert.equal(signup.status,422); assert.equal((await signup.json()).error_code,'signup_disabled');
// Exercise the deployed handlers, including endpoints not used by onboarding.
for (const name of ['provision-invitation','expand-email-outbox','deliver-email','schedule-notifications',
 'cleanup-assets-and-content','brevo-webhook','secure-asset-upload','read-asset-url']) {
 const denied=await fetch(`${base}/functions/v1/${name}`,{method:'POST',body:'{}',signal:AbortSignal.timeout(30000)});
 assert.equal(denied.status,401,`${name}: unauthenticated request`);
}
const root=await json('/auth/v1/admin/users',{email:`root-${suffix}@example.test`,password:'Local-test-only-12!',email_confirm:true});
assert.match(root.id,/^[a-f0-9-]{36}$/);
// Only synthetic local fixtures. No reusable platform bootstrap endpoint exists.
sql(`BEGIN; INSERT INTO public.user_profiles(id,display_name,preferred_language,status) VALUES('${root.id}','Integration fixture','FR','ACTIVE');
INSERT INTO private.platform_user_roles(user_id,role_code) VALUES('${root.id}','SUPER_ADMIN'); COMMIT;`);
const auth=createAuthClient({url:base,anonKey:key});
const rootSession=await auth.signIn(root.email,'Local-test-only-12!');
const academy=await rpc('create_academy',{p_name:`Local ${suffix}`,p_city:'Douala',p_country:'CM',p_timezone:'Africa/Douala',p_language:'FR',
 p_owner_email:`owner-${suffix}@example.test`,p_invitation_expires_at:new Date(Date.now()+86400000).toISOString(),p_operation_key:randomUUID()},rootSession.access_token);
assert.ok(academy.academy_id);
// Dedicated test stack must have no pre-existing pending invitation jobs.
const provision=await fetch(`${base}/functions/v1/provision-invitation`,{method:'POST',headers:{'x-worker-secret':worker},body:'{}',signal:AbortSignal.timeout(20000),redirect:'error'});
assert.equal(provision.status,200); assert.equal((await provision.json()).outcome,'QUEUED');
const invitationId=academy.invitation_id; assert.match(invitationId,/^[a-f0-9-]{36}$/);
const link=sql(`SELECT p.body->>'invitation_url' FROM private.notification_payloads p JOIN private.notification_deliveries d ON d.id=p.delivery_id
JOIN private.notification_events e ON e.id=d.event_id WHERE e.invitation_id='${invitationId}';`);
const invitation=parseInvitationFragment(new URL(link).hash);
const ownerSession=await auth.verifyEmailToken(invitation.tokenHash,invitation.type);
const accepted=await auth.acceptInvitation(ownerSession.access_token,invitation,'Owner','FR',randomUUID());
assert.equal(accepted.academy_id,academy.academy_id);
await auth.updatePassword(ownerSession.access_token,'Local-owner-only-12!');
const login=await auth.signIn(`owner-${suffix}@example.test`,'Local-owner-only-12!');
const refreshed=await auth.refresh(login.refresh_token); assert.ok(refreshed.access_token);
// Actual GoTrue recovery token, then actual reset and password login.
await auth.requestPasswordReset(`owner-${suffix}@example.test`,'http://localhost:5173/auth/recovery');
const recovery=await json('/auth/v1/admin/generate_link',{type:'recovery',email:`owner-${suffix}@example.test`});
const recoverySession=await auth.verifyEmailToken(recovery.hashed_token,'recovery');
await auth.updatePassword(recoverySession.access_token,'Local-owner-reset-12!');
// Password recovery revokes earlier sessions; continue with the new login.
const ownerJwt=(await auth.signIn(`owner-${suffix}@example.test`,'Local-owner-reset-12!')).access_token;
assert.ok(ownerJwt);
const userRpc=await fetch(`${base}/rest/v1/rpc/svc_claim_invitation`,{method:'POST',headers:headers(ownerJwt),body:'{}'});
assert.ok([401,403,404].includes(userRpc.status));
const anonymous=await fetch(`${base}/rest/v1/academies?select=id`,{headers:headers(key)}); assert.ok([401,403].includes(anonymous.status));
const foreign=await fetch(`${base}/rest/v1/rpc/authorize_asset_read`,{method:'POST',headers:headers(ownerJwt),body:JSON.stringify({p_academy:randomUUID(),p_asset:randomUUID()})}); assert.equal(foreign.status,403);
const bytes=PNG.sync.write({width:2,height:2,data:Buffer.alloc(16,255)});
const upload=await fetch(`${base}/functions/v1/secure-asset-upload`,{method:'POST',headers:{...headers(ownerJwt),'Content-Type':'image/png',
 'x-academy-id':academy.academy_id,'x-asset-usage':'BRANDING','x-operation-key':randomUUID()},body:bytes,signal:AbortSignal.timeout(30000)});
const asset=await upload.json(); assert.equal(upload.status,200,`PNG upload: ${asset.error ?? ''}`); assert.equal(asset.outcome,'READY');
const signed=await json('/functions/v1/read-asset-url',{academy_id:academy.academy_id,asset_id:asset.asset_id},ownerJwt);
assert.equal(new URL(signed.url).hostname,new URL(base).hostname); // test config must use the same loopback origin
const download=await fetch(signed.url); assert.equal(download.status,200); assert.deepEqual(Buffer.from(await download.arrayBuffer()),bytes);
const path=sql(`SELECT object_path FROM private.academy_assets WHERE id='${asset.asset_id}';`);
const direct=await fetch(`${base}/storage/v1/object/authenticated/academy-private-assets/${path}`,{headers:headers(ownerJwt)}); assert.ok([400,401,403,404].includes(direct.status));
// WebP loads a bundled WASM file: type checks alone cannot validate its availability in Edge.
const { default: encodeWebp, init: initWebp }=await import('../supabase/functions/node_modules/@jsquash/webp/encode.js');
await initWebp(await WebAssembly.compile(await readFile(new URL('../supabase/functions/node_modules/@jsquash/webp/codec/enc/webp_enc.wasm',import.meta.url))));
const jpeg=require('jpeg-js').encode({width:2,height:2,data:Buffer.alloc(16,255)},80).data;
const webp=new Uint8Array(await encodeWebp({width:2,height:2,data:new Uint8ClampedArray(16).fill(255)},{lossless:1}));
for (const [mime,body] of [['image/jpeg',jpeg],['image/webp',webp]]) {
 const operation=randomUUID(); let assetId;
 for (let attempt=0;attempt<2;attempt++) {
  const response=await fetch(`${base}/functions/v1/secure-asset-upload`,{method:'POST',headers:{...headers(ownerJwt),'Content-Type':mime,
   'x-academy-id':academy.academy_id,'x-asset-usage':'BRANDING','x-operation-key':operation},body,signal:AbortSignal.timeout(30000)});
  assert.equal(response.status,200,`${mime}: upload/replay`); const result=await response.json();
  assert.equal(result.outcome,'READY'); if(assetId) assert.equal(result.asset_id,assetId); assetId=result.asset_id;
 }
}
for (const name of ['expand-email-outbox','schedule-notifications','cleanup-assets-and-content']) {
 const response=await fetch(`${base}/functions/v1/${name}`,{method:'POST',headers:{'x-worker-secret':worker,'Content-Type':'application/json'},body:'{}',signal:AbortSignal.timeout(20000)});
 assert.equal(response.status,200,`${name}: authorized worker`);
}
// Delivery stays disabled without provider credentials: no external email is sent.
const delivery=await fetch(`${base}/functions/v1/deliver-email`,{method:'POST',headers:{'x-worker-secret':worker},body:'{}'});
assert.equal(delivery.status,503); assert.equal((await delivery.json()).error,'CONFIG_REQUIRED');
await auth.signOut(ownerJwt);
console.log('PASS: real local Auth invitation/login/refresh/recovery, owner onboarding, PostgREST denial, PNG/JPEG/WebP upload/replay, signed download, eight Edge auth guards and local workers.');
console.log('Synthetic fixtures remain in the disposable stack; no remote service or external email delivery was used.');
