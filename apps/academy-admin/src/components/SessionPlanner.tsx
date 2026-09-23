import { useEffect, useMemo, useState } from 'react'
import { Alert, Box, Button, Card, CardContent, CircularProgress, Dialog, DialogActions, DialogContent, DialogTitle, FormControl, InputLabel, MenuItem, Select, Stack, TextField, Typography } from '@mui/material'
import { AddRounded, EventAvailableRounded } from '@mui/icons-material'
import { collection, onSnapshot, query, Timestamp, where } from 'firebase/firestore'
import { db } from '../firebase'
import { createSession, type SessionActivityType, type SessionConfigurationType } from '../services/managementService'
import { localeFor, useI18n } from '../i18n'

interface Configuration { id: string; type: SessionConfigurationType; minAge: number; maxAge: number | null }
interface Coach { id: string; name: string }
interface Stadium { id: string; name: string; courtCount: number }
interface PlannedSession { id: string; title: string; coachName: string; courtName: string; startsAt?: Timestamp; endsAt?: Timestamp; capacity: number; bookedCount: number }
const typeLabel = (type: SessionConfigurationType) => type === 'private' ? 'Séance privée' : type === 'semi_private' ? 'Séance semi-privée' : 'Séance de groupe'

export function SessionPlanner({ academyId, activityType, notify }: { academyId: string; activityType: SessionActivityType; notify: (message: string) => void }) {
  const { t, language } = useI18n()
  const [configurations, setConfigurations] = useState<Configuration[]>([]); const [coaches, setCoaches] = useState<Coach[]>([]); const [stadiums, setStadiums] = useState<Stadium[]>([]); const [sessions, setSessions] = useState<PlannedSession[]>([])
  const [open, setOpen] = useState(false); const [loading, setLoading] = useState(false); const [error, setError] = useState('')
  const [form, setForm] = useState({ configurationId: '', coachId: '', stadiumId: '', courtNumber: null as number | null, capacity: 1, date: '', startTime: '', endTime: '' })
  useEffect(() => {
    if (!academyId) return
    const stops = [
      onSnapshot(query(collection(db, 'sessionConfigurations'), where('academyId', '==', academyId)), snap => setConfigurations(snap.docs.filter(doc => doc.get('active') === true && (doc.get('activityType') ?? 'tennis') === activityType).map(doc => ({ id: doc.id, type: doc.get('type'), minAge: Number(doc.get('minAge')), maxAge: doc.get('maximumAge') === null ? null : Number(doc.get('maximumAge') ?? doc.get('maxAge')) })))),
      onSnapshot(query(collection(db, 'coaches'), where('academyId', '==', academyId)), snap => setCoaches(snap.docs.filter(doc => doc.get('status') === 'active').map(doc => ({ id: doc.id, name: doc.get('displayName') || doc.id })))),
      onSnapshot(query(collection(db, 'stadiums'), where('academyId', '==', academyId)), snap => setStadiums(snap.docs.filter(doc => doc.get('status') === 'active').map(doc => ({ id: doc.id, name: doc.get('name') || doc.id, courtCount: Number(doc.get('courtCount') || 0) })))),
      onSnapshot(query(collection(db, 'sessions'), where('academyId', '==', academyId)), snap => setSessions(snap.docs.filter(doc => doc.get('status') === 'open' && (doc.get('activityType') ?? 'tennis') === activityType && doc.get('startsAt')?.toMillis() > Date.now()).map(doc => ({ id: doc.id, title: doc.get('title') || 'Séance', coachName: doc.get('coachName') || '—', courtName: doc.get('courtName') || '—', startsAt: doc.get('startsAt'), endsAt: doc.get('endsAt'), capacity: Number(doc.get('capacity') || 0), bookedCount: Number(doc.get('bookedCount') || 0) })).sort((a, b) => (a.startsAt?.toMillis() ?? 0) - (b.startsAt?.toMillis() ?? 0)))),
    ]
    return () => stops.forEach(stop => stop())
  }, [academyId, activityType])
  const stadium = useMemo(() => stadiums.find(item => item.id === form.stadiumId), [stadiums, form.stadiumId])
  const submit = async () => {
    const startsAt = new Date(`${form.date}T${form.startTime}`); const endsAt = new Date(`${form.date}T${form.endTime}`)
    if (!form.configurationId || !form.coachId || !form.date || !form.startTime || !form.endTime || !Number.isInteger(form.capacity) || form.capacity < 1 || form.courtNumber !== null && (!form.stadiumId || !Number.isInteger(form.courtNumber) || form.courtNumber < 1 || form.courtNumber > (stadium?.courtCount ?? 0)) || !Number.isFinite(startsAt.valueOf()) || endsAt <= startsAt) { setError(t('Veuillez renseigner tous les champs correctement.')); return }
    if (endsAt.valueOf() - startsAt.valueOf() > 8 * 60 * 60 * 1000) { setError(t('La durée du créneau ne peut pas dépasser 8 heures.')); return }
    setLoading(true); setError('')
    try { await createSession({ configurationId: form.configurationId, coachId: form.coachId, stadiumId: form.stadiumId || null, courtNumber: form.stadiumId ? form.courtNumber : null, capacity: form.capacity, startsAt: startsAt.toISOString(), endsAt: endsAt.toISOString() }); notify(t('Créneau planifié')); setOpen(false) }
    catch (reason) { setError(reason instanceof Error ? t(reason.message) : t('Une erreur est survenue')) } finally { setLoading(false) }
  }
  const dateFormat = new Intl.DateTimeFormat(localeFor(language), { dateStyle: 'medium', timeStyle: 'short' })
  return <Card><CardContent><Stack direction={{ xs: 'column', sm: 'row' }} justifyContent="space-between" alignItems={{ sm: 'center' }} gap={2}><Box><Typography variant="h6">{t('Créneaux planifiés')}</Typography><Typography color="text.secondary">{t('Planifiez les dates, coachs, terrains et capacités proposés à la réservation.')}</Typography></Box><Button variant="contained" startIcon={<AddRounded />} onClick={() => setOpen(true)}>{t('Planifier un créneau')}</Button></Stack>
    <Stack gap={1.2} mt={2}>{!sessions.length && <Alert severity="info">{t('Aucun créneau planifié.')}</Alert>}{sessions.map(item => <Box key={item.id} sx={{ p: 2, border: '1px solid', borderColor: 'divider', borderRadius: 3 }}><Stack direction={{ xs: 'column', md: 'row' }} justifyContent="space-between" gap={1}><Box><Typography fontWeight={800}>{t(item.title)}</Typography><Typography variant="body2" color="text.secondary">{item.startsAt ? dateFormat.format(item.startsAt.toDate()) : '—'} · {item.coachName} · {item.courtName}</Typography></Box><Typography fontWeight={800}>{item.bookedCount}/{item.capacity} {t('places')}</Typography></Stack></Box>)}</Stack>
    <Dialog open={open} onClose={() => !loading && setOpen(false)} fullWidth maxWidth="sm"><DialogTitle>{t('Planifier un créneau')}</DialogTitle><DialogContent><Stack gap={2} pt={1}>{error && <Alert severity="error">{error}</Alert>}
      <FormControl><InputLabel>{t('Configuration de séance')}</InputLabel><Select label={t('Configuration de séance')} value={form.configurationId} onChange={e => { const selected = configurations.find(item => item.id === e.target.value); setForm({ ...form, configurationId: e.target.value, capacity: selected?.type === 'private' ? 1 : selected?.type === 'semi_private' ? 2 : 4 }) }}>{configurations.map(item => <MenuItem key={item.id} value={item.id}>{t(typeLabel(item.type))} · {item.maxAge == null ? `${item.minAge} ${t('ans')}` : `${item.minAge}–${item.maxAge} ${t('ans')}`}</MenuItem>)}</Select></FormControl>
      <FormControl><InputLabel>{t('Coach')}</InputLabel><Select label={t('Coach')} value={form.coachId} onChange={e => setForm({ ...form, coachId: e.target.value })}>{coaches.map(item => <MenuItem key={item.id} value={item.id}>{item.name}</MenuItem>)}</Select></FormControl>
      <FormControl><InputLabel>{t('Stade (facultatif)')}</InputLabel><Select label={t('Stade (facultatif)')} value={form.stadiumId} onChange={e => setForm({ ...form, stadiumId: e.target.value, courtNumber: null })}><MenuItem value="">{t('À définir plus tard')}</MenuItem>{stadiums.map(item => <MenuItem key={item.id} value={item.id}>{item.name}</MenuItem>)}</Select></FormControl>
      <Stack direction="row" gap={1.5}><TextField fullWidth disabled={!form.stadiumId} type="number" label={t('Numéro du terrain (facultatif)')} value={form.courtNumber ?? ''} inputProps={{ min: 1, max: stadium?.courtCount ?? 1 }} onChange={e => setForm({ ...form, courtNumber: e.target.value ? Number(e.target.value) : null })} /><TextField fullWidth type="number" label={t('Capacité')} value={form.capacity} inputProps={{ min: 1, max: 100 }} onChange={e => setForm({ ...form, capacity: Number(e.target.value) })} /></Stack>
      <TextField type="date" label={t('Date')} InputLabelProps={{ shrink: true }} value={form.date} onChange={e => setForm({ ...form, date: e.target.value })} />
      <Stack direction="row" gap={1.5}><TextField fullWidth type="time" label={t('Heure de début')} InputLabelProps={{ shrink: true }} value={form.startTime} onChange={e => setForm({ ...form, startTime: e.target.value })} /><TextField fullWidth type="time" label={t('Heure de fin')} InputLabelProps={{ shrink: true }} value={form.endTime} onChange={e => setForm({ ...form, endTime: e.target.value })} /></Stack>
    </Stack></DialogContent><DialogActions sx={{ p: 3 }}><Button onClick={() => setOpen(false)} disabled={loading}>{t('Annuler')}</Button><Button variant="contained" startIcon={loading ? <CircularProgress size={18} color="inherit" /> : <EventAvailableRounded />} disabled={loading} onClick={submit}>{t('Planifier')}</Button></DialogActions></Dialog>
  </CardContent></Card>
}
