import { collection, getDocs, limit, onSnapshot, orderBy, query, startAfter, Timestamp, where, type DocumentData, type DocumentSnapshot, type QueryConstraint } from 'firebase/firestore'
import { getFunctions, httpsCallable } from 'firebase/functions'
import { db, firebaseApp } from '../firebase'
import type { Booking, BookingStatus } from '../data'
import type { AdminUser } from '../store/authSlice'
import { localeFor, type Language } from '../i18n'

const functions = getFunctions(firebaseApp, 'europe-west1')
const statusMap: Record<string, BookingStatus> = { pending: 'En attente', confirmed: 'Confirmée', completed: 'Terminée', cancelled: 'Annulée', rejected: 'Refusée' }
const initials = (name: string) => name.split(/\s+/).slice(0, 2).map(part => part[0]?.toUpperCase()).join('') || 'JR'

function toBooking(id: string, data: DocumentData, language: Language): Booking {
  const startsAt = data.startsAt?.toDate?.() as Date | undefined
  const student = data.playerName || data.playerId || 'Joueur'
  return { id, playerId: String(data.playerId ?? ''), student, initials: initials(student), age: Number(data.playerAge ?? 0), coach: data.coachName || data.coachId || '—', type: data.sessionType || 'Cours de tennis', date: startsAt ? new Intl.DateTimeFormat(localeFor(language), { day: '2-digit', month: 'long', year: 'numeric' }).format(startsAt) : '—', time: startsAt ? new Intl.DateTimeFormat(localeFor(language), { hour: '2-digit', minute: '2-digit' }).format(startsAt) : '—', court: data.courtName || data.courtId || '—', location: data.communityCourseName || data.communityCourseId || '—', amount: Number(data.amount ?? 0), currency: data.currency || 'AED', status: statusMap[data.status] ?? 'En attente' }
}

export function subscribeBookings(admin: AdminUser, language: Language, callback: (rows: Booking[]) => void): () => void {
  const constraints: QueryConstraint[] = []
  if (admin.role !== 'root') {
    if (!admin.academyIds.length) { callback([]); return () => undefined }
    constraints.push(where('academyId', 'in', admin.academyIds.slice(0, 10)))
  }
  constraints.push(orderBy('startsAt', 'desc'))
  return onSnapshot(query(collection(db, 'bookings'), ...constraints), snapshot => callback(snapshot.docs.filter(item => item.get('isDelete') !== true).map(item => toBooking(item.id, item.data(), language))), () => callback([]))
}

export interface BookingHistoryPage {
  rows: Booking[]
  cursor: DocumentSnapshot | null
  hasMore: boolean
}

export async function fetchBookingHistory(
  admin: AdminUser,
  language: Language,
  from: Date,
  toExclusive: Date,
  cursor: DocumentSnapshot | null = null,
): Promise<BookingHistoryPage> {
  if (!Number.isFinite(from.valueOf()) || !Number.isFinite(toExclusive.valueOf()) || toExclusive <= from) throw new Error('Période invalide.')
  const constraints: QueryConstraint[] = [
    where('startsAt', '>=', Timestamp.fromDate(from)),
    where('startsAt', '<', Timestamp.fromDate(toExclusive)),
  ]
  if (admin.role !== 'root') {
    if (!admin.academyIds.length) return { rows: [], cursor: null, hasMore: false }
    constraints.unshift(where('academyId', 'in', admin.academyIds.slice(0, 10)))
  }
  constraints.push(orderBy('startsAt', 'desc'))
  if (cursor) constraints.push(startAfter(cursor))
  const pageSize = 100
  constraints.push(limit(pageSize))
  const snapshot = await getDocs(query(collection(db, 'bookings'), ...constraints))
  return {
    rows: snapshot.docs.filter(item => item.get('isDelete') !== true).map(item => toBooking(item.id, item.data(), language)),
    cursor: snapshot.docs.at(-1) ?? null,
    hasMore: snapshot.size === pageSize,
  }
}

export const createFirebaseBooking = (input: { sessionId: string; playerId: string; communityCourseId?: string; note?: string }) => httpsCallable(functions, 'createBooking')(input)
export const decideFirebaseBooking = (bookingId: string, decision: 'approve' | 'reject') => httpsCallable(functions, 'decideBooking')({ bookingId, decision })
export const completeFirebaseBooking = (bookingId: string) => httpsCallable(functions, 'updateBookingStatus')({ bookingId, status: 'completed' })
export const softDeleteFirebaseBooking = (bookingId: string) => httpsCallable<{ bookingId: string }, { bookingId: string; isDelete: true }>(functions, 'softDeleteBooking')({ bookingId })
export const softDeleteFirebasePlayerBookings = (playerId: string) => httpsCallable<{ playerId: string }, { playerId: string; isDelete: true; deletedCount: number }>(functions, 'softDeletePlayerBookings')({ playerId })

export interface BookingOption { id: string; label: string; academyId: string; age?: number; type?: string; activityType?: string; minAge?: number; maxAge?: number; maximumAge?: number | null; price?: number; currency?: string; courtCount?: number; communityId?: string; configurationId?: string; sessionConfigurationId?: string; remainingSessions?: number }
export function subscribeBookingOptions(admin: AdminUser, language: Language, onPlayers: (rows: BookingOption[]) => void, onSessions: (rows: BookingOption[]) => void, onConfigurations?: (rows: BookingOption[]) => void, onCoaches?: (rows: BookingOption[]) => void, onStadiums?: (rows: BookingOption[]) => void, onCourses?: (rows: BookingOption[]) => void): () => void {
  if (admin.role !== 'root' && !admin.academyIds.length) { onPlayers([]); onSessions([]); onConfigurations?.([]); onCoaches?.([]); onStadiums?.([]); onCourses?.([]); return () => undefined }
  const scoped = (name: string) => admin.role === 'root' ? query(collection(db, name)) : query(collection(db, name), where('academyId', 'in', admin.academyIds.slice(0, 10)))
  const normalizeType = (value: unknown) => { const type = String(value ?? '').toLowerCase().replace(/[ -]+/g, '_'); return type.startsWith('semi_private') ? 'semi_private' : type.startsWith('private') ? 'private' : type.startsWith('group') ? 'group' : type }
  const stopPlayers = onSnapshot(scoped('players'), snap => onPlayers(snap.docs.filter(item => item.get('isDelete') !== true).map(item => ({ id: item.id, academyId: item.get('academyId'), communityId: item.get('communityId'), age: Number(item.get('age')), label: item.get('displayName') || item.get('name') || item.id, sessionConfigurationId: item.get('sessionConfigurationId') || undefined, remainingSessions: Math.max(0, Number(item.get('remainingSessions') ?? 0)) }))))
  const stopSessions = onSnapshot(scoped('sessions'), snap => onSessions(snap.docs.filter(item => item.get('status') === 'open').map(item => { const start = item.get('startsAt') as Timestamp | undefined; return { id: item.id, academyId: item.get('academyId'), configurationId: item.get('configurationId'), activityType: item.get('activityType') ?? 'tennis', type: normalizeType(item.get('configurationType') ?? item.get('type')), label: `${item.get('title') || item.get('type') || 'Cours'} · ${start?.toDate ? new Intl.DateTimeFormat(localeFor(language), { dateStyle: 'short', timeStyle: 'short' }).format(start.toDate()) : ''}` } })))
  const stopConfigurations = onSnapshot(scoped('sessionConfigurations'), snap => onConfigurations?.(snap.docs.filter(item => item.get('active') === true).map(item => ({ id: item.id, academyId: item.get('academyId'), activityType: item.get('activityType') ?? 'tennis', type: item.get('type'), minAge: Number(item.get('minAge')), maxAge: item.get('maximumAge') === null ? Number(item.get('minAge')) : Number(item.get('maximumAge') ?? item.get('maxAge')), maximumAge: item.get('maximumAge') === null ? null : Number(item.get('maximumAge') ?? item.get('maxAge')), price: Number(item.get('price')), currency: item.get('currency') || 'AED', label: item.id }))))
  const stopCoaches = onSnapshot(scoped('coaches'), snap => onCoaches?.(snap.docs.filter(item => item.get('status') === 'active').map(item => ({ id: item.id, academyId: item.get('academyId'), label: item.get('displayName') || item.id }))))
  const stopStadiums = onSnapshot(scoped('stadiums'), snap => onStadiums?.(snap.docs.filter(item => item.get('status') === 'active').map(item => ({ id: item.id, academyId: item.get('academyId'), label: item.get('name') || item.id, courtCount: Number(item.get('courtCount') || 0) }))))
  const stopCourses = onSnapshot(collection(db, 'communityCourses'), snap => onCourses?.(snap.docs.filter(item => item.get('active') === true).map(item => ({ id: item.id, academyId: item.get('academyId'), communityId: item.get('communityId'), label: item.get('name') || item.id }))))
  return () => { stopPlayers(); stopSessions(); stopConfigurations(); stopCoaches(); stopStadiums(); stopCourses() }
}
