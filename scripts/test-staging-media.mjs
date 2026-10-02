// Staging only: creates one disposable Auth identity (no profile/membership),
// exercises hosted decoders, then deletes that exact identity in finally.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import {randomUUID,randomBytes} from 'node:crypto';
import {createRequire} from 'node:module';
const ref='ordjngzihkmknnizlujp',base=`https://${ref}.supabase.co`;
assert.equal(process.argv[2],ref);assert.equal(JSON.parse(readFileSync('supabase/.temp/staging-deploy/created-project.json','utf8')).id,ref);
const r=spawnSync('supabase',['projects','api-keys','--project-ref',ref,'--output','json'],{encoding:'utf8'});assert.equal(r.status,0);
const keys=JSON.parse(r.stdout),anon=keys.find(k=>k.name==='anon')?.api_key,service=keys.find(k=>k.name==='service_role')?.api_key;assert.ok(anon&&service);
const headers=token=>({apikey:anon,Authorization:`Bearer ${token}`,'Content-Type':'application/json'});
const request=(path,options)=>fetch(base+path,{...options,signal:AbortSignal.timeout(45000),redirect:'error'});
const email=`staging-media-${randomUUID()}@example.test`,password=randomBytes(32).toString('hex');
const created=await request('/auth/v1/admin/users',{method:'POST',headers:headers(service),body:JSON.stringify({email,password,email_confirm:true})});assert.equal(created.status,200);
const user=await created.json();assert.equal(user.email,email);assert.match(user.id,/^[a-f0-9-]{36}$/);
try{
 const login=await request('/auth/v1/token?grant_type=password',{method:'POST',headers:headers(anon),body:JSON.stringify({email,password})});assert.equal(login.status,200);const session=await login.json();
 const refresh=await request('/auth/v1/token?grant_type=refresh_token',{method:'POST',headers:headers(anon),body:JSON.stringify({refresh_token:session.refresh_token})});assert.equal(refresh.status,200);const current=await refresh.json();assert.equal(current.user.id,user.id);
 const require=createRequire(new URL('../supabase/functions/package.json',import.meta.url));const {PNG}=require('pngjs'),jpeg=require('jpeg-js');
 const image={width:2,height:2,data:Buffer.alloc(16,255)};
 const {default:encode,init}=await import('../supabase/functions/node_modules/@jsquash/webp/encode.js');
 await init(await WebAssembly.compile(readFileSync(new URL('../supabase/functions/node_modules/@jsquash/webp/codec/enc/webp_enc.wasm',import.meta.url))));
 const webp=await encode({...image,data:new Uint8ClampedArray(image.data)},{lossless:1});
 for(const [mime,body,expected] of [['image/png',PNG.sync.write(image),403],['image/jpeg',jpeg.encode(image,80).data,403],['image/webp',webp,403],['image/png',Buffer.from('corrupt'),400]]){
  const res=await request('/functions/v1/secure-asset-upload',{method:'POST',headers:{...headers(current.access_token),'Content-Type':mime,'x-academy-id':randomUUID(),'x-asset-usage':'BRANDING','x-operation-key':randomUUID()},body});
  const result=await res.json();assert.equal(res.status,expected,`${mime} expected ${expected}, got ${res.status}: ${result.error}`);
 }
 console.log('PASS: hosted Auth login/refresh, PNG/JPEG/WebP decoding including WASM, corrupt image refusal, actor without membership denied before any asset write');
}finally{
 const deleted=await request(`/auth/v1/admin/users/${user.id}`,{method:'DELETE',headers:headers(service)});assert.equal(deleted.status,200,'Disposable Auth fixture cleanup');
 console.log('PASS: disposable Auth account removed; no email or business data created');
}
