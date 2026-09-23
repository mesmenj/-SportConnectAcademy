import { collection, onSnapshot, query, where } from 'firebase/firestore'
import { db } from '../firebase'
import type { AdminUser } from '../store/authSlice'

export interface CashPayment { id: string; name: string; amount: number | null; currency: string; pending: boolean; confirmed: boolean }
export function subscribeCashPayments(admin: AdminUser, onData: (rows: CashPayment[]) => void, onError: () => void) {
  if (admin.role !== 'root' && !admin.academyIds.length) { onData([]); return () => {} }
  const scope = admin.role === 'root' ? [] : [where('academyId', 'in', admin.academyIds.slice(0, 10))]
  return onSnapshot(query(collection(db, 'players'), where('paymentMethod', '==', 'cash'), ...scope), snapshot => {
    onData(snapshot.docs.filter(doc => doc.get('isDelete') !== true).map(doc => ({
      id: doc.id, name: doc.get('displayName') || doc.get('name') || doc.id,
      amount: typeof doc.get('paymentAmount') === 'number' && Number.isFinite(doc.get('paymentAmount')) ? doc.get('paymentAmount') : null,
      currency: doc.get('paymentCurrency') || 'AED',
      pending: doc.get('paymentStatus') === 'cash_pending',
      confirmed: doc.get('paymentStatus') === 'confirmed',
    })))
  }, onError)
}
