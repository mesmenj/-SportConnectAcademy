import { useEffect, useState, type FormEvent } from 'react'
import { collection, onSnapshot, type DocumentData } from 'firebase/firestore'
import { httpsCallable } from 'firebase/functions'
import { db, functions } from './firebase'
type Member = DocumentData & { id: string }
const roles: Record<string, string> = { owner: 'Propriétaire', manager: 'Responsable', coach: 'Coach', parent: 'Parent', student: 'Élève' }
export default function MembersPanel({ academyId, platform = false, canManage = false }: { academyId: string; platform?: boolean; canManage?: boolean }) {
  const [members, setMembers] = useState<Member[]>([])
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)
  const [message, setMessage] = useState('')
  useEffect(() => onSnapshot(collection(db, 'academies', academyId, 'members'), snap => setMembers(snap.docs.map(doc => ({ id: doc.id, ...doc.data() }))), () => { setMembers([]); setError('Impossible de consulter les membres de cette académie.') }), [academyId])
  async function save(data: object) {
    setBusy(true); setError(''); setMessage('')
    try { await httpsCallable(functions, platform ? 'platformSetMember' : 'academySetMember')({ academyId, ...data }); setMessage('Accès mis à jour.'); return true }
    catch (reason) { setError(reason instanceof Error ? reason.message : 'Modification impossible.'); return false }
    finally { setBusy(false) }
  }
  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); const form = event.currentTarget; const data = new FormData(form)
    if (await save({ email: data.get('email'), role: data.get('role'), status: 'active' })) form.reset()
  }
  return <section className="card"><h2>Équipe et familles</h2><p>Les accès sont propres à cette académie. Responsables et coachs actifs comptent dans le quota d’équipe.</p>{error && <p className="alert error" role="alert">{error}</p>}{message && <p className="alert" role="status">{message}</p>}{canManage && <form className="grid" onSubmit={submit}><label>Email du compte existant<input type="email" name="email" required /></label><label>Rôle<select name="role" defaultValue="coach">{Object.entries(roles).filter(([role]) => role !== 'owner').map(([role, label]) => <option key={role} value={role}>{label}</option>)}</select></label><button disabled={busy}>Attribuer / modifier l’accès</button></form>}<div className="table"><table><thead><tr><th>Membre</th><th>Rôle</th><th>Statut</th>{canManage && <th>Accès</th>}</tr></thead><tbody>{members.map(member => <tr key={member.id}><td>{member.displayName || member.email || member.id}{member.displayName && <small>{member.email}</small>}</td><td>{roles[member.role] ?? member.role}</td><td>{member.status === 'active' ? 'Actif' : 'Suspendu'}</td>{canManage && <td>{member.role !== 'owner' && member.email && <button disabled={busy} onClick={() => { const status = member.status === 'active' ? 'suspended' : 'active'; if (window.confirm(`${status === 'suspended' ? 'Suspendre' : 'Réactiver'} l’accès de ${member.email} à cette académie ?`)) void save({ email: member.email, role: member.role, status }) }}>{member.status === 'active' ? 'Suspendre' : 'Réactiver'}</button>}</td>}</tr>)}</tbody></table></div>{!members.length && <p>Aucun membre disponible.</p>}</section>
}
