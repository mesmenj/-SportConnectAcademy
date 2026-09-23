import { useEffect, useState, type ReactNode } from 'react'
import { Alert, Avatar, Box, Button, Card, CardContent, Chip, CircularProgress, FormControl, IconButton, InputLabel, MenuItem, Select, Stack, TextField, Tooltip, Typography } from '@mui/material'
import { CloseRounded, EditRounded, EventAvailableRounded, GroupsRounded, PaymentsRounded, PendingActionsRounded, SaveRounded } from '@mui/icons-material'
import { doc, onSnapshot } from 'firebase/firestore'
import type { Booking } from '../data'
import { colors } from '../theme'
import type { Page } from '../components/AdminShell'
import { formatMoney, useI18n } from '../i18n'
import { useAppSelector } from '../store/hooks'
import { db } from '../firebase'
import { subscribeCashPayments, type CashPayment } from '../services/cashPaymentService'
import { confirmCashPlayerPayment, updateValidatedRevenue, type SessionCurrency } from '../services/managementService'

function Panel({ title, action, onAction, children }: { title: string; action?: string; onAction?: () => void; children: ReactNode }) {
  const { t } = useI18n()
  return <Card><CardContent sx={{ p: { xs: 2, sm: 2.5 } }}><Stack direction="row" justifyContent="space-between" alignItems="center" mb={2}><Typography variant="h6">{t(title)}</Typography>{action && <Button size="small" onClick={onAction}>{t(action)}</Button>}</Stack>{children}</CardContent></Card>
}

const currencies: SessionCurrency[] = ['AED', 'XAF', 'EUR', 'USD', 'MAD']

function RevenueCard({ calculated, calculatedAmount, defaultCurrency }: { calculated: string; calculatedAmount: number; defaultCurrency: SessionCurrency }) {
  const { t, language } = useI18n()
  const admin = useAppSelector(state => state.auth.user)
  const canEdit = admin?.role === 'root'
  const [cashAdjustments, setCashAdjustments] = useState<Record<string, number>>({})
  const [saved, setSaved] = useState<{ amount: number; currency: SessionCurrency } | null>(null)
  const [revenueLoaded, setRevenueLoaded] = useState(false)
  const [readError, setReadError] = useState(false)
  const [editing, setEditing] = useState(false)
  const [amount, setAmount] = useState('')
  const [currency, setCurrency] = useState<SessionCurrency>(defaultCurrency)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')
  useEffect(() => {
    if (!admin) return
    return onSnapshot(doc(db, 'systemSettings', 'dashboard'), snapshot => {
      const value = snapshot.get('validatedRevenueAmount')
      const savedCurrency = snapshot.get('validatedRevenueCurrency')
      setSaved(snapshot.exists() && typeof value === 'number' && Number.isFinite(value) && currencies.includes(savedCurrency) ? { amount: value, currency: savedCurrency } : null)
      const totals = snapshot.get('confirmedCashTotals') ?? {}
      const baseline = snapshot.get('validatedRevenueCashBaseline') ?? {}
      setCashAdjustments(Object.fromEntries(currencies.map(code => [code, (Number(totals[code]) || 0) - (Number(baseline[code]) || 0)])))
      setRevenueLoaded(true); setReadError(false)
    }, () => { setReadError(true); setRevenueLoaded(false) })
  }, [admin])
  const startEdit = () => { setAmount(String(saved ? saved.amount + (cashAdjustments[saved.currency] ?? 0) : calculatedAmount)); setCurrency(saved?.currency ?? defaultCurrency); setError(''); setEditing(true) }
  const save = async () => {
    const value = Number(amount)
    if (!amount.trim() || !Number.isFinite(value) || value < 0 || value > 1_000_000_000) { setError(t('Montant invalide.')); return }
    setSaving(true); setError('')
    try { await updateValidatedRevenue({ amount: value, currency }); setEditing(false) }
    catch (reason) { setError(reason instanceof Error ? t(reason.message) : t('Une erreur est survenue')) }
    finally { setSaving(false) }
  }
  return <Card sx={{ minHeight: 168 }}><CardContent sx={{ p: 3 }}>
    <Stack direction="row" justifyContent="space-between"><Avatar variant="rounded" sx={{ bgcolor: `${colors.orange}20`, color: colors.orange }}><PaymentsRounded /></Avatar><Stack direction="row" alignItems="center" gap={.5}><Chip size="small" label={t('Confirmées et terminées')} sx={{ bgcolor: colors.cloud }} />{canEdit && !editing && <Tooltip title={t('Modifier le montant total')}><IconButton size="small" disabled={!revenueLoaded || readError} onClick={startEdit} aria-label={t('Modifier le montant total')}><EditRounded fontSize="small" /></IconButton></Tooltip>}</Stack></Stack>
    {editing ? <Stack mt={1.5} gap={1}>
      <Stack direction="row" gap={1}><TextField autoFocus fullWidth size="small" type="number" label={t('Montant total')} value={amount} inputProps={{ min: 0, max: 1_000_000_000, step: 1 }} onChange={event => setAmount(event.target.value)} /><FormControl size="small" sx={{ minWidth: 92 }}><InputLabel>{t('Devise')}</InputLabel><Select label={t('Devise')} value={currency} onChange={event => setCurrency(event.target.value as SessionCurrency)}>{currencies.map(item => <MenuItem key={item} value={item}>{item}</MenuItem>)}</Select></FormControl><IconButton color="primary" disabled={saving} onClick={() => void save()} aria-label={t('Enregistrer')}><SaveRounded /></IconButton><IconButton disabled={saving} onClick={() => setEditing(false)} aria-label={t('Annuler')}><CloseRounded /></IconButton></Stack>
      {error && <Alert severity="error" sx={{ py: 0 }}>{error}</Alert>}
    </Stack> : <Typography variant="h5" mt={2}>{!revenueLoaded || readError ? '—' : saved ? currencies.filter(code => code === saved.currency || cashAdjustments[code]).map(code => formatMoney((code === saved.currency ? saved.amount : 0) + (cashAdjustments[code] ?? 0), code, language)).join(' · ') : calculated}</Typography>}
    {readError && <Alert severity="error" sx={{ mt: 1 }}>{t('Impossible de charger le montant partagé. Veuillez actualiser la page.')}</Alert>}
    <Typography variant="body2" color="text.secondary">{t('Revenus validés')}</Typography>
  </CardContent></Card>
}

export function Dashboard({ bookings, navigate }: { bookings: Booking[]; navigate: (page: Page) => void }) {
  const { t, language } = useI18n()
  const admin = useAppSelector(state => state.auth.user)
  const [cashPayments, setCashPayments] = useState<CashPayment[]>([])
  const [cashError, setCashError] = useState('')
  const [confirming, setConfirming] = useState('')
  useEffect(() => admin ? subscribeCashPayments(admin, rows => { setCashPayments(rows); setCashError('') }, () => setCashError('Impossible de charger les paiements en espèces.')) : undefined, [admin])
  const pendingCash = cashPayments.filter(payment => payment.pending)
  const canConfirmCash = admin?.role === 'root' || admin?.role === 'admin' || admin?.permissions.includes('bookings.approve')
  const confirmCash = async (id: string) => {
    setConfirming(id); setCashError('')
    try { await confirmCashPlayerPayment(id) }
    catch (reason) { setCashError(reason instanceof Error ? reason.message : 'Une erreur est survenue') }
    finally { setConfirming('') }
  }
  const cashPlayerIds = new Set(cashPayments.filter(payment => payment.pending || payment.amount !== null).map(payment => payment.id))
  const activePlayers = new Set(bookings.filter(row => row.status !== 'Annulée' && row.status !== 'Refusée').map(row => row.student)).size
  const completed = bookings.filter(row => row.status === 'Terminée').length
  const pending = bookings.filter(row => row.status === 'En attente').length
  const revenueByCurrency = bookings.filter(row => !cashPlayerIds.has(row.playerId) && (row.status === 'Confirmée' || row.status === 'Terminée')).reduce<Record<string, number>>((totals, row) => { totals[row.currency] = (totals[row.currency] ?? 0) + row.amount; return totals }, {})
  cashPayments.filter(payment => payment.confirmed && payment.amount !== null).forEach(payment => { revenueByCurrency[payment.currency] = (revenueByCurrency[payment.currency] ?? 0) + payment.amount! })
  const revenue = Object.entries(revenueByCurrency).map(([currency, amount]) => formatMoney(amount, currency, language)).join(' · ') || '—'
  const defaultCurrency = (Object.keys(revenueByCurrency).find(currency => currencies.includes(currency as SessionCurrency)) as SessionCurrency | undefined) ?? 'AED'
  const stats: Array<[string, string, string, ReactNode, string]> = [
    ['Joueurs actifs', String(activePlayers), t('Données réelles'), <GroupsRounded />, colors.sky],
    ['Réservations', String(bookings.length), `${completed} ${t('terminées')}`, <EventAvailableRounded />, colors.green],
    ['En attente', String(pending + pendingCash.length), t('Validation requise'), <PendingActionsRounded />, colors.lilac],
  ]
  return <Stack gap={{ xs: 3, md: 4 }}>
    <Box sx={{ display: 'grid', gridTemplateColumns: { xs: '1fr', sm: 'repeat(2,1fr)', xl: 'repeat(4,1fr)' }, gap: { xs: 2, md: 3 } }}>{stats.slice(0, 2).map(stat => <Card key={stat[0]} sx={{ minHeight: 168 }}><CardContent sx={{ p: 3 }}>
      <Stack direction="row" justifyContent="space-between"><Avatar variant="rounded" sx={{ bgcolor: `${stat[4]}20`, color: stat[4] }}>{stat[3]}</Avatar><Chip size="small" label={stat[2]} sx={{ bgcolor: colors.cloud }} /></Stack>
      <Typography variant="h5" mt={2}>{stat[1]}</Typography><Typography variant="body2" color="text.secondary">{t(stat[0])}</Typography>
    </CardContent></Card>)}<RevenueCard calculated={revenue} calculatedAmount={revenueByCurrency[defaultCurrency] ?? 0} defaultCurrency={defaultCurrency} />{stats.slice(2).map(stat => <Card key={stat[0]} sx={{ minHeight: 168 }}><CardContent sx={{ p: 3 }}><Stack direction="row" justifyContent="space-between"><Avatar variant="rounded" sx={{ bgcolor: `${stat[4]}20`, color: stat[4] }}>{stat[3]}</Avatar><Chip size="small" label={stat[2]} sx={{ bgcolor: colors.cloud }} /></Stack><Typography variant="h5" mt={2}>{stat[1]}</Typography><Typography variant="body2" color="text.secondary">{t(stat[0])}</Typography></CardContent></Card>)}</Box>
    <Panel title="Paiements en espèces en attente">
      <Stack gap={1.5}>
        {cashError && <Alert severity="error">{t(cashError)}</Alert>}
        {!cashError && !pendingCash.length && <Typography color="text.secondary">{t('Aucun paiement en espèces en attente.')}</Typography>}
        {pendingCash.map(payment => <Stack key={payment.id} direction={{ xs: 'column', sm: 'row' }} alignItems={{ sm: 'center' }} gap={1.5} p={1.5} bgcolor={colors.cloud} borderRadius={3}>
          <Box flex={1}><Typography fontWeight={800}>{payment.name}</Typography><Typography variant="body2">{payment.amount === null ? t('Montant du forfait à vérifier') : formatMoney(payment.amount, payment.currency, language)}</Typography></Box>
          <Chip size="small" color="warning" label={t('En attente de confirmation')} />
          {canConfirmCash && <Button variant="contained" color="success" disabled={Boolean(confirming)} onClick={() => void confirmCash(payment.id)} startIcon={confirming === payment.id ? <CircularProgress size={16} color="inherit" /> : undefined}>{t('Confirmer le paiement')}</Button>}
        </Stack>)}
      </Stack>
    </Panel>
    <Box sx={{ display: 'grid', gridTemplateColumns: { xs: '1fr', xl: '1.6fr 1fr' }, gap: { xs: 2, md: 3 } }}>
      <Panel title="Réservations récentes" action="Tout voir" onAction={() => navigate('bookings')}><Stack gap={1}>{bookings.slice(0, 4).map(row => <Stack key={row.id} direction="row" alignItems="center" gap={1.5} py={1} borderBottom={`1px solid ${colors.line}`}><Typography fontWeight={800} width={48}>{row.time}</Typography><Avatar sx={{ width: 34, height: 34, fontSize: 10, bgcolor: colors.sky }}>{row.initials}</Avatar><Box flex={1}><Typography variant="body2" fontWeight={800}>{row.student}</Typography><Typography variant="caption" color="text.secondary">{t(row.type)} · {row.coach}</Typography></Box><Chip size="small" label={t(row.status)} color={row.status === 'Confirmée' ? 'success' : 'warning'} /></Stack>)}</Stack></Panel>
      <Panel title="À traiter"><Stack gap={1.3}>{pending === 0 ? <Typography color="text.secondary">{t('Aucune réservation en attente.')}</Typography> : bookings.filter(row => row.status === 'En attente').slice(0, 4).map(row => <Stack key={row.id} direction="row" alignItems="center" gap={1.4} p={1.2} bgcolor={colors.cloud} borderRadius={3}><Avatar sx={{ bgcolor: `${colors.orange}20`, color: colors.orange }}><PendingActionsRounded /></Avatar><Box><Typography variant="body2" fontWeight={800}>{row.student}</Typography><Typography variant="caption" color="text.secondary">{row.date} · {row.time}</Typography></Box></Stack>)}</Stack></Panel>
    </Box>
  </Stack>
}
