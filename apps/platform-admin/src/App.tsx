import MembersPanel from './MembersPanel'
import { useEffect, useState, type FormEvent } from 'react'
import { onAuthStateChanged, signInWithEmailAndPassword, signOut } from 'firebase/auth'
import { collection, doc, onSnapshot, query, orderBy, limit, type DocumentData } from 'firebase/firestore'
import { httpsCallable } from 'firebase/functions'
import { auth, db, functions } from './firebase'
import './style.css'
type Row = DocumentData & { id: string }
type Page = 'overview' | 'academies' | 'plans' | 'audit'
const labels: Record<Page, string> = { overview: 'Vue d’ensemble', academies: 'Académies', plans: 'Forfaits', audit: 'Journal d’audit' }
const date = (value: { toDate?: () => Date } | undefined) => value?.toDate?.().toLocaleDateString('fr-FR') ?? '—'
export default function App() {
  const [access, setAccess] = useState<'loading' | 'login' | 'denied' | 'ready'>('loading')
  const [membersAcademy, setMembersAcademy] = useState('')
  const [page, setPage] = useState<Page>('overview')
  const [academies, setAcademies] = useState<Row[]>([])
  const [plans, setPlans] = useState<Row[]>([])
  const [subscriptions, setSubscriptions] = useState<Row[]>([])
  const [logs, setLogs] = useState<Row[]>([])
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')
  const [busy, setBusy] = useState(false)
  const [now, setNow] = useState(() => Date.now())
  useEffect(() => { const timer = window.setInterval(() => setNow(Date.now()), 30000); return () => window.clearInterval(timer) }, [])
  useEffect(() => {
    let stopProfile = () => {}
    const stop = onAuthStateChanged(auth, user => {
      stopProfile(); setAcademies([]); setPlans([]); setSubscriptions([]); setLogs([])
      if (!user) { setAccess('login'); return }
      setAccess('loading')
      stopProfile = onSnapshot(doc(db, 'platformOperators', user.uid), snap => setAccess(snap.get('status') === 'active' ? 'ready' : 'denied'), () => setAccess('denied'))
    })
    return () => { stop(); stopProfile() }
  }, [])
  useEffect(() => {
    if (access !== 'ready') return
    const read = (name: string, save: (rows: Row[]) => void) => onSnapshot(name === 'platformAuditLogs' ? query(collection(db, name), orderBy('createdAt', 'desc'), limit(50)) : collection(db, name), snap => save(snap.docs.map(d => ({ ...d.data(), id: d.id }))), () => setError('Impossible de charger les données. Vérifiez les émulateurs et vos droits.'))
    const stops = [read('academies', setAcademies), read('plans', setPlans), read('academySubscriptions', setSubscriptions), read('platformAuditLogs', setLogs)]
    return () => stops.forEach(stop => stop())
  }, [access])
  async function action(name: string, data: object) {
    setBusy(true); setError(''); setMessage('')
    try { await httpsCallable(functions, name)({ ...data, requestId: crypto.randomUUID() }); setMessage('Modification enregistrée.'); return true }
    catch (reason) { setError(reason instanceof Error ? reason.message : 'Une erreur est survenue.'); return false }
    finally { setBusy(false) }
  }
  const submit = (name: string, transform: (data: FormData) => object) => async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault(); const form = event.currentTarget
    if (await action(name, transform(new FormData(form)))) form.reset()
  }
  const subscription = (academyId: string) => subscriptions.find(row => row.id === academyId)
  const active = subscriptions.filter(row => row.status === 'active' && row.endsAt?.toMillis() > now)
  if (access === 'loading') return <main className="login"><h1>SportA</h1><p>Chargement de votre espace…</p></main>
  if (access !== 'ready') return <main className="login"><div className="brand">S<span>SportA</span></div><h1>Le sport, à votre échelle.</h1><p>Connectez-vous au back-office de la plateforme.</p>{access === 'denied' ? <><p role="alert">Ce compte ne possède pas l’accès opérateur SportA.</p><button onClick={() => void signOut(auth)}>Changer de compte</button></> : <form onSubmit={async event => { event.preventDefault(); const data = new FormData(event.currentTarget); setBusy(true); setError(''); try { await signInWithEmailAndPassword(auth, String(data.get('email')), String(data.get('password'))) } catch { setError('Connexion impossible. Vérifiez vos identifiants et le service d’authentification.') } finally { setBusy(false) } }}><label>Email<input name="email" type="email" required autoComplete="username" /></label><label>Mot de passe<input name="password" type="password" required autoComplete="current-password" /></label><button disabled={busy}>Se connecter</button></form>}{error && <p role="alert">{error}</p>}</main>
  return <div className="shell"><aside><div className="brand">S<span>SportA<small>PLATEFORME</small></span></div><nav>{(Object.keys(labels) as Page[]).map(key => <button key={key} className={page === key ? 'selected' : ''} onClick={() => setPage(key)}>{labels[key]}</button>)}</nav><div className="account"><p>{auth.currentUser?.email}</p><button onClick={() => void signOut(auth)}>Se déconnecter</button></div></aside><main><header><div><span className="eyebrow">SPORTA · ADMINISTRATION GLOBALE</span><h1>{labels[page]}</h1></div><span className="badge">{import.meta.env.VITE_USE_EMULATORS === 'true' ? 'Environnement local' : 'Plateforme'}</span></header>{error && <p className="alert error" role="alert">{error}</p>}{message && <p className="alert" role="status">{message}</p>}
    {page === 'overview' && <><section className="hero"><span>UN ESPACE POUR CHAQUE ACADÉMIE</span><h2>Accompagnez votre réseau.<br />Gardez une vision d’ensemble.</h2><p>Gérez les accès, les forfaits et le développement de vos académies.</p><button onClick={() => setPage('academies')}>Gérer les académies →</button></section><div className="stats"><article><span>Académies</span><strong>{academies.length}</strong></article><article><span>Abonnements actifs</span><strong>{active.length}</strong></article><article><span>À renouveler / à activer</span><strong>{academies.filter(a => !active.some(s => s.id === a.id)).length}</strong></article><article><span>Forfaits disponibles</span><strong>{plans.filter(p => p.active).length}</strong></article></div><section className="card"><h2>Gestion manuelle des abonnements</h2><p>Les paiements en ligne seront intégrés ultérieurement. L’activation d’un forfait ne constitue pas un encaissement.</p></section></>}
    {page === 'academies' && <><section className="card"><label>Gérer les membres d’une académie<select value={membersAcademy} onChange={event => setMembersAcademy(event.target.value)}><option value="">Choisir une académie</option>{academies.map(a => <option key={a.id} value={a.id}>{a.name}</option>)}</select></label></section>{membersAcademy && <MembersPanel key={membersAcademy} academyId={membersAcademy} platform canManage />}<section className="card"><h2>Nouvelle académie</h2><p>Le propriétaire doit avoir un compte dans Firebase Authentication SportA.</p><form className="grid" onSubmit={submit('platformCreateAcademy', d => Object.fromEntries(d))}><label>Identifiant unique<input name="academyId" pattern="[a-zA-Z0-9_-]+" maxLength={100} required placeholder="tennis-dubai" /></label><label>Nom<input name="name" required maxLength={160} /></label><label>Pays<input name="country" required maxLength={160} /></label><label>Email du propriétaire<input name="ownerEmail" type="email" required /></label><button disabled={busy}>Créer l’académie</button></form></section><section className="card"><h2>Votre réseau</h2>{!academies.length && <p>Aucune académie. Créez votre première académie ci-dessus.</p>}<div className="table"><table><thead><tr><th>Académie</th><th>Statut</th><th>Forfait</th><th>Échéance</th><th>Accès</th></tr></thead><tbody>{academies.map(a => <tr key={a.id}><td><b>{a.name}</b><small>{a.country} · {a.ownerEmail}</small></td><td>{a.status === 'active' ? 'Active' : 'Suspendue'}</td><td>{subscription(a.id)?.planName ?? 'Non attribué'}</td><td>{date(subscription(a.id)?.endsAt)}</td><td><button disabled={busy} onClick={() => { if (window.confirm(`${a.status === 'active' ? 'Suspendre' : 'Réactiver'} ${a.name} ?`)) void action('platformSetAcademyStatus', { academyId: a.id, status: a.status === 'active' ? 'suspended' : 'active' }) }}>{a.status === 'active' ? 'Suspendre' : 'Réactiver'}</button></td></tr>)}</tbody></table></div></section><section className="card"><h2>Activer ou prolonger un abonnement</h2><p>La durée s’ajoute à la période en cours, ou commence aujourd’hui si elle est expirée. Les limites du forfait choisi s’appliquent immédiatement.</p><form className="grid" onSubmit={submit('platformActivateSubscription', d => ({ academyId: d.get('academyId'), planId: d.get('planId'), durationDays: Number(d.get('durationDays')), note: d.get('note') }))}><label>Académie<select name="academyId" required defaultValue=""><option value="" disabled>Choisir</option>{academies.map(a => <option key={a.id} value={a.id}>{a.name}</option>)}</select></label><label>Forfait<select name="planId" required defaultValue=""><option value="" disabled>Choisir</option>{plans.filter(p => p.active).map(p => <option key={p.id} value={p.id}>{p.name}</option>)}</select></label><label>Durée en jours<input name="durationDays" type="number" min="1" max="3660" defaultValue="30" required /></label><label>Motif / référence interne<input name="note" required maxLength={500} /></label><button disabled={busy || !academies.length || !plans.some(p => p.active)}>Enregistrer l’accès</button></form></section></>}
    {page === 'plans' && <><section className="card"><h2>Créer un forfait</h2><form className="grid" onSubmit={submit('platformSavePlan', d => ({ planId: d.get('planId'), name: d.get('name'), maxPlayers: Number(d.get('maxPlayers')), maxStaff: Number(d.get('maxStaff')), active: true }))}><label>Identifiant<input name="planId" pattern="[a-zA-Z0-9_-]+" maxLength={100} required /></label><label>Nom<input name="name" required maxLength={160} /></label><label>Limite de joueurs<input type="number" name="maxPlayers" min="1" max="1000000" required /></label><label>Limite de membres d’équipe<input type="number" name="maxStaff" min="1" max="1000000" required /></label><button disabled={busy}>Enregistrer le forfait</button></form><p>Réutiliser un identifiant met à jour le catalogue ; les abonnements existants conservent leurs limites jusqu’à leur prochaine activation.</p></section><div className="stats">{plans.map(p => <article key={p.id}><span>{p.active ? 'Disponible' : 'Désactivé'}</span><h2>{p.name}</h2><p>{p.maxPlayers} joueurs · {p.maxStaff} membres d’équipe</p><button disabled={busy} onClick={() => void action('platformSavePlan', { planId: p.id, name: p.name, maxPlayers: p.maxPlayers, maxStaff: p.maxStaff, active: !p.active })}>{p.active ? 'Désactiver' : 'Activer'}</button></article>)}</div></>}
    {page === 'audit' && <section className="card"><h2>Les 50 dernières opérations</h2><div className="table"><table><thead><tr><th>Date</th><th>Action</th><th>Cible</th><th>Opérateur</th><th>Détails</th></tr></thead><tbody>{logs.map(log => <tr key={log.id}><td>{date(log.createdAt)}</td><td>{log.action}</td><td>{log.targetId}</td><td>{log.actorId}</td><td>{JSON.stringify(log.details)}</td></tr>)}</tbody></table></div>{!logs.length && <p>Aucune opération enregistrée.</p>}</section>}
  </main></div>
}

