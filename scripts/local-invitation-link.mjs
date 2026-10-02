// Operator-only local review helper. Never send email, consume a token or set a password.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {readFileSync,writeFileSync,mkdtempSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
const id=process.argv[2];
assert.match(id??'',/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i,'Provide the invitation UUID shown in the Web interface');
const status=spawnSync('supabase',['status','-o','json'],{encoding:'utf8'});
assert.equal(status.status,0,'LOCAL_SUPABASE_REQUIRED');
const local=JSON.parse(status.stdout);assert.equal(local.API_URL,'http://127.0.0.1:54321');
function sql(query){
 const r=spawnSync(process.env.SPORTA_PG_BIN?`${process.env.SPORTA_PG_BIN}/psql`:'/usr/local/opt/postgresql@17/bin/psql',['-X','-At','-v','ON_ERROR_STOP=1','-h','127.0.0.1','-p','54322','-U','postgres','-d','postgres'],{input:query,encoding:'utf8',env:{PATH:process.env.PATH,PGPASSWORD:'postgres',PGPASSFILE:'/dev/null',PGSERVICEFILE:'/dev/null'}});
 if(r.status!==0)throw Error('LOCAL_SQL_FAILED');return r.stdout.trim();
}
function invitation(){
 const raw=sql(`SELECT jsonb_build_object('id',i.id,'email',i.email,'status',i.status,'valid',i.expires_at>now(),'user_id',(SELECT u.id FROM auth.users u WHERE lower(u.email)=i.email)) FROM private.academy_invitations i WHERE i.id='${id}';`);
 if(!raw)throw Error('INVITATION_NOT_FOUND');return JSON.parse(raw);
}
let state=invitation();
if(!state.valid||['ACCEPTED','REVOKED','EXPIRED'].includes(state.status))throw Error('Use the application to resend an expired invitation, or sign in to an already activated account.');
if(state.status!=='SENT'){
 const worker=readFileSync(process.env.SPORTA_EDGE_ENV_FILE??'supabase/functions/.env','utf8').match(/^WORKER_SECRET=(.+)$/m)?.[1];
 if(!worker)throw Error('LOCAL_WORKER_SECRET_REQUIRED');
 for(let n=0;n<30&&state.status!=='SENT';n++){
  const response=await fetch(`${local.API_URL}/functions/v1/provision-invitation`,{method:'POST',headers:{'x-worker-secret':worker},body:'{}',signal:AbortSignal.timeout(20000)});
  if(!response.ok)throw Error(`LOCAL_WORKER_${response.status}`);
  state=invitation();
 }
}
assert.equal(state.status,'SENT','INVITATION_NOT_READY');
// invited_user_id is only set at acceptance. Before that, the invitation identity is
// the Auth user with the invitation email, as enforced by svc_finish_invitation.
assert.ok(state.user_id,'INVITED_AUTH_USER_MISSING');
const raw=sql(`SELECT p.body->>'invitation_url' FROM private.notification_payloads p JOIN private.notification_deliveries d ON d.id=p.delivery_id JOIN private.notification_events e ON e.id=d.event_id WHERE e.invitation_id='${id}' ORDER BY d.created_at DESC LIMIT 1;`);
if(!raw)throw Error('INVITATION_PAYLOAD_UNAVAILABLE');
const link=new URL(raw);assert.equal(link.origin,'http://localhost:5173');
// The Auth token can expire before the business invitation. Generate it now,
// preserving the invitation token and identity. No credentials reach the app.
const response=await fetch(`${local.API_URL}/auth/v1/admin/generate_link`,{method:'POST',headers:{apikey:local.SERVICE_ROLE_KEY,Authorization:`Bearer ${local.SERVICE_ROLE_KEY}`,'Content-Type':'application/json'},body:JSON.stringify({type:'magiclink',email:state.email}),signal:AbortSignal.timeout(15000)});
if(!response.ok)throw Error(`LOCAL_AUTH_${response.status}`);
const result=await response.json();assert.equal(result.id,state.user_id);assert.ok(result.hashed_token);assert.ok(['invite','magiclink'].includes(result.verification_type));
const fragment=new URLSearchParams(link.hash.slice(1));fragment.set('token_hash',result.hashed_token);fragment.set('type',result.verification_type);link.hash=fragment.toString();
const temp=mkdtempSync(join(tmpdir(),'sporta-invitation-'));
writeFileSync(join(temp,'link.txt'),link.href+'\n',{mode:0o600});
const escaped=link.href.replaceAll('&','&amp;').replaceAll('"','&quot;').replaceAll('<','&lt;');
writeFileSync(join(temp,'activation.html'),`<!doctype html><html lang="fr"><meta charset="utf-8"><meta name="referrer" content="no-referrer"><title>Activation locale Sport Connect</title><h1>Activer votre accès local</h1><p>Ouvrez le lien sur ce Mac, puis choisissez votre mot de passe. Ne partagez pas ce fichier.</p><p><a href="${escaped}">Activer mon accès</a></p></html>`,{mode:0o600});
console.log(`Ouvrez le fichier local : ${join(temp,'activation.html')}`);
console.log('Lien personnel fraîchement généré ; aucun email envoyé. Ne recopiez pas les jetons à la main.');
