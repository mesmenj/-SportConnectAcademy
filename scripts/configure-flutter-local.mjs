// Emit PUBLIC local configuration only. Never persist the CLI service key.
import {spawnSync} from 'node:child_process';
import {writeFileSync} from 'node:fs';
const result=spawnSync('supabase',['status','-o','json'],{encoding:'utf8'});
if(result.status!==0)throw Error('LOCAL_SUPABASE_REQUIRED');
const local=JSON.parse(result.stdout);
if(local.API_URL!=='http://127.0.0.1:54321')throw Error('LOCAL_SUPABASE_REQUIRED');
const android=process.argv.includes('--android');
const file=`apps/student/config.local${android?'.android':''}.json`;
writeFileSync(file,JSON.stringify({SUPABASE_URL:android?'http://10.0.2.2:54321':local.API_URL,SUPABASE_ANON_KEY:local.ANON_KEY,AUTH_RECOVERY_URL:'http://localhost:5173/auth/recovery'},null,2)+'\n',{mode:0o600});
console.log(`Configuration publique locale créée : ${file}`);
