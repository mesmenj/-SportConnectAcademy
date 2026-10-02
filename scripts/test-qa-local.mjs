// Browser acceptance on the LOCAL disposable stack. Never contacts a remote project.
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { readFileSync, mkdtempSync, openSync, closeSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { randomUUID, randomBytes } from 'node:crypto';
import { createAuthClient, parseInvitationFragment } from '../supabase/auth/client.mjs';
const base='http://127.0.0.1:54321';
const status=spawnSync('supabase',['status','-o','json'],{encoding:'utf8'});
if(status.status!==0)throw new Error('LOCAL_SUPABASE_REQUIRED');
const local=JSON.parse(status.stdout);
assert.equal(new URL(local.API_URL).origin,base);
const workerFile=process.env.SPORTA_EDGE_ENV_FILE??'supabase/functions/.env';
const worker=readFileSync(workerFile,'utf8').match(/^WORKER_SECRET=(.+)$/m)?.[1];
if(!worker)throw new Error('LOCAL_WORKER_SECRET_REQUIRED');
const temp=mkdtempSync(join(tmpdir(),'sporta-qa-'));

const suffix=randomUUID(),password=`Local-${randomBytes(16).toString('hex')}!`;
const rootEmail=`web-root-${suffix}@example.test`,ownerEmail=`web-owner-${suffix}@example.test`;
const apiHeaders=token=>({apikey:local.ANON_KEY,Authorization:`Bearer ${token}`,'Content-Type':'application/json'});
async function post(path,body,token=local.SERVICE_ROLE_KEY){
 const response=await fetch(base+path,{method:'POST',headers:apiHeaders(token),body:JSON.stringify(body),signal:AbortSignal.timeout(20000)});
 const result=await response.json();assert.equal(response.status,200,`Local API ${path}: ${result.code??result.error_code??''}`);return result;
}
function sql(statement){
 const psql=process.env.SPORTA_PG_BIN?`${process.env.SPORTA_PG_BIN}/psql`:'/usr/local/opt/postgresql@17/bin/psql';
 const r=spawnSync(psql,['-X','-At','-v','ON_ERROR_STOP=1','-h','127.0.0.1','-p','54322','-U','postgres','-d','postgres'],{input:statement,encoding:'utf8',env:{PATH:process.env.PATH,PGPASSWORD:'postgres',PGPASSFILE:'/dev/null',PGSERVICEFILE:'/dev/null'}});
 if(r.status!==0)throw new Error('LOCAL_SQL_FIXTURE_FAILED');return r.stdout.trim();
}
const auth=createAuthClient({url:base,anonKey:local.ANON_KEY});
async function provision(id){
 assert.match(id,/^[a-f0-9-]{36}$/);
 for(let n=0;n<30;n++){
  const link=sql(`SELECT p.body->>'invitation_url' FROM private.notification_payloads p JOIN private.notification_deliveries d ON d.id=p.delivery_id JOIN private.notification_events e ON e.id=d.event_id WHERE e.invitation_id='${id}' ORDER BY d.created_at DESC LIMIT 1;`);
  if(link)return link;
  const r=await fetch(`${base}/functions/v1/provision-invitation`,{method:'POST',headers:{'x-worker-secret':worker},body:'{}',signal:AbortSignal.timeout(20000)});assert.equal(r.status,200,'local invitation worker');
 }
 throw new Error('INVITATION_NOT_PROVISIONED');
}
async function acceptHeadless(invitationId,name){
 const i=parseInvitationFragment(new URL(await provision(invitationId)).hash);
 const s=await auth.verifyEmailToken(i.tokenHash,i.type);await auth.acceptInvitation(s.access_token,i,name,'FR',randomUUID());await auth.updatePassword(s.access_token,password);return s;
}
const root=await post('/auth/v1/admin/users',{email:rootEmail,password,email_confirm:true});
sql(`BEGIN; INSERT INTO public.user_profiles(id,display_name,preferred_language,status) VALUES('${root.id}','QA root','FR','ACTIVE'); INSERT INTO private.platform_user_roles(user_id,role_code) VALUES('${root.id}','SUPER_ADMIN'); COMMIT;`);
const rootSession=await auth.signIn(rootEmail,password);
const academy=await post('/rest/v1/rpc/create_academy',{p_name:`QA ${suffix}`,p_city:'Paris',p_country:'FR',p_timezone:'Europe/Paris',p_language:'EN',p_owner_email:ownerEmail,p_invitation_expires_at:new Date(Date.now()+86400000).toISOString(),p_operation_key:randomUUID()},rootSession.access_token);
// The helper prepares REQUESTED and creates an exact clickable link with a fresh
// Auth token. It never verifies/consumes it on behalf of the invited user.
const helper=spawnSync(process.execPath,['scripts/local-invitation-link.mjs',academy.invitation_id],{encoding:'utf8',env:process.env});
assert.equal(helper.status,0,`local link helper failed: ${helper.stderr.replace(/https?:\/\/\S+/g,'[url]')}`);
const htmlPath=helper.stdout.match(/Ouvrez le fichier local : (.+)/)?.[1];assert.ok(htmlPath);
const html=readFileSync(htmlPath,'utf8');
const exact=html.match(/href="([^"]+)"/)?.[1].replaceAll('&amp;','&');assert.ok(exact);
const i=parseInvitationFragment(new URL(exact).hash);
const malformed=await fetch(base+'/auth/v1/verify',{method:'POST',headers:apiHeaders(local.ANON_KEY),body:JSON.stringify({type:i.type,token_hash:'corrupted-token'})});assert.equal(malformed.status,403);
const session=await auth.verifyEmailToken(i.tokenHash,i.type);
await auth.updatePassword(session.access_token,password);
await auth.acceptInvitation(session.access_token,i,'QA Owner','EN',randomUUID());
await assert.rejects(auth.verifyEmailToken(i.tokenHash,i.type),/AUTH_403/);
const owner=await auth.signIn(ownerEmail,password);
const access=await post('/rest/v1/rpc/get_access_context',{p_academy:academy.academy_id},owner.access_token);assert.ok(access.academy_roles.includes('ACADEMY_OWNER'));
console.log('PASS: REQUESTED → fresh exact activation link → password → membership; corrupt and reused tokens refused');
// Exercise private Storage using the caller JWT, including replay and isolation.
const {createRequire}=await import('node:module');const require=createRequire(new URL('../supabase/functions/package.json',import.meta.url));const {PNG}=require('pngjs');
const bytes=PNG.sync.write({width:2,height:2,data:Buffer.alloc(16,255)}),operation=randomUUID();
let assetId;
for(let n=0;n<2;n++){
 const res=await fetch(base+'/functions/v1/secure-asset-upload',{method:'POST',headers:{...apiHeaders(owner.access_token),'Content-Type':'image/png','x-academy-id':academy.academy_id,'x-asset-usage':'BRANDING','x-operation-key':operation},body:bytes,signal:AbortSignal.timeout(30000)});
 assert.equal(res.status,200);const asset=await res.json();assert.equal(asset.outcome,'READY');if(assetId)assert.equal(asset.asset_id,assetId);assetId=asset.asset_id;
}
const signed=await post('/functions/v1/read-asset-url',{academy_id:academy.academy_id,asset_id:assetId},owner.access_token);
assert.equal(new URL(signed.url).origin,base);
const download=await fetch(signed.url);assert.equal(download.status,200);assert.deepEqual(Buffer.from(await download.arrayBuffer()),bytes);
const path=sql(`SELECT object_path FROM private.academy_assets WHERE id='${assetId}';`);
const direct=await fetch(`${base}/storage/v1/object/authenticated/academy-private-assets/${path}`,{headers:apiHeaders(owner.access_token)});assert.ok([400,401,403,404].includes(direct.status));
const other=await fetch(base+'/functions/v1/read-asset-url',{method:'POST',headers:apiHeaders(rootSession.access_token),body:JSON.stringify({academy_id:academy.academy_id,asset_id:assetId})});assert.equal(other.status,403);
const invalid=await fetch(base+'/functions/v1/secure-asset-upload',{method:'POST',headers:{...apiHeaders(owner.access_token),'Content-Type':'image/png','x-academy-id':academy.academy_id,'x-asset-usage':'BRANDING','x-operation-key':randomUUID()},body:Buffer.from('not an image')});assert.equal(invalid.status,400);
console.log('PASS: private asset upload/replay/download, corrupt image rejected, direct and foreign access refused');
const academyRead=await post('/rest/v1/rpc/list_my_academies',{},owner.access_token);assert.equal(academyRead.items[0].timezone,'Europe/Paris');assert.equal(academyRead.items[0].language,'EN');
const language=sql(`SELECT preferred_language FROM public.user_profiles WHERE id='${session.user.id}';`);assert.equal(language,'EN');
const audit=await post('/rest/v1/rpc/read_audit',{p_academy:academy.academy_id,p_limit:100},owner.access_token);assert.ok(audit.items.length>0);
// Realtime is deliberately not enabled for business tables: don't mistake an
// empty publication for a validated live-update feature.
const realtime=sql("SELECT count(*) FROM pg_publication_tables WHERE pubname='supabase_realtime' AND schemaname IN ('public','private');");assert.equal(realtime,'0');
console.log('PASS: EN preference, academy timezone and scoped audit preserved');
console.log('LIMIT: no business table published to Realtime; live-update behavior remains unimplemented');
console.log(`QA local artifacts: ${temp}`);
