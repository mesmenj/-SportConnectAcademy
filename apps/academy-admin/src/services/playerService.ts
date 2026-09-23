import type { PaymentInvoice } from '../utils/paymentInvoice'
import { collection, onSnapshot, query, where, type DocumentData, type QueryConstraint } from 'firebase/firestore'
import { db } from '../firebase'
import type { AdminUser } from '../store/authSlice'

export interface FamilyMember {
  id: string
  name: string
  relationship: string
  phone: string
  email: string
}

export interface PlayerRecord {
  id: string
  name: string
  initials: string
  age: number | null
  level: string
  academy: string
  coach: string
  progress: number
  totalSessions: number
  remainingSessions: number
  status: string
  paymentMethod: string
  invoice: PaymentInvoice | null
  paymentStatus: string
  academyId: string
  communityId: string | null
  communityName: string
  assignedUserId: string | null
  embeddedFamily: FamilyMember[]
}

export interface UserWithPlayers {
  id: string
  name: string
  email: string
  phone: string
  role: string
  status: string
  playerIds: string[]
}

const text = (value: unknown, fallback = '—') => typeof value === 'string' && value.trim() ? value.trim() : fallback
const initials = (name: string) => name.split(/\s+/).slice(0, 2).map(part => part[0]?.toUpperCase()).join('') || 'JR'
const member = (id: string, value: DocumentData): FamilyMember => ({
  id,
  name: text(value.displayName ?? value.name, 'Membre de la famille'),
  relationship: text(value.relationship ?? value.relation ?? value.role, 'Proche'),
  phone: text(value.phone ?? value.phoneNumber),
  email: text(value.email),
})

export function subscribePlayers(admin: AdminUser, onData: (rows: PlayerRecord[]) => void, onError: () => void): () => void {
  const constraints: QueryConstraint[] = []
  if (admin.role !== 'root') {
    if (!admin.academyIds.length) { onData([]); return () => undefined }
    constraints.push(where('academyId', 'in', admin.academyIds.slice(0, 10)))
  }
  let rows: PlayerRecord[] = []
  let progressByPlayer = new Map<string, number>()
  let playersReady = false
  let evaluationsReady = false
  const emit = () => {
    if (!playersReady || !evaluationsReady) return
    onData(rows.map(player => ({ ...player, progress: progressByPlayer.get(player.id) ?? 0 })))
  }
  const stopPlayers = onSnapshot(query(collection(db, 'players'), ...constraints), snapshot => {
    rows = snapshot.docs.filter(document => document.get('isDelete') !== true).sort((a, b) => (b.get('createdAt')?.toMillis?.() ?? 0) - (a.get('createdAt')?.toMillis?.() ?? 0)).map(document => {
      const data = document.data()
      const name = text(data.displayName ?? data.name, document.id)
      const embedded = Array.isArray(data.familyMembers) ? data.familyMembers.map((item: DocumentData, index: number) => member(String(item.id ?? index), item)) : []
      return {
        id: document.id,
        name,
        initials: initials(name),
        age: Number.isFinite(Number(data.age)) ? Number(data.age) : null,
        level: text(data.level, 'Non défini'),
        academy: text(data.academyName ?? data.academyId),
        coach: text(data.coachName ?? data.coachId),
        progress: 0,
        totalSessions: Math.max(0, Number(data.sessionCount ?? data.sessions ?? 0)),
        remainingSessions: Math.max(0, Number(data.remainingSessions ?? data.sessionCount ?? data.sessions ?? 0)),
        status: data.status === 'pending_cash_confirmation' ? 'En attente de confirmation' : data.status === 'inactive' || data.status === 'paused' ? 'En pause' : 'Actif',
        paymentMethod: text(data.paymentMethod, ''),
        paymentStatus: text(data.paymentStatus, ''),
        invoice: data.invoice ?? null,
        academyId: text(data.academyId, ''),
        communityId: typeof data.communityId === 'string' ? data.communityId : null,
        communityName: text(data.communityName, 'Non attribuée'),
        assignedUserId: typeof data.assignedUserId === 'string' ? data.assignedUserId : typeof data.createdForUserId === 'string' ? data.createdForUserId : null,
        embeddedFamily: embedded,
      }
    })
    playersReady = true
    emit()
  }, onError)
  const stopEvaluations = onSnapshot(query(collection(db, 'playerEvaluations'), ...constraints), snapshot => {
    const totals = new Map<string, { sum: number; count: number }>()
    snapshot.docs.forEach(document => {
      const playerId = document.get('playerId')
      const average = Number(document.get('average'))
      if (typeof playerId !== 'string' || !Number.isFinite(average)) return
      const current = totals.get(playerId) ?? { sum: 0, count: 0 }
      totals.set(playerId, { sum: current.sum + average, count: current.count + 1 })
    })
    progressByPlayer = new Map([...totals].map(([playerId, value]) => [playerId, Math.max(0, Math.min(100, Math.round(value.sum / value.count * 20)))]))
    evaluationsReady = true
    emit()
  }, onError)
  return () => { stopPlayers(); stopEvaluations() }
}

export function subscribePlayerFamily(player: PlayerRecord, onData: (rows: FamilyMember[]) => void, onError: () => void): () => void {
  return onSnapshot(collection(db, 'players', player.id, 'family'), snapshot => {
    const linked = snapshot.docs.map(document => member(document.id, document.data()))
    onData(linked.length ? linked : player.embeddedFamily)
  }, () => {
    onData(player.embeddedFamily)
    if (!player.embeddedFamily.length) onError()
  })
}

export function subscribeUsersWithPlayers(onData: (rows: UserWithPlayers[]) => void, onError: () => void): () => void {
  let users = new Map<string, UserWithPlayers>()
  const playerIds = new Map<string, string[]>()
  const playerStops = new Map<string, () => void>()
  const emit = () => onData([...users.values()].map(user => ({ ...user, playerIds: playerIds.get(user.id) ?? [] })).sort((a, b) => a.name.localeCompare(b.name)))
  const stopUsers = onSnapshot(collection(db, 'users'), snapshot => {
    const next = new Map<string, UserWithPlayers>()
    snapshot.docs.filter(document => ['parent', 'student'].includes(String(document.get('role')))).forEach(document => {
      const data = document.data()
      next.set(document.id, { id: document.id, name: text(data.displayName, data.email ?? document.id), email: text(data.email), phone: text(data.phone), role: text(data.role), status: text(data.status, 'active'), playerIds: playerIds.get(document.id) ?? [] })
      if (!playerStops.has(document.id)) {
        playerStops.set(document.id, onSnapshot(collection(db, 'users', document.id, 'players'), links => { playerIds.set(document.id, links.docs.map(link => link.id)); emit() }, onError))
      }
    })
    playerStops.forEach((stop, id) => { if (!next.has(id)) { stop(); playerStops.delete(id); playerIds.delete(id) } })
    users = next
    emit()
  }, onError)
  return () => { stopUsers(); playerStops.forEach(stop => stop()) }
}
