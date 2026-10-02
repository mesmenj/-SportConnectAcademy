import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,writeFileSync,readFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
const ref='abcdefghijklmnopqrst';
function run({project=ref,extraEnv='',extraAuth=''}={}){
 const dir=mkdtempSync(join(tmpdir(),'sporta-staging-preflight-'));
 try{
  const env=join(dir,'test.env'),config=join(dir,'config.toml');
  writeFileSync(env,`PUBLIC_SUPABASE_URL=https://${project}.supabase.co\nALLOWED_ORIGINS=\nINVITATION_CALLBACK_URL=\nWORKER_SECRET=${'worker-test-'.repeat(5)}\nBREVO_WEBHOOK_SECRET=${'webhook-test-'.repeat(5)}\nINVITATION_TOKEN_SECRET=${'invitation-test-'.repeat(5)}\nASSET_URL_TTL_SECONDS=120\nBREVO_API_KEY=\nBREVO_SENDER_EMAIL=\n${extraEnv}`);
  writeFileSync(config,readFileSync('supabase/config.toml','utf8').split('[remotes.staging]')[0]+`\n[remotes.staging]\nproject_id = "${project}"\n[remotes.staging.auth]\nsite_url = "https://${project}.supabase.co"\nadditional_redirect_urls = []\n${extraAuth}`);
  return spawnSync(process.execPath,['scripts/staging-preflight.mjs','--backend-only','--project-ref',project,'--env',env,'--config',config],{encoding:'utf8'});
 }finally{rmSync(dir,{recursive:true,force:true});}
}
test('backend-only staging passes with no domains or email',()=>{const r=run();assert.equal(r.status,0,r.stdout+r.stderr);});
test('production reference is rejected even in backend-only mode',()=>{const r=run({project:'phjzyohsscwrgwvhgvfh'});assert.equal(r.status,1);assert.match(r.stdout,/protected production/);});
test('backend-only refuses an invitation callback',()=>{const r=run({extraEnv:'INVITATION_CALLBACK_URL=https://example.test/auth/invitation\n'});assert.equal(r.status,1);assert.match(r.stdout,/FAIL Backend only/);});
test('backend-only refuses enabled external email',()=>{const r=run({extraEnv:'BREVO_API_KEY=fake-key\nBREVO_SENDER_EMAIL=test@example.test\n'});assert.equal(r.status,1);assert.match(r.stdout,/FAIL Backend only: external email/);});
test('backend-only refuses Auth redirects and reenabled signup',()=>{const r=run({extraAuth:'additional_redirect_urls = ["https://example.test/auth/invitation"]\nenable_signup = true\n'});assert.equal(r.status,1);assert.match(r.stdout,/FAIL Backend only: no Auth redirect/);assert.match(r.stdout,/FAIL Config: staging does not re-enable/);});
