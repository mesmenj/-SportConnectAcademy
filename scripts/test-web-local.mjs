// Browser acceptance on the LOCAL disposable stack. Never contacts a remote project.
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { readFileSync, mkdtempSync, openSync, closeSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { randomUUID, randomBytes } from 'node:crypto';
import { chromium, expect } from '@playwright/test';
import { createAuthClient, parseInvitationFragment } from '../supabase/auth/client.mjs';
const base='http://127.0.0.1:54321';
const academyPort=Number(process.env.SPORTA_WEB_ACADEMY_PORT??5273),platformPort=Number(process.env.SPORTA_WEB_PLATFORM_PORT??5274);
for(const port of [academyPort,platformPort])assert.ok(Number.isInteger(port)&&port>=1024&&port<=65535);
assert.notEqual(academyPort,platformPort);
const academyOrigin=`http://localhost:${academyPort}`,platformOrigin=`http://localhost:${platformPort}`;
const status=spawnSync('supabase',['status','-o','json'],{encoding:'utf8'});
if(status.status!==0)throw new Error('LOCAL_SUPABASE_REQUIRED');
const local=JSON.parse(status.stdout);
assert.equal(new URL(local.API_URL).origin,base);
const workerFile=process.env.SPORTA_EDGE_ENV_FILE??'supabase/functions/.env';
const worker=readFileSync(workerFile,'utf8').match(/^WORKER_SECRET=(.+)$/m)?.[1];
if(!worker)throw new Error('LOCAL_WORKER_SECRET_REQUIRED');
const temp=mkdtempSync(join(tmpdir(),'sporta-web-'));
const log=openSync(join(temp,'servers.log'),'w',0o600),children=[];
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
async function start(port,app){
 const processEnv={...process.env,VITE_SUPABASE_URL:base,VITE_SUPABASE_ANON_KEY:local.ANON_KEY,VITE_DESIGN_PREVIEW:'false'};
 // Service credentials are never passed to Vite or the browser.
 delete processEnv.SPORTA_LOCAL_SERVICE_KEY;delete processEnv.SUPABASE_SERVICE_ROLE_KEY;delete processEnv.WORKER_SECRET;
 const child=spawn(process.execPath,[`${process.cwd()}/apps/${app}/node_modules/vite/bin/vite.js`,'--host','127.0.0.1','--port',String(port),'--strictPort'],{cwd:`${process.cwd()}/apps/${app}`,env:processEnv,stdio:['ignore',log,log]});
 // Resolve the executable relative to the repository, not the app working directory.
 children.push(child);
 for(let attempt=0;attempt<100;attempt++){
  if(child.exitCode!==null)throw new Error(`WEB_SERVER_FAILED_${port}`);
  try{if((await fetch(`http://127.0.0.1:${port}`,{signal:AbortSignal.timeout(500)})).ok)return;}catch{}
  await new Promise(r=>setTimeout(r,200));
 }
 throw new Error('WEB_SERVER_TIMEOUT');
}
let browser;
const browserErrors=[];
async function login(page,origin,email){await page.goto(origin);await page.getByLabel('Adresse email').fill(email);await page.getByLabel('Mot de passe',{exact:true}).fill(password);await page.getByRole('button',{name:'Se connecter',exact:true}).click();await expect(page.getByRole('navigation')).toBeVisible();}
async function navigate(page,label){await page.getByRole('navigation').getByRole('button',{name:label,exact:true}).click();await expect(page.getByRole('heading',{level:1,name:label,exact:true})).toBeVisible();}
async function fill(page,values){
 const d=page.getByRole('dialog');
 for(const [key,value] of Object.entries(values)){
  const control=d.locator(`[name="${key}"]`);await expect(control).toBeEnabled();
  const tag=await control.evaluate(el=>el.tagName);
  if(tag==='SELECT'){if(typeof value==='object'&&!Array.isArray(value))await control.selectOption(value);else await control.selectOption(value);}
  else await control.fill(String(value));
 }
}
async function submit(page,rpc,values={}){
 await fill(page,values);
 const result=page.waitForResponse(r=>r.url()===`${base}/rest/v1/rpc/${rpc}`&&r.request().method()==='POST');
 await page.getByRole('dialog').getByRole('button',{name:'Confirmer',exact:true}).click();
 const response=await result,body=await response.json();
 assert.equal(response.status(),200,`UI ${rpc}: ${body.message??''}`);
 await expect(page.getByRole('dialog')).toHaveCount(0);return body;
}
async function create(page,nav,label,rpc,values){await navigate(page,nav);await page.getByRole('button',{name:label,exact:false}).first().click();return submit(page,rpc,values);}
async function rowAction(page,match,label,rpc,values={}){
 const row=page.locator('tbody tr').filter({hasText:match});await expect(row).toHaveCount(1);await row.getByRole('button',{name:/Ouvrir/}).click();
 await page.getByRole('dialog').getByRole('button',{name:label,exact:true}).click();return submit(page,rpc,values);
}
try{
 // New Auth identity + root bootstrap are synthetic fixtures only, not a public application endpoint.
 const root=await post('/auth/v1/admin/users',{email:rootEmail,password,email_confirm:true});assert.match(root.id,/^[a-f0-9-]{36}$/);
 sql(`BEGIN; INSERT INTO public.user_profiles(id,display_name,preferred_language,status) VALUES('${root.id}','Web test root','FR','ACTIVE'); INSERT INTO private.platform_user_roles(user_id,role_code) VALUES('${root.id}','SUPER_ADMIN'); COMMIT;`);
 await start(academyPort,'academy-admin');await start(platformPort,'platform-admin');
 browser=await chromium.launch({channel:'chromium',headless:true});
 const context=await browser.newContext({viewport:{width:1440,height:1000}});
 context.on('page',page=>page.on('pageerror',error=>browserErrors.push(error.message)));
 context.on('request',request=>{if(request.url().startsWith(base))assert.notEqual(request.headers().authorization,`Bearer ${local.SERVICE_ROLE_KEY}`,'service key must never reach browser');});
 const platform=await context.newPage(),academyPage=await context.newPage();
 await login(platform,platformOrigin,rootEmail);
 const date=(offsetDays=0)=>{const d=new Date(Date.now()+offsetDays*86400000);d.setUTCHours(10,0,0,0);return d.toISOString().slice(0,16);};
 const academy=await create(platform,'Académies','Créer une académie','create_academy',{p_name:`Web Academy ${suffix.slice(0,8)}`,p_city:'Douala',p_country:'CM',p_timezone:'Africa/Douala',p_language:'FR',p_owner_email:ownerEmail,p_invitation_expires_at:date(7)});
 console.log('PASS: platform login, create academy and owner invitation via browser');
 const sourceLink=new URL(await provision(academy.invitation_id));assert.equal(sourceLink.origin,'http://localhost:5173');
 const link=academyOrigin+sourceLink.pathname+sourceLink.hash;
 await academyPage.goto(link);await expect(academyPage.getByLabel('Nom complet')).toBeVisible();
 await academyPage.getByLabel('Nom complet').fill('Web Owner');await academyPage.getByLabel('Mot de passe',{exact:true}).fill(password);await academyPage.getByRole('button',{name:'Activer mon accès'}).click();
 await expect(academyPage.getByRole('navigation')).toBeVisible();assert.equal(new URL(academyPage.url()).hash,'');
 await academyPage.reload();await expect(academyPage.getByRole('navigation')).toBeVisible();
 console.log('PASS: owner callback, token fragment removal and session restoration');
 const coachEmail=`web-coach-${suffix}@example.test`;
 const invitation=await create(academyPage,'Invitations','Inviter un membre','invite_member',{p_email:coachEmail,p_roles:['PARENT'],p_expires_at:date(7)});
 await acceptHeadless(invitation.invitation_id,'Web Coach');
 const ownerSession=await auth.signIn(ownerEmail,password);
 const memberships=await post('/rest/v1/rpc/list_memberships',{p_academy:academy.academy_id},ownerSession.access_token);
 const coachMember=memberships.items.find(r=>r.display_name==='Web Coach');assert.ok(coachMember);
 await navigate(academyPage,'Équipe et accès');
 await rowAction(academyPage,'Web Coach','Modifier les rôles','set_membership_roles',{p_roles:['COACH'],p_reason:'Affectation coach pour test local'});
 const coach=await create(academyPage,'Coachs','Ajouter un coach','create_coach',{p_membership:coachMember.id,p_specialties:'Tennis'});
 const player=await create(academyPage,'Joueurs','Ajouter un joueur','create_player',{p_first_name:'Lina',p_last_name:suffix.slice(0,8),p_birth_date:'2012-05-12'});
 const stadium=await create(academyPage,'Sites sportifs','Ajouter un site','create_stadium',{p_name:'Court central',p_address:'Douala'});
 const court=await create(academyPage,'Courts','Ajouter un court','create_court',{p_stadium:stadium.stadium_id,p_number:'1',p_label:'Court A'});
 const offer=await create(academyPage,'Offres','Créer une offre','create_offer',{p_name:'Tennis progression',p_activity:'TENNIS',p_session_type:'GROUP',p_min_age:'5',p_max_age:'70',p_session_count:'10',p_price:'25000',p_currency:'XAF',p_price_basis:'PACKAGE',p_duration_minutes:'60'});
 await rowAction(academyPage,'Tennis progression','Publier l’offre','publish_offer');
 const packageResult=await create(academyPage,'Forfaits des joueurs','Acheter un forfait','purchase_package',{p_player:player.player_id,p_offer:offer.offer_id});
 const payment=await create(academyPage,'Encaissements','Enregistrer un règlement','record_payment',{p_player:player.player_id,p_package:packageResult.package_id,p_amount:'25000',p_currency:'XAF',p_method:'CASH'});
 await rowAction(academyPage,'25000.00','Confirmer l’encaissement','confirm_payment');
 await rowAction(academyPage,'25000.00','Émettre la facture','issue_invoice',{p_number:`WEB-${suffix.slice(0,8)}`,p_description:'Forfait tennis'});
 await navigate(academyPage,'Forfaits des joueurs');await academyPage.getByLabel('Joueur à consulter').selectOption(player.player_id);
 await rowAction(academyPage,'25000.00','Activer les crédits','activate_package_credit');
 const session=await create(academyPage,'Séances','Planifier une séance','create_session',{p_offer:offer.offer_id,p_coach:coach.coach_id,p_starts_at:date(1),p_ends_at:date(1).replace('T10:00','T11:00'),p_capacity:'4',p_stadium:stadium.stadium_id,p_court:court.court_id});
 const booking=await create(academyPage,'Réservations et présences','Planifier une réservation','schedule_booking',{p_session:session.session_id,p_player:player.player_id,p_package:packageResult.package_id});
 await expect(academyPage.locator('tbody')).toContainText('Confirmé');
 console.log('PASS: coach, player, sites/courts, offer, package, payment/invoice and confirmed booking through Web RPC forms');
 // Only move our synthetic session in time to exercise attendance without waiting a day.
 sql(`UPDATE public.sessions SET starts_at=clock_timestamp()-interval '2 hours',ends_at=clock_timestamp()-interval '1 hour' WHERE id='${session.session_id}';`);
 await academyPage.getByRole('button',{name:'Actualiser',exact:true}).click();
 await rowAction(academyPage,'Confirmé','Saisir la présence','record_attendance',{p_attended:'true'});
 await rowAction(academyPage,'Terminé','Évaluer le joueur','record_evaluation',{p_technical:'4',p_tactical:'3',p_physical:'4',p_behavior:'5',p_comment:'Très bonne progression'});
 const balances=await post('/rest/v1/rpc/list_player_packages',{p_academy:academy.academy_id,p_player:player.player_id},ownerSession.access_token);
 assert.equal(balances.items[0].remaining_sessions,9);assert.equal(balances.items[0].confirmed_unconsumed_bookings,0);
 await navigate(academyPage,'Évaluations');await expect(academyPage.locator('tbody')).toContainText('Très bonne progression');
 console.log('PASS: attendance, evaluation and authoritative credit balance R=9 H=0');
 // D34 remains authoritative even when the UI requests a quota override.
 await navigate(academyPage,'Forfaits des joueurs');await academyPage.getByLabel('Joueur à consulter').selectOption(player.player_id);
 await rowAction(academyPage,'25000.00','Ajuster les crédits','adjust_course_credit',{p_delta:'-9',p_reason:'Test quota épuisé'});
 const future=await create(academyPage,'Séances','Planifier une séance','create_session',{p_offer:offer.offer_id,p_coach:coach.coach_id,p_starts_at:date(2),p_ends_at:date(2).replace('T10:00','T11:00'),p_capacity:'4',p_stadium:stadium.stadium_id,p_court:court.court_id});
 const waiting=await create(academyPage,'Réservations et présences','Planifier une réservation','schedule_booking',{p_session:future.session_id,p_player:player.player_id,p_package:packageResult.package_id,p_overrides:['quota'],p_reason:'Demande en attente de crédit'});
 assert.equal(waiting.status,'PENDING');await expect(academyPage.getByRole('status').filter({hasText:'Réservation en attente'})).toContainText('Aucun crédit ni place');
 const zero=await post('/rest/v1/rpc/list_player_packages',{p_academy:academy.academy_id,p_player:player.player_id},ownerSession.access_token);
 assert.equal(zero.items[0].remaining_sessions,0);assert.equal(zero.items[0].confirmed_unconsumed_bookings,0);
 // Another operator changes the reservation while this form still has its old revision.
 await academyPage.locator('tbody tr').filter({hasText:'En attente'}).getByRole('button',{name:/Ouvrir/}).click();
 await academyPage.getByRole('dialog').getByRole('button',{name:'Approuver',exact:true}).click();
 await post('/rest/v1/rpc/adjust_course_credit',{p_academy:academy.academy_id,p_package:packageResult.package_id,p_delta:1,p_reason:'Crédit de test',p_operation_key:randomUUID()},ownerSession.access_token);
 await post('/rest/v1/rpc/approve_booking',{p_academy:academy.academy_id,p_booking:waiting.booking_id,p_expected_revision:waiting.revision,p_operation_key:randomUUID()},ownerSession.access_token);
 await academyPage.getByRole('dialog').getByRole('button',{name:'Confirmer',exact:true}).click();
 await expect(academyPage.getByRole('alert')).toContainText('Cet élément a changé');await academyPage.getByRole('dialog').getByRole('button',{name:'Fermer',exact:true}).first().click();
 console.log('PASS: D34 quota override stays pending at zero credit and stale revision is refused');
 // Network response lost after the server commits: the retry must reuse its operation key.
 await navigate(academyPage,'Joueurs');let intercepted=false,operationKey;
 await academyPage.route('**/rest/v1/rpc/create_player',async route=>{
  const body=route.request().postDataJSON();if(!intercepted){intercepted=true;operationKey=body.p_operation_key;await route.fetch();await route.abort('failed');}else{assert.equal(body.p_operation_key,operationKey);await route.continue();}
 });
 await academyPage.getByRole('button',{name:'Ajouter un joueur',exact:false}).click();await fill(academyPage,{p_first_name:'Retry',p_last_name:'Unique'});await academyPage.getByRole('dialog').getByRole('button',{name:'Confirmer',exact:true}).click();
 await expect(academyPage.getByRole('dialog').getByRole('button',{name:'Réessayer la même opération'})).toBeVisible();
 await academyPage.reload();await expect(academyPage.getByRole('button',{name:'Reprendre l’opération'})).toBeVisible();await academyPage.getByRole('button',{name:'Reprendre l’opération'}).click();await academyPage.getByRole('dialog').getByRole('button',{name:'Réessayer la même opération'}).click();await expect(academyPage.getByRole('dialog')).toHaveCount(0);
 assert.equal(sql(`SELECT count(*) FROM public.players WHERE academy_id='${academy.academy_id}' AND first_name='Retry';`),'1');
 await academyPage.unroute('**/rest/v1/rpc/create_player');
 console.log('PASS: lost response, page reload and idempotent retry without duplicate player');
 // The same owner joins a second tenant; a late response from tenant A must not appear in B.
 const second=await create(platform,'Académies','Créer une académie','create_academy',{p_name:`Second Academy ${suffix.slice(0,8)}`,p_city:'Yaoundé',p_country:'CM',p_timezone:'Africa/Douala',p_language:'FR',p_owner_email:ownerEmail,p_invitation_expires_at:date(7)});
 const secondInvite=parseInvitationFragment(new URL(await provision(second.invitation_id)).hash);
 const secondAuth=await auth.verifyEmailToken(secondInvite.tokenHash,secondInvite.type);await auth.acceptInvitation(secondAuth.access_token,secondInvite,'Web Owner','FR',randomUUID());
 await academyPage.getByRole('button',{name:'Actualiser les accès'}).click();await navigate(academyPage,'Joueurs');
 let release,started,finish;const requestStarted=new Promise(r=>{started=r;}),requestFinished=new Promise(r=>{finish=r;});let delayed=false;
 await academyPage.route('**/rest/v1/rpc/list_players',async route=>{
  if(!delayed&&route.request().postDataJSON().p_academy===academy.academy_id){delayed=true;const response=await route.fetch();started();await new Promise(r=>{release=r;});await route.fulfill({response});finish();}else await route.continue();
 });
 await academyPage.getByRole('button',{name:'Actualiser',exact:true}).click();await requestStarted;
 await academyPage.getByLabel('Académie active').selectOption(second.academy_id);await navigate(academyPage,'Joueurs');
 await expect(academyPage.getByRole('heading',{name:'Aucun élément à afficher'})).toBeVisible();release();await requestFinished;await academyPage.evaluate(()=>new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r))));
 await expect(academyPage.locator('tbody')).toHaveCount(0);await academyPage.unroute('**/rest/v1/rpc/list_players');
 await create(academyPage,'Joueurs','Ajouter un joueur','create_player',{p_first_name:'Isolated',p_last_name:'Tenant B'});
 await academyPage.getByLabel('Académie active').selectOption(academy.academy_id);await navigate(academyPage,'Joueurs');
 await expect(academyPage.locator('tbody')).toContainText('Lina');await expect(academyPage.locator('tbody')).not.toContainText('Isolated');
 console.log('PASS: tenant switch clears records and ignores late responses from the previous academy');
 // Coach permissions and a forged finance route must not expose owner data.
 const coachContext=await browser.newContext();const coachPage=await coachContext.newPage();
 await login(coachPage,academyOrigin,coachEmail);await expect(coachPage.getByRole('navigation')).not.toContainText('Encaissements');
 await coachPage.goto(`${academyOrigin}/?page=payments`);await expect(coachPage.getByRole('heading',{name:'Espace indisponible'})).toBeVisible();
 // Revoke this synthetic coach via the owner RPC and require refreshed access.
 await post('/rest/v1/rpc/suspend_membership',{p_academy:academy.academy_id,p_membership:coachMember.id,p_reason:'Local revocation test',p_operation_key:randomUUID()},ownerSession.access_token);
 await coachPage.getByRole('button',{name:'Actualiser les accès'}).click();await expect(coachPage.getByRole('heading',{name:'Aucune académie accessible'})).toBeVisible();
 await coachContext.close();
 await academyPage.setViewportSize({width:390,height:844});await academyPage.goto(`${academyOrigin}/`);await expect(academyPage.getByRole('heading',{level:1})).toBeVisible();
 assert.equal(await academyPage.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true,'mobile page should not overflow');
 await academyPage.screenshot({path:join(temp,'academy-mobile.png'),fullPage:true});
 await academyPage.setViewportSize({width:1440,height:1000});await navigate(academyPage,'Réservations et présences');await expect(academyPage.locator('tbody')).toContainText('Terminé');await academyPage.screenshot({path:join(temp,'academy-bookings.png'),fullPage:true});
 await platform.screenshot({path:join(temp,'platform-academies.png'),fullPage:true});
 assert.deepEqual(browserErrors,[]);
 console.log('PASS: coach restrictions, forged route, live revocation, mobile layout and no browser exceptions');
 writeFileSync(join(temp,'local-accounts.json'),JSON.stringify({platform:{url:platformOrigin,email:rootEmail,password},academy:{url:academyOrigin,email:ownerEmail,password}},null,2),{mode:0o600});
 console.log(`Screenshots, synthetic local accounts and local logs: ${temp}`);
 console.log('Synthetic data remains in the disposable local stack; no remote writes or external email.');
}catch(error){
 console.error(String(error.stack??error).replace(/#(?:[^\s]*)/g,'#[REDACTED]'));process.exitCode=1;
}finally{await browser?.close();for(const child of children)child.kill('SIGTERM');closeSync(log);}
