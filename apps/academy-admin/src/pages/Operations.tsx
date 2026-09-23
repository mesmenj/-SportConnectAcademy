import { useCallback, useMemo, useState } from 'react'
import { Accordion, AccordionDetails, AccordionSummary, Alert, Avatar, Box, Button, Card, CardContent, Chip, CircularProgress, Dialog, DialogActions, DialogContent, DialogContentText, DialogTitle, IconButton, Stack, Tab, Table, TableBody, TableCell, TableContainer, TableHead, TableRow, Tabs, TextField, Tooltip, Typography } from '@mui/material'
import { CalendarMonthRounded, CheckRounded, CloseRounded, DeleteOutlineRounded, DoneAllRounded, ExpandMoreRounded, HistoryRounded, PersonRemoveRounded } from '@mui/icons-material'
import type { DocumentSnapshot } from 'firebase/firestore'
import { colors } from '../theme'
import type { Booking, BookingStatus } from '../data'
import { useI18n } from '../i18n'
import { fetchBookingHistory, softDeleteFirebaseBooking, softDeleteFirebasePlayerBookings } from '../services/bookingService'
import { useAppSelector } from '../store/hooks'
import type { AdminUser } from '../store/authSlice'
import { matchesSearch } from '../utils/search'

const statusColor = (status: BookingStatus) => status === 'Confirmée' ? 'success' : status === 'En attente' ? 'warning' : status === 'Refusée' || status === 'Annulée' ? 'error' : 'default'

interface PlayerBookings {
  key: string
  playerId: string
  student: string
  initials: string
  age: number
  bookings: Booking[]
}

export function Operations({ bookings, searchQuery = '', onDecision, onComplete }: { bookings: Booking[]; searchQuery?: string; onDecision: (id: string, decision: 'approve' | 'reject') => Promise<void>; onComplete: (id: string) => Promise<void> }) {
  const { t } = useI18n()
  const admin = useAppSelector(state => state.auth.user)
  const [tab, setTab] = useState<'operations' | 'history'>('operations')
  const [filter, setFilter] = useState('Toutes')
  const [processing, setProcessing] = useState('')
  const [error, setError] = useState('')
  const [bookingToDelete, setBookingToDelete] = useState<Booking | null>(null)
  const [groupToDelete, setGroupToDelete] = useState<PlayerBookings | null>(null)
  const [deleting, setDeleting] = useState(false)
  const visible = useMemo(() => bookings.filter(row => (filter === 'Toutes' || row.status === filter) && matchesSearch(searchQuery, row.id, row.playerId, row.student, row.date, row.time, row.type, row.coach, row.location, row.status)), [bookings, filter, searchQuery])
  const groups = useMemo(() => {
    const byPlayer = new Map<string, PlayerBookings>()
    visible.forEach(booking => {
      const key = booking.playerId || `name:${booking.student.trim().toLocaleLowerCase()}`
      const current = byPlayer.get(key)
      if (current) current.bookings.push(booking)
      else byPlayer.set(key, { key, playerId: booking.playerId, student: booking.student, initials: booking.initials, age: booking.age, bookings: [booking] })
    })
    return [...byPlayer.values()]
  }, [visible])
  const act = async (id: string, action: () => Promise<void>) => { setProcessing(id); setError(''); try { await action() } catch (reason) { setError(reason instanceof Error ? t(reason.message) : t('Une erreur est survenue')) } finally { setProcessing('') } }
  const deleteBooking = async () => { if (!bookingToDelete) return; setDeleting(true); setError(''); try { await softDeleteFirebaseBooking(bookingToDelete.id); setBookingToDelete(null) } catch (reason) { setError(reason instanceof Error ? t(reason.message) : t('Une erreur est survenue')) } finally { setDeleting(false) } }
  const deletePlayerBookings = async () => { if (!groupToDelete?.playerId) return; setDeleting(true); setError(''); try { await softDeleteFirebasePlayerBookings(groupToDelete.playerId); setGroupToDelete(null) } catch (reason) { setError(reason instanceof Error ? t(reason.message) : t('Une erreur est survenue')) } finally { setDeleting(false) } }

  return <Stack gap={2}>
    <Tabs value={tab} onChange={(_, value: 'operations' | 'history') => setTab(value)} aria-label={t('Navigation des réservations')}>
      <Tab value="operations" icon={<CalendarMonthRounded />} iconPosition="start" label={t('Suivi des réservations')} />
      <Tab value="history" icon={<HistoryRounded />} iconPosition="start" label={t('Historique complet')} />
    </Tabs>
    {tab === 'history' && admin && <BookingHistory admin={admin} searchQuery={searchQuery} onComplete={onComplete} />}
    {tab === 'operations' && <>
    {error && <Alert severity="error">{error}</Alert>}
    <Stack direction="row" gap={1} flexWrap="wrap">{['Toutes', 'Confirmée', 'En attente', 'Terminée', 'Annulée', 'Refusée'].map(item => <Chip clickable key={item} label={`${t(item)} ${item === 'Toutes' ? bookings.length : bookings.filter(row => row.status === item).length}`} color={filter === item ? 'primary' : 'default'} onClick={() => setFilter(item)} />)}</Stack>
    {!bookings.length && <Alert severity="info">{t('Aucune réservation Firebase pour le moment.')}</Alert>}
    {!!bookings.length && !groups.length && <Alert severity="info">{t('Aucune réservation pour ce filtre.')}</Alert>}
    <Stack gap={1.2}>{groups.map(group => {
      const latest = group.bookings[0]
      const pending = group.bookings.filter(item => item.status === 'En attente').length
      const confirmed = group.bookings.filter(item => item.status === 'Confirmée').length
      const completed = group.bookings.filter(item => item.status === 'Terminée').length
      return <Accordion key={group.key} disableGutters elevation={0} sx={{ border: `1px solid ${colors.line}`, borderRadius: '18px !important', overflow: 'hidden', '&:before': { display: 'none' } }}>
        <AccordionSummary expandIcon={<ExpandMoreRounded />} sx={{ px: { xs: 2, md: 2.5 }, py: 1, '& .MuiAccordionSummary-content': { my: 1.2 } }}>
          <Stack direction={{ xs: 'column', md: 'row' }} alignItems={{ xs: 'flex-start', md: 'center' }} gap={{ xs: 1.2, md: 2 }} width="100%" pr={1}>
            <Stack direction="row" gap={1.3} alignItems="center" minWidth={{ md: 260 }}>
              <Avatar sx={{ bgcolor: colors.sky, fontSize: 12 }}>{group.initials}</Avatar>
              <Box><Typography fontWeight={900}>{group.student}</Typography><Typography variant="caption" color="text.secondary">{group.age ? `${group.age} ${t('ans')}` : t('Âge non renseigné')}</Typography></Box>
            </Stack>
            <Stack direction="row" gap={.8} flexWrap="wrap" flex={1}>
              <Chip size="small" label={`${group.bookings.length} ${t(group.bookings.length > 1 ? 'réservations' : 'réservation')}`} />
              {pending > 0 && <Chip size="small" color="warning" label={`${pending} ${t('en attente')}`} />}
              {confirmed > 0 && <Chip size="small" color="success" label={`${confirmed} ${t('confirmée(s)')}`} />}
              {completed > 0 && <Chip size="small" label={`${completed} ${t('terminée(s)')}`} />}
            </Stack>
            <Box minWidth={{ md: 175 }}><Typography variant="caption" color="text.secondary">{t('Réservation récente')}</Typography><Typography variant="body2" fontWeight={800}>{latest.date} · {latest.time}</Typography></Box>
            {group.playerId && <Tooltip title={t('Retirer le client du Booking')}><IconButton color="error" aria-label={t('Retirer le client du Booking')} onClick={event => { event.stopPropagation(); setGroupToDelete(group) }}><PersonRemoveRounded /></IconButton></Tooltip>}
          </Stack>
        </AccordionSummary>
        <AccordionDetails sx={{ p: 0, borderTop: `1px solid ${colors.line}` }}>
          <Card elevation={0} square><TableContainer><Table size="small"><TableHead><TableRow>{['Date & heure', 'Séance', 'Coach', 'Lieu', 'Statut', 'Actions'].map(label => <TableCell key={label} sx={{ fontWeight: 800, fontSize: 11, color: 'text.secondary' }}>{t(label)}</TableCell>)}</TableRow></TableHead><TableBody>{group.bookings.map(row => <TableRow key={row.id} hover>
            <TableCell sx={{ minWidth: 145 }}><Typography variant="body2" fontWeight={700}>{row.date}</Typography><Typography variant="caption" color="text.secondary">{row.time}</Typography></TableCell>
            <TableCell>{t(row.type)}</TableCell><TableCell>{row.coach}</TableCell><TableCell>{row.location}</TableCell>
            <TableCell><Chip size="small" label={t(row.status)} color={statusColor(row.status)} /></TableCell>
            <TableCell><Stack direction="row" gap={.5}>{row.status === 'En attente' && <><Button size="small" color="success" startIcon={<CheckRounded />} disabled={processing === row.id} onClick={() => act(row.id, () => onDecision(row.id, 'approve'))}>{t('Approuver')}</Button><Button size="small" color="error" startIcon={<CloseRounded />} disabled={processing === row.id} onClick={() => act(row.id, () => onDecision(row.id, 'reject'))}>{t('Refuser')}</Button></>}{row.status === 'Confirmée' && <Button size="small" startIcon={<DoneAllRounded />} disabled={processing === row.id} onClick={() => act(row.id, () => onComplete(row.id))}>{t('Terminer')}</Button>}<Tooltip title={t('Supprimer la réservation')}><IconButton size="small" color="error" aria-label={t('Supprimer la réservation')} onClick={() => setBookingToDelete(row)}><DeleteOutlineRounded fontSize="small" /></IconButton></Tooltip></Stack></TableCell>
          </TableRow>)}</TableBody></Table></TableContainer></Card>
        </AccordionDetails>
      </Accordion>
    })}</Stack>
    <Dialog open={Boolean(bookingToDelete)} onClose={() => !deleting && setBookingToDelete(null)}><DialogTitle>{t('Supprimer la réservation ?')}</DialogTitle><DialogContent><DialogContentText>{t('La réservation sera masquée. Si elle était confirmée, la place et le cours seront restitués.')}</DialogContentText></DialogContent><DialogActions><Button disabled={deleting} onClick={() => setBookingToDelete(null)}>{t('Annuler')}</Button><Button color="error" variant="contained" disabled={deleting} onClick={() => void deleteBooking()}>{deleting ? <CircularProgress size={18} color="inherit" /> : t('Supprimer')}</Button></DialogActions></Dialog>
    <Dialog open={Boolean(groupToDelete)} onClose={() => !deleting && setGroupToDelete(null)}><DialogTitle>{t('Retirer le client du Booking ?')}</DialogTitle><DialogContent><DialogContentText>{t('Toutes les réservations de ce client seront masquées dans le Booking. Son profil joueur restera disponible dans Joueurs & familles.')}</DialogContentText></DialogContent><DialogActions><Button disabled={deleting} onClick={() => setGroupToDelete(null)}>{t('Annuler')}</Button><Button color="error" variant="contained" disabled={deleting} onClick={() => void deletePlayerBookings()}>{deleting ? <CircularProgress size={18} color="inherit" /> : t('Retirer')}</Button></DialogActions></Dialog>
    </>}
  </Stack>
}

const dateInput = (date: Date) => {
  const year = date.getFullYear()
  const month = String(date.getMonth() + 1).padStart(2, '0')
  const day = String(date.getDate()).padStart(2, '0')
  return `${year}-${month}-${day}`
}

function BookingHistory({ admin, searchQuery, onComplete }: { admin: AdminUser; searchQuery: string; onComplete: (id: string) => Promise<void> }) {
  const { t, language } = useI18n()
  const now = useMemo(() => new Date(), [])
  const [from, setFrom] = useState(() => dateInput(new Date(now.getFullYear(), now.getMonth(), 1)))
  const [to, setTo] = useState(() => dateInput(now))
  const [rows, setRows] = useState<Booking[]>([])
  const [cursor, setCursor] = useState<DocumentSnapshot | null>(null)
  const [hasMore, setHasMore] = useState(false)
  const [searched, setSearched] = useState(false)
  const [loading, setLoading] = useState(false)
  const [processing, setProcessing] = useState('')
  const [error, setError] = useState('')

  const load = useCallback(async (append = false) => {
    const fromDate = new Date(`${from}T00:00:00`)
    const toExclusive = new Date(`${to}T00:00:00`)
    toExclusive.setDate(toExclusive.getDate() + 1)
    if (!from || !to || !Number.isFinite(fromDate.valueOf()) || !Number.isFinite(toExclusive.valueOf()) || toExclusive <= fromDate) {
      setError(t('La date de fin doit être postérieure ou égale à la date de début.'))
      return
    }
    setLoading(true); setError('')
    try {
      const page = await fetchBookingHistory(admin, language, fromDate, toExclusive, append ? cursor : null)
      setRows(current => append ? [...current, ...page.rows] : page.rows)
      setCursor(page.cursor); setHasMore(page.hasMore)
      setSearched(true)
    } catch (reason) {
      setError(reason instanceof Error ? t(reason.message) : t('Impossible de charger l’historique des réservations.'))
    } finally { setLoading(false) }
  }, [admin, cursor, from, language, t, to])

  const visibleRows = useMemo(() => rows.filter(row => matchesSearch(searchQuery, row.id, row.playerId, row.student, row.date, row.time, row.type, row.coach, row.location, row.status)), [rows, searchQuery])
  const complete = async (bookingId: string) => {
    setProcessing(bookingId); setError('')
    try {
      await onComplete(bookingId)
      setRows(current => current.map(row => row.id === bookingId ? { ...row, status: 'Terminée' } : row))
    } catch (reason) {
      setError(reason instanceof Error ? t(reason.message) : t('Une erreur est survenue'))
    } finally { setProcessing('') }
  }

  return <Stack gap={2}>
    <Card><CardContent><Stack direction={{ xs: 'column', md: 'row' }} gap={1.5} alignItems={{ md: 'flex-end' }}>
      <TextField type="date" label={t('Date de début')} value={from} onChange={event => setFrom(event.target.value)} InputLabelProps={{ shrink: true }} inputProps={{ max: to }} />
      <TextField type="date" label={t('Date de fin')} value={to} onChange={event => setTo(event.target.value)} InputLabelProps={{ shrink: true }} inputProps={{ min: from }} />
      <Button variant="contained" startIcon={loading ? <CircularProgress size={17} color="inherit" /> : <CalendarMonthRounded />} disabled={loading} onClick={() => void load(false)}>{t('Filtrer')}</Button>
      <Typography variant="body2" color="text.secondary" sx={{ ml: { md: 'auto' } }}>{visibleRows.length} {t(visibleRows.length > 1 ? 'réservations chargées' : 'réservation chargée')}</Typography>
    </Stack></CardContent></Card>
    {error && <Alert severity="error">{error}</Alert>}
    {searched && !loading && !rows.length && <Alert severity="info">{t('Aucune réservation pour cette période.')}</Alert>}
    {!!visibleRows.length && <Card><TableContainer><Table size="small"><TableHead><TableRow>{['Joueur', 'Date & heure', 'Séance', 'Coach', 'Lieu', 'Statut', 'Actions'].map(label => <TableCell key={label} sx={{ fontWeight: 800, fontSize: 11, color: 'text.secondary' }}>{t(label)}</TableCell>)}</TableRow></TableHead><TableBody>{visibleRows.map(row => <TableRow key={row.id} hover>
      <TableCell><Stack direction="row" gap={1} alignItems="center"><Avatar sx={{ width: 30, height: 30, bgcolor: colors.sky, fontSize: 10 }}>{row.initials}</Avatar><Typography variant="body2" fontWeight={800}>{row.student}</Typography></Stack></TableCell>
      <TableCell sx={{ whiteSpace: 'nowrap' }}><Typography variant="body2" fontWeight={700}>{row.date}</Typography><Typography variant="caption" color="text.secondary">{row.time}</Typography></TableCell>
      <TableCell>{t(row.type)}</TableCell><TableCell>{row.coach}</TableCell><TableCell>{row.location}</TableCell>
      <TableCell><Chip size="small" label={t(row.status)} color={statusColor(row.status)} /></TableCell>
      <TableCell>{row.status === 'Confirmée' ? <Button size="small" startIcon={processing === row.id ? <CircularProgress size={15} color="inherit" /> : <DoneAllRounded />} disabled={Boolean(processing)} onClick={() => void complete(row.id)}>{t('Terminer')}</Button> : '—'}</TableCell>
    </TableRow>)}</TableBody></Table></TableContainer></Card>}
    {hasMore && <Button variant="outlined" disabled={loading} onClick={() => void load(true)}>{loading ? <CircularProgress size={18} /> : t('Charger plus')}</Button>}
  </Stack>
}
