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
const temp=mkdtempSync(join(tmpdir(),'sporta-flutter-'));

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
sql(`BEGIN; INSERT INTO public.user_profiles(id,display_name,preferred_language,status) VALUES('${root.id}','Flutter root','FR','ACTIVE'); INSERT INTO private.platform_user_roles(user_id,role_code) VALUES('${root.id}','SUPER_ADMIN'); COMMIT;`);
const rootSession=await auth.signIn(rootEmail,password);
const rpc=(token,name,args)=>post(`/rest/v1/rpc/${name}`,{...args,p_operation_key:randomUUID()},token);
const expires=new Date(Date.now()+7*86400000).toISOString();
const academy=await rpc(rootSession.access_token,'create_academy',{p_name:'Flutter Academy',p_city:'Douala',p_country:'CM',p_timezone:'Africa/Douala',p_language:'FR',p_owner_email:ownerEmail,p_invitation_expires_at:expires});
await acceptHeadless(academy.invitation_id,'Flutter Owner');
const owner=await auth.signIn(ownerEmail,password),id=academy.academy_id;
const command=(name,args)=>rpc(owner.access_token,name,{p_academy:id,...args});
const parentEmail=`flutter-parent-${suffix}@example.test`,coachEmail=`flutter-coach-${suffix}@example.test`;
const parentInvite=await command('invite_member',{p_email:parentEmail,p_roles:['PARENT'],p_expires_at:expires});
await acceptHeadless(parentInvite.invitation_id,'Flutter Parent');
const coachInvite=await command('invite_member',{p_email:coachEmail,p_roles:['COACH'],p_expires_at:expires});
await acceptHeadless(coachInvite.invitation_id,'Flutter Coach');
const parent=await auth.signIn(parentEmail,password);
const coaches=await post('/rest/v1/rpc/list_coaches',{p_academy:id},owner.access_token);
const coach=coaches.items.find(x=>x.display_name==='Flutter Coach');assert.ok(coach);
const player=await rpc(parent.access_token,'create_player',{p_academy:id,p_first_name:'Lina',p_last_name:'Mobile',p_reported_age:14});
const hidden=await command('create_player',{p_first_name:'Private',p_last_name:'Unlinked',p_reported_age:14});
const offer=await command('create_offer',{p_name:'Tennis progression',p_activity:'TENNIS',p_session_type:'GROUP',p_min_age:5,p_max_age:70,p_session_count:10,p_price:'25000',p_currency:'XAF',p_price_basis:'PACKAGE',p_duration_minutes:60});
await command('publish_offer',{p_offer:offer.offer_id});
const pack=await command('purchase_package',{p_player:player.player_id,p_offer:offer.offer_id});
const payment=await command('record_payment',{p_player:player.player_id,p_package:pack.package_id,p_amount:'25000',p_currency:'XAF',p_method:'CASH'});
await command('confirm_payment',{p_payment:payment.payment_id});
await command('activate_package_credit',{p_package:pack.package_id});
const invoice=await command('issue_invoice',{p_payment:payment.payment_id,p_number:`FLUTTER-${suffix}`,p_description:'Forfait du parcours Flutter QA'});
assert.ok(invoice.invoice_id);
const date=days=>new Date(Date.now()+days*86400000).toISOString();
const future=await command('create_session',{p_offer:offer.offer_id,p_coach:coach.id,p_starts_at:date(1),p_ends_at:new Date(Date.now()+86400000+3600000).toISOString(),p_capacity:4});
const past=await command('create_session',{p_offer:offer.offer_id,p_coach:coach.id,p_starts_at:date(2),p_ends_at:new Date(Date.now()+2*86400000+3600000).toISOString(),p_capacity:4});
const booking=await command('schedule_booking',{p_session:past.session_id,p_player:player.player_id,p_package:pack.package_id});
sql(`UPDATE public.sessions SET starts_at=clock_timestamp()-interval '2 hours',ends_at=clock_timestamp()-interval '1 hour' WHERE id='${past.session_id}';`);
const config={SUPABASE_URL:base,SUPABASE_ANON_KEY:local.ANON_KEY,AUTH_RECOVERY_URL:'http://localhost:5173/auth/recovery',TEST_PARENT_EMAIL:parentEmail,TEST_COACH_EMAIL:coachEmail,TEST_PASSWORD:password,TEST_ACADEMY:id,TEST_PLAYER:player.player_id,TEST_HIDDEN_PLAYER:hidden.player_id,TEST_SESSION:future.session_id,TEST_BOOKING:booking.booking_id,TEST_PACKAGE:pack.package_id};
const testConfig=join(temp,'test-config.json');writeFileSync(testConfig,JSON.stringify(config),{mode:0o600});
const publicConfig=join(temp,'public-config.json');writeFileSync(publicConfig,JSON.stringify({SUPABASE_URL:base,SUPABASE_ANON_KEY:local.ANON_KEY,AUTH_RECOVERY_URL:config.AUTH_RECOVERY_URL}),{mode:0o600});
console.log('PASS: local parent, coach, linked player, private player, funded package and sessions prepared');
console.log(`Local artifacts: ${temp}`);
if(!process.env.SPORTA_FIXTURE_ONLY){
 const child=spawnSync('flutter',['test','test/connect/local_integration_test.dart',`--dart-define-from-file=${testConfig}`,'--reporter','expanded'],{cwd:'apps/student',stdio:'inherit'});
 if(child.status!==0)process.exit(child.status??1);
 const balances=await post('/rest/v1/rpc/list_player_packages',{p_academy:id,p_player:player.player_id},owner.access_token);
 const balance=balances.items.find(x=>x.id===pack.package_id);assert.equal(balance.remaining_sessions,9);assert.equal(balance.confirmed_unconsumed_bookings,0);
 const audit=await post('/rest/v1/rpc/read_audit',{p_academy:id,p_limit:100},owner.access_token);
 assert.ok(audit.items.some(x=>x.action==='evaluation.recorded'));
 const ledger=await post('/rest/v1/rpc/list_course_ledger',{p_academy:id,p_package:pack.package_id},owner.access_token);
 assert.equal(ledger.items.reduce((sum,x)=>sum+x.delta,0),9);
 console.log('PASS: owner projection sees Flutter attendance/evaluation, ledger sum 9, audit and issued invoice');
}
