import { useEffect, useMemo, useState } from 'react'
import { Alert, Autocomplete, Button, CircularProgress, Dialog, DialogActions, DialogContent, DialogTitle, FormControl, InputLabel, MenuItem, Select, Stack, TextField, ToggleButton, ToggleButtonGroup, Typography } from '@mui/material'
import { CheckCircleRounded } from '@mui/icons-material'
import { createFirebaseBooking, subscribeBookingOptions, type BookingOption } from '../services/bookingService'
import { createSession } from '../services/managementService'
import { useAppSelector } from '../store/hooks'
import { formatMoney, useI18n } from '../i18n'

const typeLabel = (type?: string) => type === 'private' ? 'Séance privée' : type === 'semi_private' ? 'Séance semi-privée' : 'Séance de groupe'
type ActivityType = 'tennis' | 'padel'
const emptySlot = { coachId: '', stadiumId: '', courtNumber: null as number | null, capacity: 1, date: '', startTime: '', endTime: '' }

export function CreateBooking({ open, onClose, onCreated }: { open: boolean; onClose: () => void; onCreated: () => void }) {
  const { t, language } = useI18n(); const admin = useAppSelector(state => state.auth.user)
  const [players, setPlayers] = useState<BookingOption[]>([]); const [, setSessions] = useState<BookingOption[]>([]); const [configurations, setConfigurations] = useState<BookingOption[]>([])
  const [coaches, setCoaches] = useState<BookingOption[]>([]); const [stadiums, setStadiums] = useState<BookingOption[]>([])
  const [courses, setCourses] = useState<BookingOption[]>([])
  const [playerIds, setPlayerIds] = useState<string[]>([]); const [courseId, setCourseId] = useState(''); const [activityType, setActivityType] = useState<ActivityType>('tennis'); const [configurationId, setConfigurationId] = useState('')
  const [slot, setSlot] = useState(emptySlot); const [note, setNote] = useState(''); const [loading, setLoading] = useState(false); const [error, setError] = useState('')
  useEffect(() => admin ? subscribeBookingOptions(admin, language, setPlayers, setSessions, setConfigurations, setCoaches, setStadiums, setCourses) : undefined, [admin, language])
  const selectedPlayers = useMemo(() => playerIds.map(id => players.find(item => item.id === id)).filter((item): item is BookingOption => Boolean(item)), [playerIds, players])
  const player = selectedPlayers[0]; const configuration = configurations.find(item => item.id === configurationId)
  const compatibleConfigurations = configurations.filter(item => item.activityType === activityType)
  const compatibleCoaches = configuration ? coaches.filter(item => item.academyId === configuration.academyId) : []
  const compatibleStadiums = configuration ? stadiums.filter(item => item.academyId === configuration.academyId) : []
  const stadium = compatibleStadiums.find(item => item.id === slot.stadiumId)
  const manualComplete = Boolean(slot.coachId && slot.date && slot.startTime && slot.endTime && Number.isInteger(slot.capacity) && slot.capacity > 0 && (!slot.stadiumId || slot.courtNumber === null || slot.courtNumber >= 1 && slot.courtNumber <= (stadium?.courtCount ?? 0)))

  const selectConfiguration = (id: string) => {
    const selected = configurations.find(item => item.id === id)
    setConfigurationId(id); setSlot({ ...emptySlot, capacity: selected?.type === 'private' ? 1 : selected?.type === 'semi_private' ? 2 : 4 })
  }
  const selectCourse = (id: string) => setCourseId(id)
  const selectActivity = (activity: ActivityType) => {
    if (activity === activityType) return
    setActivityType(activity); setConfigurationId(''); setSlot(emptySlot); setError('')
  }
  const selectPlayers = (values: BookingOption[]) => {
    const nextPrimary = values[0]
    const primaryChanged = nextPrimary?.id !== player?.id
    setPlayerIds(values.map(item => item.id))
    if (!primaryChanged) {
      if (values.length > slot.capacity) setSlot(current => ({ ...current, capacity: values.length }))
      return
    }
    const subscribedConfiguration = configurations.some(item => item.id === nextPrimary?.sessionConfigurationId) ? nextPrimary!.sessionConfigurationId! : ''
    const selected = configurations.find(item => item.id === subscribedConfiguration)
    setCourseId(''); setActivityType(selected?.activityType === 'padel' ? 'padel' : 'tennis'); setConfigurationId(subscribedConfiguration)
    setSlot({ ...emptySlot, capacity: Math.max(values.length, selected?.type === 'private' ? 1 : selected?.type === 'semi_private' ? 2 : 4) })
  }
  const submit = async () => {
    setError('')
    const startsAt = new Date(`${slot.date}T${slot.startTime}`); const endsAt = new Date(`${slot.date}T${slot.endTime}`)
    if (!configurationId || !manualComplete || !Number.isFinite(startsAt.valueOf()) || endsAt <= startsAt) { setError(t('Veuillez renseigner tous les champs correctement.')); return }
    if (endsAt.valueOf() - startsAt.valueOf() > 8 * 60 * 60 * 1000) { setError(t('La durée du créneau ne peut pas dépasser 8 heures.')); return }
    setLoading(true)
    let selectedSessionId: string
    try {
      const result = await createSession({ configurationId, coachId: slot.coachId, stadiumId: slot.stadiumId || null, courtNumber: slot.stadiumId ? slot.courtNumber : null, capacity: slot.capacity, startsAt: startsAt.toISOString(), endsAt: endsAt.toISOString() })
      selectedSessionId = result.data.id
    } catch (reason) { setError(reason instanceof Error ? t(reason.message) : t('Une erreur est survenue')); setLoading(false); return }
    try {
      const results = await Promise.allSettled(playerIds.map(playerId => createFirebaseBooking({ playerId, sessionId: selectedSessionId, communityCourseId: courseId || undefined, note })))
      const failure = results.find(result => result.status === 'rejected')
      if (failure?.status === 'rejected') throw failure.reason
      onCreated()
    }
    catch (reason) { setError(reason instanceof Error ? t(reason.message) : t('Une erreur est survenue')) }
    finally { setLoading(false) }
  }

  return <Dialog open={open} onClose={() => !loading && onClose()} fullWidth maxWidth="sm"><DialogTitle>{t('Nouvelle réservation')}</DialogTitle><DialogContent><Stack gap={2} pt={1}>
    {error && <Alert severity="error">{error}</Alert>}{!players.length && <Alert severity="info">{t('Créez d’abord un joueur.')}</Alert>}
    <Autocomplete multiple disableCloseOnSelect options={players} value={selectedPlayers} getOptionLabel={item => `${item.label}${Number.isFinite(item.age) ? ` · ${item.age} ${t('ans')}` : ''}`} isOptionEqualToValue={(option, value) => option.id === value.id} onChange={(_, values) => selectPlayers(values)} renderInput={params => <TextField {...params} label={t('Rechercher et sélectionner des joueurs')} helperText={t('Tous les joueurs peuvent être ajoutés à cette réservation.')} />} />
    <FormControl><InputLabel>{t('Cours de la communauté (facultatif)')}</InputLabel><Select label={t('Cours de la communauté (facultatif)')} value={courseId} onChange={event => selectCourse(event.target.value)}><MenuItem value="">{t('À définir plus tard')}</MenuItem>{courses.map(item => <MenuItem key={item.id} value={item.id}>{item.label}</MenuItem>)}</Select></FormControl>
    <Stack gap={0.75}><Typography variant="subtitle2">{t('Sport')}</Typography><ToggleButtonGroup exclusive fullWidth color="primary" value={activityType} onChange={(_, value: ActivityType | null) => value && selectActivity(value)} disabled={!player} aria-label={t('Choix du sport')}><ToggleButton value="tennis">{t('Tennis')}</ToggleButton><ToggleButton value="padel">{t('Paddle')}</ToggleButton></ToggleButtonGroup></Stack>
    <FormControl disabled={!player}><InputLabel>{t('Configuration de séance')}</InputLabel><Select label={t('Configuration de séance')} value={configurationId} onChange={event => selectConfiguration(event.target.value)}>{compatibleConfigurations.map(item => <MenuItem key={item.id} value={item.id}>{t(item.activityType === 'padel' ? 'Paddle session' : 'Tennis session')} · {t(typeLabel(item.type))} · {item.maximumAge == null ? `${item.minAge} ${t('ans')}` : `${item.minAge}–${item.maximumAge} ${t('ans')}`} · {formatMoney(item.price ?? 0, item.currency ?? 'AED', language)}</MenuItem>)}</Select></FormControl>
    <Stack gap={2}>
      <Typography variant="subtitle2">{t('Nouveau créneau')}</Typography>
      <FormControl disabled={!configuration}><InputLabel>{t('Coach')}</InputLabel><Select label={t('Coach')} value={slot.coachId} onChange={e => setSlot({ ...slot, coachId: e.target.value })}>{compatibleCoaches.map(item => <MenuItem key={item.id} value={item.id}>{item.label}</MenuItem>)}</Select></FormControl>
      <FormControl disabled={!configuration}><InputLabel>{t('Stade (facultatif)')}</InputLabel><Select label={t('Stade (facultatif)')} value={slot.stadiumId} onChange={e => setSlot({ ...slot, stadiumId: e.target.value, courtNumber: null })}><MenuItem value="">{t('À définir plus tard')}</MenuItem>{compatibleStadiums.map(item => <MenuItem key={item.id} value={item.id}>{item.label}</MenuItem>)}</Select></FormControl>
      <Stack direction={{ xs: 'column', sm: 'row' }} gap={1.5}><TextField fullWidth disabled={!slot.stadiumId} type="number" label={t('Numéro du terrain (facultatif)')} value={slot.courtNumber ?? ''} inputProps={{ min: 1, max: stadium?.courtCount ?? 1 }} onChange={e => setSlot({ ...slot, courtNumber: e.target.value ? Number(e.target.value) : null })} /><TextField fullWidth type="number" label={t('Capacité')} value={slot.capacity} inputProps={{ min: 1, max: 100 }} onChange={e => setSlot({ ...slot, capacity: Number(e.target.value) })} /></Stack>
      <TextField type="date" label={t('Date')} InputLabelProps={{ shrink: true }} value={slot.date} onChange={e => setSlot({ ...slot, date: e.target.value })} />
      <Stack direction={{ xs: 'column', sm: 'row' }} gap={1.5}><TextField fullWidth type="time" label={t('Heure de début')} InputLabelProps={{ shrink: true }} value={slot.startTime} onChange={e => setSlot({ ...slot, startTime: e.target.value })} /><TextField fullWidth type="time" label={t('Heure de fin')} InputLabelProps={{ shrink: true }} value={slot.endTime} onChange={e => setSlot({ ...slot, endTime: e.target.value })} /></Stack>
    </Stack>
    <TextField multiline minRows={2} label={t('Note facultative')} value={note} onChange={event => setNote(event.target.value)} /><Typography variant="caption" color="text.secondary">{t('La réservation sera confirmée immédiatement.')}</Typography>
  </Stack></DialogContent><DialogActions sx={{ p: 3 }}><Button onClick={onClose} disabled={loading}>{t('Annuler')}</Button><Button variant="contained" startIcon={loading ? <CircularProgress size={18} color="inherit" /> : <CheckCircleRounded />} disabled={loading || !playerIds.length || !configurationId || !manualComplete} onClick={submit}>{t(playerIds.length > 1 ? 'Créer les réservations' : 'Créer la réservation')}</Button></DialogActions></Dialog>
}
