import { spawn } from 'node:child_process'
import { existsSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const env = { ...process.env }
const androidJava = '/Applications/Android Studio.app/Contents/jbr/Contents/Home'
if (!env.JAVA_HOME && process.platform === 'darwin' && existsSync(path.join(androidJava, 'bin/java'))) env.JAVA_HOME = androidJava
if (env.JAVA_HOME) env.PATH = path.join(env.JAVA_HOME, 'bin') + path.delimiter + (env.PATH || '')
const args = process.argv[2] === 'test'
  ? ['emulators:exec', '--project', 'demo-sporta', '--only', 'auth,firestore,functions', 'node --test functions/lib/integration.test.js']
  : ['emulators:start', '--project', 'demo-sporta', '--only', 'auth,firestore,functions']
const child = spawn(process.execPath, [path.join(root, 'node_modules/firebase-tools/lib/bin/firebase.js'), ...args], { cwd: root, env, stdio: 'inherit' })
child.on('error', error => { console.error(error.message); process.exitCode = 1 })
child.on('exit', code => { process.exitCode = code ?? 1 })
