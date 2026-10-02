// Explicit staging-only transaction tests. Refuse production and any populated
// staging; each SQL suite rolls back its fixtures and scheduler HTTP queue.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {readFileSync,readdirSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
const ref='ordjngzihkmknnizlujp';
assert.equal(process.argv[2],ref,'Pass the exact authorized staging reference');
const dir=resolve('supabase/.temp/staging-deploy');
assert.equal(JSON.parse(readFileSync(dir+'/created-project.json','utf8')).id,ref);
const url=new URL(readFileSync(dir+'/workspace/supabase/.temp/pooler-url','utf8').trim());
assert.equal(url.username,`postgres.${ref}`);assert.equal(url.hostname,'aws-1-eu-west-3.pooler.supabase.com');assert.equal(url.port,'5432');
const password=readFileSync(dir+'/database-password','utf8');
const env={PATH:process.env.PATH,PGHOST:url.hostname,PGPORT:url.port,PGUSER:url.username,PGDATABASE:'postgres',PGPASSWORD:password,PGSSLMODE:'require',PGCONNECT_TIMEOUT:'20',PGPASSFILE:'/dev/null',PGSERVICEFILE:'/dev/null'};
function query(args,input){
 const r=spawnSync('/usr/local/opt/postgresql@17/bin/psql',['-X','-At','-v','ON_ERROR_STOP=1',...args],{encoding:'utf8',env,input});
 if(r.status!==0){writeFileSync(dir+'/sql-error.log',(r.stdout+r.stderr).replaceAll(password,'[redacted]'),{mode:0o600});throw Error('STAGING_SQL_FAILED: diagnostic in ignored sql-error.log');}return r.stdout;
}
assert.equal(query([],"SELECT (SELECT count(*) FROM public.academies)+(SELECT count(*) FROM auth.users);\n").trim(),'0','Staging must contain no user data before fixture tests');
assert.equal(query([],"SELECT count(*) FROM ops.worker_schedule WHERE enabled;\n").trim(),'0');
let total=0;
for(const file of readdirSync('supabase/tests/database').filter(f=>/^\d.*\.sql$/.test(f)).sort()){
 const out=query(['-f',resolve('supabase/tests/database',file)]);
 writeFileSync(dir+'/'+file+'.tap',out,{mode:0o600});
 assert.ok(!/^not ok/m.test(out),file);
 const passed=(out.match(/^ok \d+ -/gm)??[]).length,plan=Number(out.match(/^1\.\.(\d+)$/m)?.[1]);
 assert.ok(passed>0);assert.equal(passed,plan,file);total+=passed;console.log(`PASS ${file}: ${passed}`);
}
assert.equal(query([],"SELECT (SELECT count(*) FROM public.academies)+(SELECT count(*) FROM auth.users);\n").trim(),'0','Fixture data rolled back');
assert.equal(query([],"SELECT count(*) FROM cron.job WHERE jobname='sporta-workers';\n").trim(),'0');
console.log(`PASS: ${total} SQL assertions on actual staging; no user fixture or cron retained.`);
