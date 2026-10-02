// Smoke the compiled Flutter app; fixture credentials are local and never logged.
import {createServer} from 'node:http';
import {readFileSync,existsSync} from 'node:fs';
import {resolve,join,extname} from 'node:path';
import {chromium,expect} from '@playwright/test';
import assert from 'node:assert/strict';
const temp=process.env.SPORTA_FLUTTER_ARTIFACTS;
if(!temp)throw Error('SPORTA_FLUTTER_ARTIFACTS_REQUIRED');
const config=JSON.parse(readFileSync(join(temp,'test-config.json'),'utf8'));
assert.equal(config.SUPABASE_URL,'http://127.0.0.1:54321');
const root=resolve('apps/student/build/web');
const server=createServer((req,res)=>{
 const pathname=new URL(req.url,'http://localhost').pathname;
 const file=resolve(root,'.'+decodeURIComponent(pathname==='/'?'/index.html':pathname));
 if(!file.startsWith(root+'/')&&file!==root){res.writeHead(403).end();return;}
 const target=file===root?join(root,'index.html'):file;
 if(!existsSync(target)){res.writeHead(404).end();return;}
 const type={'.html':'text/html','.js':'text/javascript','.json':'application/json','.wasm':'application/wasm','.png':'image/png','.css':'text/css'}[extname(target)]??'application/octet-stream';
 res.writeHead(200,{'Content-Type':type,'Cache-Control':'no-store'});res.end(readFileSync(target));
});
await new Promise(r=>server.listen(5175,'127.0.0.1',r));
const browser=await chromium.launch({channel:'chromium',headless:true});
try{
 const page=await browser.newPage({viewport:{width:390,height:844}}),errors=[];
 page.on('pageerror',e=>errors.push(e.message));
 await page.goto('http://127.0.0.1:5175');
 await page.locator('flt-semantics-placeholder').evaluate(el=>el.click());
 await page.getByRole('textbox',{name:'Adresse email'}).fill(config.TEST_PARENT_EMAIL);
 await page.getByRole('textbox',{name:'Mot de passe',exact:true}).fill(config.TEST_PASSWORD);
 await page.getByRole('button',{name:'Se connecter',exact:true}).click();
 // Flutter semantics expose body text as node text, not aria-label.
 await expect(page.getByText('Bienvenue sur le terrain.')).toBeVisible();
 await page.screenshot({path:join(temp,'flutter-home.png')});
 await page.getByRole('tab',{name:'Joueurs',exact:true}).click();
 // Merged card semantics carry the player name as the group's accessible name.
 await expect(page.getByRole('group',{name:/Lina Mobile/})).toBeVisible();
 assert.ok(!(await page.locator('body').ariaSnapshot()).includes('Private Unlinked'));
 await page.screenshot({path:join(temp,'flutter-players.png')});
 assert.deepEqual(errors,[]);
 console.log('PASS: compiled Flutter Chromium login and family profile at 390px; no browser exception');
}finally{await browser.close();await new Promise(r=>server.close(r));}
