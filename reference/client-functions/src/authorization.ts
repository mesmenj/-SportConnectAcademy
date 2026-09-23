import { getFirestore } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';

export const PERMISSIONS = [
  'admins.manage', 'academies.manage', 'stadiums.manage', 'coaches.manage', 'sessions.manage', 'bookings.approve',
] as const;
export type Permission = typeof PERMISSIONS[number];
export type AdminRole = 'root' | 'admin' | 'academy_manager' | 'booking_manager';

export interface AdminProfile {
  uid: string;
  email: string;
  displayName: string;
  role: AdminRole;
  status: 'active' | 'suspended';
  academyIds: string[];
  permissions: Permission[];
}

export const ROLE_PERMISSIONS: Record<AdminRole, Permission[]> = {
  root: [...PERMISSIONS],
  admin: [...PERMISSIONS],
  academy_manager: ['academies.manage', 'stadiums.manage', 'coaches.manage', 'sessions.manage'],
  booking_manager: ['bookings.approve'],
};

export async function requirePermission(uid: string | undefined, permission: Permission, academyId?: string): Promise<AdminProfile> {
  if (!uid) throw new HttpsError('unauthenticated', 'Authentification requise.');
  const snapshot = await getFirestore().collection('users').doc(uid).get();
  if (!snapshot.exists) throw new HttpsError('permission-denied', 'Profil administrateur introuvable.');
  const profile = { uid, ...snapshot.data() } as AdminProfile;
  if (profile.status !== 'active') throw new HttpsError('permission-denied', 'Compte administrateur suspendu.');
  const effectivePermissions = new Set([...(Array.isArray(profile.permissions) ? profile.permissions : []), ...(ROLE_PERMISSIONS[profile.role] ?? [])]);
  if (!effectivePermissions.has(permission)) throw new HttpsError('permission-denied', 'Permission insuffisante.');
  if (academyId && profile.role !== 'root' && !profile.academyIds?.includes(academyId)) throw new HttpsError('permission-denied', 'Académie non autorisée.');
  return profile;
}

export function parseRole(value: unknown): AdminRole {
  if (!['root', 'admin', 'academy_manager', 'booking_manager'].includes(String(value))) throw new HttpsError('invalid-argument', 'Rôle invalide.');
  return value as AdminRole;
}

export function parseString(value: unknown, field: string, maxLength = 150): string {
  if (typeof value !== 'string' || !value.trim() || value.trim().length > maxLength) throw new HttpsError('invalid-argument', `${field} invalide.`);
  return value.trim();
}

export function parseIds(value: unknown, field: string): string[] {
  if (!Array.isArray(value) || value.length > 100) throw new HttpsError('invalid-argument', `${field} invalide.`);
  return [...new Set(value.map(item => parseString(item, field, 100)))];
}
