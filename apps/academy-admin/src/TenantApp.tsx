import MembersPanel from './MembersPanel'
import { useEffect, useState, type FormEvent } from 'react'
import { onAuthStateChanged, signInWithEmailAndPassword, signOut } from 'firebase/auth'
import { collection, doc, onSnapshot, type DocumentData } from 'firebase/firestore'
import { httpsCallable } from 'firebase/functions'
import { auth, db, functions } from './firebase'
import './sporta.css'
type Row = DocumentData & { id: string }
export default function TenantApp() {
  const [uid, setUid] = useState<string | null>(null)
  const [ready, setReady] = useState(false)
  const [memberships, setMemberships] = useState<Row[]>([])
  const [academyId, setAcademyId] = useState('')
  const [players, setPlayers] = useState<Row[]>([])
  const [subscription, setSubscription] = useState<DocumentData | null>(null)
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)
  const [now, setNow] = useState(() => Date.now())
  useEffect(() => { const timer = window.setInterval(() => setNow(Date.now()), 30000); return () => window.clearInterval(timer) }, [])
  useEffect(() => onAuthStateChanged(auth, user => { setUid(user?.uid ?? null); setReady(true); setAcademyId(''); setMemberships([]); setPlayers([]); setSubscription(null) }), [])
  useEffect(() => uid ? onSnapshot(collection(db, 'users', uid, 'memberships'), snap => setMemberships(snap.docs.filter(d => ['owner', 'manager'].includes(d.get('role'))).map(d => ({ id: d.id, ...d.data() }))), () => setError('Impossible de charger vos académies.')) : undefined, [uid])
  useEffect(() => {
    if (!academyId) return
    const stopPlayers = onSnapshot(collection(db, 'academies', academyId, 'players'), snap => setPlayers(snap.docs.map(d => ({ id: d.id, ...d.data() }))), () => { setPlayers([]); setError('Accès refusé ou académie suspendue.') })
    const stopSubscription = onSnapshot(doc(db, 'academySubscriptions', academyId), snap => setSubscription(snap.data() ?? null), () => setSubscription(null))
    return () => { stopPlayers(); stopSubscription() }
  }, [academyId])
  const active = subscription?.status === 'active' && subscription.endsAt?.toMillis() > now
  async function login(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); const data = new FormData(event.currentTarget); setBusy(true); setError('')
    try { await signInWithEmailAndPassword(auth, String(data.get('email')), String(data.get('password'))) } catch { setError('Connexion impossible. Vérifiez vos identifiants et les émulateurs.') } finally { setBusy(false) }
  }
  if (!ready) return <main>Chargement…</main>
  if (!uid) return <main className="login"><div className="brand">S<span>SportA</span></div><h1>Mon académie</h1><p>Connectez-vous à votre espace de gestion.</p><form onSubmit={login}><label>Email<input type="email" name="email" required autoComplete="username" /></label><label>Mot de passe<input type="password" name="password" required autoComplete="current-password" /></label><button disabled={busy}>Se connecter</button></form>{error && <p role="alert">{error}</p>}</main>
  return <main><header><div><span className="eyebrow">SPORTA · ESPACE ACADÉMIE</span><h1>{memberships.find(m => m.id === academyId)?.name ?? 'Bienvenue dans votre académie'}</h1></div><button onClick={() => void signOut(auth)}>Se déconnecter</button></header>{error && <p className="alert error" role="alert">{error}</p>}<section className="card"><label>Académie active<select value={academyId} onChange={event => { setPlayers([]); setSubscription(null); setError(''); setAcademyId(event.target.value) }}><option value="">Choisir une académie</option>{memberships.map(m => <option key={m.id} value={m.id}>{m.name}</option>)}</select></label>{!memberships.length && <p>Aucune académie associée à ce compte. Contactez votre opérateur SportA.</p>}</section>{academyId && <><MembersPanel key={academyId} academyId={academyId} canManage={memberships.find(m => m.id === academyId)?.role === 'owner'} /><section className="hero"><span>{active ? 'ABONNEMENT ACTIF' : 'ACTIVATION / RENOUVELLEMENT REQUIS'}</span><h2>{subscription?.planName ?? 'Aucun forfait'}</h2><p>{players.length} / {subscription?.maxPlayers ?? '—'} joueurs · Échéance : {subscription?.endsAt?.toDate().toLocaleDateString('fr-FR') ?? '—'}</p></section><section className="card" style={{ marginTop: 24 }}><h2>Joueurs de l’académie</h2><form className="grid" onSubmit={async event => { event.preventDefault(); const form = event.currentTarget; const data = new FormData(form); setBusy(true); setError(''); try { await httpsCallable(functions, 'academyCreatePlayer')({ academyId, name: data.get('name') }); form.reset() } catch (reason) { setError(reason instanceof Error ? reason.message : 'Création impossible.') } finally { setBusy(false) } }}><label>Nom du joueur<input name="name" required maxLength={160} /></label><button disabled={busy || !active}>Ajouter un joueur</button></form><div className="table"><table><thead><tr><th>Nom</th><th>Statut</th></tr></thead><tbody>{players.map(p => <tr key={p.id}><td>{p.name}</td><td>{p.status === 'active' ? 'Actif' : p.status}</td></tr>)}</tbody></table></div>{!players.length && <p>Aucun joueur enregistré dans cette académie.</p>}</section></>}</main>
}
