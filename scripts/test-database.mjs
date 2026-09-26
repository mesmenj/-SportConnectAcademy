import { spawn, spawnSync } from 'node:child_process'
import { mkdtempSync, readdirSync, readFileSync, existsSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join, resolve } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

// Always creates a new disposable cluster; accepts no URL, host or database.
// No existing database, Supabase project or Firebase resource is contacted.
const root = fileURLToPath(new URL('../', import.meta.url))
const homebrew = '/usr/local/opt/postgresql@17/bin'
const bin = process.env.SPORTA_PG_BIN ?? (existsSync(homebrew) ? homebrew : '')
const executable = name => bin ? join(bin, name) : name
const version = spawnSync(executable('postgres'), ['--version'], { encoding: 'utf8' })
if (version.status !== 0) {
  console.error('LOCAL_RUNTIME_NOT_AVAILABLE: PostgreSQL required; set SPORTA_PG_BIN to its bin directory.')
  process.exit(1)
}
const work = mkdtempSync(join(tmpdir(), 'sporta-db-test-'))
const data = join(work, 'data')
let started = false
let assertions = 0
// Do not inherit connection variables or user's psqlrc/service/password.
const env = { PATH: process.env.PATH, LC_ALL: 'C', HOME: work, PGSERVICEFILE: join(work, 'no-service'), PGPASSFILE: join(work, 'no-password') }
function run(name, args, input) {
  const result = spawnSync(executable(name), args, { encoding: 'utf8', input, cwd: root, env, maxBuffer: 8 * 1024 * 1024 })
  if (result.status !== 0) throw new Error(`${name} failed:\n${result.stderr ?? ''}\n${result.stdout ?? ''}`)
  return result.stdout
}
const psql = ['-X', '-v', 'ON_ERROR_STOP=1', '-h', work, '-p', '54329', '-U', 'postgres', '-d', 'postgres']
const conc = [...psql.slice(0, -1), 'conc']
const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`
const sleep = ms => new Promise(done => setTimeout(done, ms))

// A psql session kept open; PGAPPNAME lets pg_stat_activity observe it.
// Every session is killed on exit so a failed scenario cannot hang the runner.
const children = []
function session(name, sql) {
  const child = spawn(executable('psql'), [...conc, '-At'], { cwd: root, env: { ...env, PGAPPNAME: name } })
  children.push(child)
  const state = { out: '', exited: false }
  child.stdout.on('data', d => { state.out += d })
  child.stderr.on('data', d => { state.out += d })
  state.done = new Promise(done => child.on('close', code => { state.exited = true; state.code = code; done(state) }))
  if (sql !== undefined) child.stdin.end(sql)
  state.child = child
  return state
}
const waiting = name => run('psql', [...conc, '-At', '-c',
  `SELECT coalesce(wait_event_type, '') || ':' || coalesce(wait_event, '') FROM pg_stat_activity WHERE application_name = '${name}'`]).trim()
async function until(predicate, label, ms = 10000) {
  for (const start = Date.now(); Date.now() - start < ms; await sleep(20)) if (predicate()) return
  throw new Error(`Concurrency timeout: ${label}`)
}
const as = (user, call, role = 'authenticated') => `SELECT set_config('request.jwt.claim.sub', '${id(user)}', true);\nSET LOCAL ROLE ${role};\nSELECT public.${call};\nRESET ROLE;\n`

// Each scenario: A commands then waits at the gate holding its locks; B must be
// observed blocked on a lock; the gate opens; final state is checked.
async function concurrency() {
  run('psql', [...psql, '-c', 'CREATE DATABASE conc TEMPLATE postgres'])
  run('psql', [...conc, '-f', resolve(root, 'supabase/tests/concurrency/setup.sql')])
  const vars = Object.fromEntries(run('psql', [...conc, '-At', '-F', ' ', '-c', 'SELECT k, v FROM conc.vars']).trim().split('\n').map(l => l.split(' ')))
  const { scenarios } = await import(pathToFileURL(resolve(root, 'supabase/tests/concurrency/scenarios.mjs')).href)
  const gate = session('conc-gate')
  gate.child.stdin.write('SELECT pg_advisory_lock(777001);\n')
  await until(() => run('psql', [...conc, '-At', '-c', 'SELECT count(*) FROM pg_locks WHERE locktype = \'advisory\' AND objid = 777001 AND granted']).trim() === '1', 'gate lock')
  let count = 0
  for (const s of scenarios(vars, id)) {
    const a = session('conc-a', `BEGIN;\n${as(...s.a)}SELECT pg_advisory_xact_lock_shared(777001);\nCOMMIT;\n`)
    await until(() => a.exited || waiting('conc-a') === 'Lock:advisory', `${s.name}: A at gate`)
    if (a.exited) throw new Error(`${s.name}: A failed before the gate\n${a.out}`)
    const b = session('conc-b', `BEGIN;\n${as(...s.b)}COMMIT;\n`)
    await until(() => b.exited || waiting('conc-b').startsWith('Lock:'), `${s.name}: B blocked`)
    const blocked = !b.exited
    gate.child.stdin.write('SELECT pg_advisory_unlock(777001);\nSELECT pg_advisory_lock(777001);\n')
    await Promise.all([a.done, b.done])
    await until(() => run('psql', [...conc, '-At', '-c', 'SELECT count(*) FROM pg_locks l JOIN pg_stat_activity p ON p.pid = l.pid WHERE l.locktype = \'advisory\' AND l.objid = 777001 AND l.granted AND p.application_name = \'conc-gate\'']).trim() === '1', 'gate relocked')
    const ok = run('psql', [...conc, '-At', '-c', s.check]).trim() === 't'
    const label = `concurrency: ${s.name}`
    if (a.code !== 0) throw new Error(`FAIL: ${label}: A failed\n${a.out}`)
    if (!blocked) throw new Error(`FAIL: ${label}: B was never blocked by A\n${b.out}`)
    if (!b.out.includes(s.expect)) throw new Error(`FAIL: ${label}: B output lacks ${s.expect}\n${b.out}`)
    if (!ok) throw new Error(`FAIL: ${label}: final state check failed`)
    console.log(`ok ${++count} - ${label} [B waited, then ${s.expect}]`)
  }
  gate.child.stdin.end()
  await gate.done
  console.log(`1..${count}`)
  return count
}
try {
  run('initdb', ['-D', data, '-U', 'postgres', '--auth-local=trust', '--auth-host=reject', '--no-locale', '--encoding=UTF8'])
  run('pg_ctl', ['-D', data, '-l', join(work, 'postgres.log'), '-o', `-k ${work} -p 54329 -c listen_addresses=''`, '-w', 'start'])
  started = true
  run('psql', psql, readFileSync(join(root, 'supabase/local/auth-test-bootstrap.sql'), 'utf8'))
  for (const migration of readdirSync(join(root, 'supabase/migrations')).filter(n => n.endsWith('.sql')).sort()) {
    run('psql', [...psql, '-1', '-f', resolve(root, 'supabase/migrations', migration)])
    console.log(`APPLIED ${migration}`)
  }
  const tests = readdirSync(join(root, 'supabase/tests/database')).filter(n => n.endsWith('.sql')).sort()
  if (tests.length === 0) throw new Error('No SQL test files found')
  for (const test of tests) {
    const output = run('psql', [...psql, '-f', resolve(root, 'supabase/tests/database', test)])
    const count = (output.match(/^ok [0-9]+ -/gm) ?? []).length
    const plan = output.match(/^1\.\.([0-9]+)$/m)
    if (count === 0 || !plan || Number(plan[1]) !== count) throw new Error(`Invalid TAP plan in ${test}`)
    console.log(output.split('\n').filter(line => line.trim()).join('\n'))
    assertions += count
  }
  const races = await concurrency()
  console.log(`PASS: ${assertions} SQL assertions and ${races} two-connection concurrency scenarios; ${version.stdout.trim()}.`)
  console.log('This is PostgreSQL foundation validation with an auth.users stub, not a Supabase Auth/API/Storage integration test.')
} catch (error) {
  console.error(error.message)
  process.exitCode = 1
} finally {
  for (const child of children) if (child.exitCode === null) child.kill('SIGKILL')
  if (started) {
    try { run('pg_ctl', ['-D', data, '-m', 'fast', '-w', 'stop']) }
    catch (error) { console.error(error.message); process.exitCode = 1 }
  }
  console.log(`Local test artifacts retained at ${work}`)
}
