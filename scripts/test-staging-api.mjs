// Read/negative probes only. No email, account, academy or asset is created.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {readFileSync,writeFileSync} from 'node:fs';
import {randomUUID} from 'node:crypto';
const ref='ordjngzihkmknnizlujp',base=`https://${ref}.supabase.co`,dir='supabase/.temp/staging-deploy';
assert.equal(process.argv[2],ref,'Pass the exact authorized staging reference');
assert.equal(JSON.parse(readFileSync(dir+'/created-project.json','utf8')).id,ref);
const result=spawnSync('supabase',['projects','api-keys','--project-ref',ref,'--output','json'],{encoding:'utf8'});
assert.equal(result.status,0,'STAGING_API_KEYS_UNAVAILABLE');
const keys=JSON.parse(result.stdout),anon=keys.find(k=>k.name==='anon')?.api_key;
assert.ok(anon,'Public anon key required');
const headers={apikey:anon,Authorization:`Bearer ${anon}`,'Content-Type':'application/json'};
const request=(path,options={})=>fetch(base+path,{...options,signal:AbortSignal.timeout(45000),redirect:'error'});
const settingsResponse=await request('/auth/v1/settings',{headers});assert.equal(settingsResponse.status,200);
const settings=await settingsResponse.json();assert.equal(settings.disable_signup,true);assert.equal(settings.mailer_autoconfirm,false);
console.log('PASS: Auth available, signup disabled, email confirmation required');
const signup=await request('/auth/v1/signup',{method:'POST',headers,body:JSON.stringify({email:`denied-${randomUUID()}@example.test`,password:`Denied-${randomUUID()}`})});
assert.equal(signup.status,422);assert.equal((await signup.json()).error_code,'signup_disabled');
for(const table of ['academies','players','bookings']){
 const r=await request(`/rest/v1/${table}?select=id&limit=1`,{headers});assert.ok([401,403].includes(r.status),`${table}: ${r.status}`);
}
for(const schema of ['private','ops','net','vault','cron']){
 const r=await request('/rest/v1/worker_schedule?select=worker&limit=1',{headers:{...headers,'Accept-Profile':schema}});assert.equal(r.status,406,`${schema}: must be unexposed`);
}
console.log('PASS: anonymous business reads denied; private/ops/net/vault/cron unexposed');
const functions=['provision-invitation','secure-asset-upload','read-asset-url','expand-email-outbox','deliver-email','brevo-webhook','schedule-notifications','cleanup-assets-and-content'];
for(const name of functions){const r=await request(`/functions/v1/${name}`,{method:'POST',body:'{}'});assert.equal(r.status,401,`${name}: ${r.status}`);}
console.log('PASS: all 8 deployed Edge functions start and deny unauthorized requests');
const origin=await request('/functions/v1/read-asset-url',{method:'OPTIONS',headers:{Origin:'https://unconfigured.example.test'}});assert.equal(origin.status,403);
const worker=readFileSync(dir+'/edge.env','utf8').match(/^WORKER_SECRET=(.+)$/m)?.[1];assert.ok(worker);
for(const name of ['provision-invitation','deliver-email']){
 const r=await request(`/functions/v1/${name}`,{method:'POST',headers:{'x-worker-secret':worker},body:'{}'});assert.equal(r.status,503);assert.equal((await r.json()).error,'CONFIG_REQUIRED');
}
console.log('PASS: frontend CORS denied and invitation/email workers fail closed before claiming work');
writeFileSync(dir+'/api-verification.json',JSON.stringify({project:ref,checked_at:new Date().toISOString(),functions,signup_disabled:true,private_schemas_exposed:false,frontend_enabled:false,email_enabled:false},null,2)+'\n',{mode:0o600});
