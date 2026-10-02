// Phase 6 staging preflight. Offline and read-only: no network, no Supabase CLI
// remote command, no secret printed. Exit 1 on any failure.
//   node scripts/staging-preflight.mjs                       repository checks
//   node scripts/staging-preflight.mjs --project-ref <ref> --env <file>
import {readFileSync,readdirSync,existsSync,statSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {join,extname} from 'node:path';

const args=process.argv.slice(2),opt=name=>{const i=args.indexOf(name);return i<0?undefined:args[i+1];};
const ref=opt('--project-ref'),envFile=opt('--env'),configFile=opt('--config')??'supabase/config.toml';
const backendOnly=args.includes('--backend-only');
const productionRef='phjzyohsscwrgwvhgvfh';
if((ref===undefined)!==(envFile===undefined))throw Error('Use --project-ref and --env together');
const failures=[],notes=[];
const check=(ok,label)=>{(ok?notes:failures).push(label);return ok;};

// Minimal TOML reader for supabase/config.toml: sections, strings, booleans,
// numbers and single-line string arrays. Anything else fails loudly.
function readToml(text){
 const out={};let section=out;
 for(const [n,raw] of text.split('\n').entries()){
  const line=raw.replace(/\s+#.*$/,'').trim();if(!line||line.startsWith('#'))continue;
  const head=line.match(/^\[([A-Za-z0-9_.-]+)\]$/);
  if(head){section=head[1].split('.').reduce((o,k)=>o[k]??={},out);continue;}
  const kv=line.match(/^([A-Za-z0-9_]+)\s*=\s*(.+)$/);if(!kv)throw Error(`config.toml:${n+1} unsupported syntax`);
  section[kv[1]]=JSON.parse(kv[2]);
 }
 return out;
}
const config=readToml(readFileSync(configFile,'utf8'));

// 1. Edge functions: deploy exactly the directories that have an entry point.
const functionsDir='supabase/functions';
const dirs=readdirSync(functionsDir).filter(d=>!d.startsWith('.')&&!['_shared','node_modules','tests'].includes(d)&&statSync(join(functionsDir,d)).isDirectory());
const deployable=dirs.filter(d=>existsSync(join(functionsDir,d,'index.ts'))).sort();
const configured=Object.keys(config.functions??{}).sort();
check(JSON.stringify(deployable)===JSON.stringify(configured),`Edge: ${deployable.length} entry points match config.toml [functions.*]`);
check(deployable.length===8,'Edge: exactly the 8 functions validated in 3D');
check(configured.every(f=>config.functions[f].verify_jwt===false),'Edge: verify_jwt=false everywhere (handlers authenticate)');
check(existsSync(join(functionsDir,'secure-asset-upload/deno.json')),'Edge: image uploader has its own deployable Deno dependency configuration');
const empty=dirs.filter(d=>!deployable.includes(d));
if(empty.length)notes.push(`Edge: ${empty.length} empty legacy directories are NOT deployed (${empty.join(', ')})`);

// 2. Migrations: ordered, unique, and free of the local auth.users test stub.
const migrations=readdirSync('supabase/migrations').filter(f=>f.endsWith('.sql')).sort();
check(migrations.every(f=>/^\d{14}_[a-z0-9_]+\.sql$/.test(f)),'Migrations: timestamped names');
check(new Set(migrations.map(f=>f.slice(0,14))).size===migrations.length,'Migrations: unique versions');
check(migrations.every(f=>!/create\s+(table|schema)\s+(if\s+not\s+exists\s+)?auth\b/i.test(readFileSync(join('supabase/migrations',f),'utf8'))),'Migrations: no auth schema/table creation (test stub stays local)');
notes.push(`Migrations: ${migrations.length} to apply`);

// 3. Auth and seed settings that config push would carry to the remote.
check(config.auth?.enable_signup===false,'Auth: public signup disabled');
check(config.db?.seed?.enabled===false,'DB: seed disabled');
// pg_net tables are PUBLIC-granted by supabase_admin: the API must never expose them.
check(JSON.stringify(config.api?.schemas)==='["public"]','API: only the public schema is exposed (never net, vault, cron or private)');

// 4. No secret in any file that could be committed (root and submodules).
const repos=['.',...(readFileSync('.gitmodules','utf8').match(/path = (.+)/g)??[]).map(l=>l.slice(7).trim())];
const textExt=new Set(['','.js','.mjs','.ts','.tsx','.dart','.json','.toml','.sql','.md','.yaml','.yml','.sh','.html','.env','.example','.txt','.xml','.gradle','.plist']);
const leaks=[];
for(const repo of repos){
 const r=spawnSync('git',['-C',repo,'ls-files','--cached','--others','--exclude-standard','-z'],{encoding:'utf8'});
 if(r.status!==0){failures.push(`Secrets: cannot list files in ${repo}`);continue;}
 for(const rel of r.stdout.split('\0').filter(Boolean)){
  const file=join(repo,rel);
  if(/node_modules|\/build\/|\/dist\//.test(file)||!textExt.has(extname(file))||!existsSync(file)||!statSync(file).isFile()||statSync(file).size>2e6)continue;
  const text=readFileSync(file,'utf8');
  for(const jwt of text.match(/eyJ[\w-]+\.eyJ[\w-]+\.[\w-]+/g)??[]){
   try{const p=JSON.parse(Buffer.from(jwt.split('.')[1],'base64url'));if(p.role==='service_role'&&p.iss!=='supabase-demo')leaks.push(`${file} (service_role JWT)`);}catch{/* not a JWT */}
  }
  if(/sb_secret_[\w-]{20,}/.test(text))leaks.push(`${file} (sb_secret_ key)`);
  if(/xkeysib-[a-f0-9]{20,}/.test(text))leaks.push(`${file} (Brevo API key)`);
  if(/\.env/.test(rel)&&/^(WORKER_SECRET|BREVO_WEBHOOK_SECRET|INVITATION_TOKEN_SECRET|BREVO_API_KEY)=\S+/m.test(text))leaks.push(`${file} (populated env file)`);
 }
}
check(leaks.length===0,`Secrets: none in committable files${leaks.length?` — ${leaks.join('; ')}`:''}`);

// 5. Staging environment for Edge functions and the matching remote config.
if(envFile){
 const localId=config.project_id;
 check(/^[a-z]{20}$/.test(ref)&&ref!==localId&&ref!==productionRef,'Target: a hosted staging ref, neither local nor protected production');
 const env=Object.fromEntries(readFileSync(envFile,'utf8').split('\n').map(l=>l.trim()).filter(l=>l&&!l.startsWith('#')).map(l=>{const i=l.indexOf('=');return [l.slice(0,i),l.slice(i+1)];}));
 const url=v=>{try{return new URL(v);}catch{return null;}};
 const legacy=/challengeme|classcard|firebase/i;
 check(!Object.keys(env).some(k=>k.startsWith('SUPABASE_')),'Env: no SUPABASE_* key (injected by the platform)');
 check(env.PUBLIC_SUPABASE_URL===`https://${ref}.supabase.co`,'Env: PUBLIC_SUPABASE_URL is the target project over HTTPS');
 const origins=(env.ALLOWED_ORIGINS??'').split(',').map(x=>x.trim()).filter(Boolean);
 if(!backendOnly) check(origins.length>0&&origins.every(o=>{const u=url(o);return u&&u.protocol==='https:'&&u.origin===o&&!['localhost','127.0.0.1'].includes(u.hostname);}),'Env: ALLOWED_ORIGINS are exact HTTPS origins, no localhost or wildcard');
 const callback=url(env.INVITATION_CALLBACK_URL);
 if(!backendOnly) check(Boolean(callback&&callback.protocol==='https:'&&origins.includes(callback.origin)&&callback.pathname==='/auth/invitation'),'Env: INVITATION_CALLBACK_URL is <allowed origin>/auth/invitation');
 check(![env.PUBLIC_SUPABASE_URL,env.INVITATION_CALLBACK_URL,...origins].some(v=>legacy.test(v??'')),'Env: no ChallengeMe/Firebase host');
 const secrets=['WORKER_SECRET','BREVO_WEBHOOK_SECRET','INVITATION_TOKEN_SECRET'].map(k=>env[k]??'');
 check(secrets.every(s=>s.length>=32),'Env: three secrets of at least 32 characters');
 check(new Set(secrets).size===3,'Env: the three secrets are independent');
 const localEnv=existsSync('supabase/functions/.env')?readFileSync('supabase/functions/.env','utf8'):'';
 check(secrets.every(s=>!localEnv.includes(s)),'Env: no secret reused from the local stack');
 const ttl=Number(env.ASSET_URL_TTL_SECONDS);check(Number.isInteger(ttl)&&ttl>=30&&ttl<=300,'Env: ASSET_URL_TTL_SECONDS within 30..300');
 const brevo=[env.BREVO_API_KEY,env.BREVO_SENDER_EMAIL].filter(Boolean).length;
 if(backendOnly){
  check(origins.length===0&&!env.INVITATION_CALLBACK_URL,'Backend only: no frontend origin or invitation callback');
  check(brevo===0,'Backend only: external email disabled');
  notes.push('Backend only: workers installed disabled; activation needs frontend/email and a retention decision');
 }
 check(brevo!==1,'Env: BREVO_API_KEY and BREVO_SENDER_EMAIL set together or both empty');
 notes.push(brevo?'Email: Brevo delivery ENABLED on staging':'Email: Brevo disabled; invitations need the operator link tool');

 const remote=config.remotes?.staging;
 if(check(remote?.project_id===ref,'Config: [remotes.staging] targets this project ref')){
  const auth=remote.auth??{},site=url(auth.site_url);
  if(!backendOnly) check(Boolean(site&&site.protocol==='https:'&&origins.includes(site.origin)),'Config: staging auth.site_url is an allowed HTTPS origin');
  const redirects=auth.additional_redirect_urls??[];
  if(!backendOnly) check(redirects.length>0&&redirects.every(r=>{const u=url(r);return u&&u.protocol==='https:'&&origins.includes(u.origin);}),'Config: staging redirect URLs are HTTPS on allowed origins');
  if(!backendOnly) check(redirects.includes(env.INVITATION_CALLBACK_URL),'Config: invitation callback is an allowed redirect');
  else {
   check(auth.site_url===`https://${ref}.supabase.co`,'Backend only: neutral Auth site URL is the staging API origin');
   check(redirects.length===0,'Backend only: no Auth redirect URLs before frontend setup');
  }
  check(auth.enable_signup!==true,'Config: staging does not re-enable public signup');
  check(remote.db?.seed?.enabled!==true,'Config: staging does not enable seed');
  check(remote.api?.schemas===undefined||JSON.stringify(remote.api.schemas)==='["public"]','Config: staging exposes only the public schema');
 }
}

for(const n of notes)console.log(`ok   ${n}`);
for(const f of failures)console.log(`FAIL ${f}`);
console.log(failures.length?`STAGING PREFLIGHT FAILED (${failures.length})`:`STAGING PREFLIGHT PASSED${envFile?'':' (repository only; pass --project-ref and --env for the target)'}`);
process.exit(failures.length?1:0);
