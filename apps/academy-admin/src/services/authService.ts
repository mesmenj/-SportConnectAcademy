import {
  browserLocalPersistence,
  browserSessionPersistence,
  setPersistence,
  signInWithEmailAndPassword,
  signOut,
  type User,
} from 'firebase/auth'
import { doc, getDoc, onSnapshot } from 'firebase/firestore'
import { auth, db } from '../firebase'
import type { AdminUser } from '../store/authSlice'

const ADMIN_ROLES = new Set(['root', 'admin', 'academy_manager', 'booking_manager'])

export async function toAdminUser(user: User): Promise<AdminUser | null> {
  const profile = await getDoc(doc(db, 'users', user.uid))
  if (!profile.exists()) return null
  const data = profile.data()
  if (data.status !== 'active' || !ADMIN_ROLES.has(data.role)) return null
  const name = String(data.displayName || user.displayName || user.email?.split('@')[0] || 'Administrateur')
  const initials = name.split(/\s+/).slice(0, 2).map(part => part[0]?.toUpperCase()).join('') || 'AD'
  return {
    uid: user.uid,
    email: user.email ?? '',
    name,
    initials,
    role: data.role as AdminUser['role'],
    academyIds: Array.isArray(data.academyIds) ? data.academyIds : [],
    permissions: Array.isArray(data.permissions) ? data.permissions : [],
    phone: typeof data.phone === 'string' ? data.phone : '',
    preferredLanguage: data.preferredLanguage === 'en' || data.preferredLanguage === 'fr' ? data.preferredLanguage : undefined,
  }
}

export function subscribeToAdminProfile(user: User, callback: (admin: AdminUser | null) => void): () => void {
  return onSnapshot(doc(db, 'users', user.uid), snapshot => {
    if (!snapshot.exists()) { callback(null); return }
    const data = snapshot.data()
    if (data.status !== 'active' || !ADMIN_ROLES.has(data.role)) { callback(null); return }
    const name = String(data.displayName || user.displayName || user.email?.split('@')[0] || 'Administrateur')
    callback({
      uid: user.uid, email: user.email ?? '', name,
      initials: name.split(/\s+/).slice(0, 2).map(part => part[0]?.toUpperCase()).join('') || 'AD',
      role: data.role, academyIds: Array.isArray(data.academyIds) ? data.academyIds : [],
      permissions: Array.isArray(data.permissions) ? data.permissions : [],
      phone: typeof data.phone === 'string' ? data.phone : '',
      preferredLanguage: data.preferredLanguage === 'en' || data.preferredLanguage === 'fr' ? data.preferredLanguage : undefined,
    })
  }, () => callback(null))
}

export async function loginWithFirebase(email: string, password: string, remember: boolean): Promise<AdminUser> {
  await setPersistence(auth, remember ? browserLocalPersistence : browserSessionPersistence)
  const credential = await signInWithEmailAndPassword(auth, email.trim(), password)
  const admin = await toAdminUser(credential.user)
  if (!admin) {
    await signOut(auth)
    throw new Error('auth/not-admin')
  }
  return admin
}

export const logoutFromFirebase = () => signOut(auth)
