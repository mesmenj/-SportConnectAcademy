import { useEffect, useMemo, useState } from 'react'
import { Alert, Autocomplete, Button, CircularProgress, Dialog, DialogActions, DialogContent, DialogTitle, FormControl, InputLabel, ListSubheader, MenuItem, Select, Stack, TextField } from '@mui/material'
import { createPlayerForUser, getPlayerCreationOptions } from '../services/managementService'
import type { UserWithPlayers } from '../services/playerService'
import { formatMoney, useI18n } from '../i18n'

interface Configuration { id: string; activityType: string; type: string; minAge: number; maxAge: number; price: number; currency: string; sessionCount: number; dayOfWeek?: number; startTime?: string; durationMinutes?: number }
const typeLabel = (type: string) => type === 'private' ? 'Séance privée' : type === 'semi_private' ? 'Séance semi-privée' : 'Séance de groupe'

export function CreatePlayerDialog({ open, users, onClose, onCreated }: { open: boolean; users: UserWithPlayers[]; onClose: () => void; onCreated: () => void }) {
  const { t, language } = useI18n()
  const [firstName, setFirstName] = useState('')
  const [lastName, setLastName] = useState('')
  const [age, setAge] = useState('')
  const [gender, setGender] = useState<'female' | 'male' | 'woman' | 'man' | 'other'>('female')
  const [configurationId, setConfigurationId] = useState('')
  const [paymentMethod, setPaymentMethod] = useState<'cash' | 'card' | 'payment_link' | 'bank_transfer'>('cash')
  const [userId, setUserId] = useState('')
  const [configurations, setConfigurations] = useState<Configuration[]>([])
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')
  useEffect(() => {
    if (!open) return
    let active = true
    getPlayerCreationOptions().then(result => {
      if (!active) return
      setConfigurations(result.data.configurations.map(item => ({
        id: item.id, activityType: item.activityType, type: item.type,
        minAge: Number(item.minAge), maxAge: item.maximumAge === null ? Number(item.minAge) : Number(item.maximumAge),
        price: Number(item.price), currency: item.currency, sessionCount: Number(item.sessionCount),
        dayOfWeek: item.dayOfWeek ?? undefined, startTime: item.startTime ?? undefined, durationMinutes: item.durationMinutes ?? undefined,
      })))
    }).catch(reason => { if (active) setError(reason instanceof Error ? t(reason.message) : t('Une erreur est survenue')) })
    return () => { active = false }
  }, [open, t])
  const parsedAge = Number(age)
  const compatible = useMemo(() => configurations.filter(item => Number.isInteger(parsedAge) && parsedAge >= item.minAge && parsedAge <= item.maxAge), [configurations, parsedAge])
  const selectedConfigurationId = compatible.some(item => item.id === configurationId) ? configurationId : ''
  const selectedUser = users.find(user => user.id === userId) ?? null
  const submit = async () => {
    if (!firstName.trim() || !lastName.trim() || !Number.isInteger(parsedAge) || parsedAge < 3 || parsedAge > 80 || !selectedConfigurationId) { setError(t('Renseignez les informations du joueur et une séance compatible avec son âge.')); return }
    setSaving(true); setError('')
    try { await createPlayerForUser({ firstName: firstName.trim(), lastName: lastName.trim(), age: parsedAge, gender, sessionConfigurationId: selectedConfigurationId, paymentMethod, userId: userId || null }); onCreated() }
    catch (reason) { setError(reason instanceof Error ? t(reason.message) : t('Une erreur est survenue')) }
    finally { setSaving(false) }
  }
  return <Dialog open={open} onClose={saving ? undefined : onClose} fullWidth maxWidth="sm">
    <DialogTitle>{t('Créer un profil joueur')}</DialogTitle>
    <DialogContent><Stack gap={2} pt={1}>
      {error && <Alert severity="error">{error}</Alert>}
      <Stack direction={{ xs: 'column', sm: 'row' }} gap={1.5}><TextField fullWidth required label={t('Prénom')} value={firstName} onChange={event => setFirstName(event.target.value)} /><TextField fullWidth required label={t('Nom')} value={lastName} onChange={event => setLastName(event.target.value)} /></Stack>
      <Stack direction={{ xs: 'column', sm: 'row' }} gap={1.5}><TextField fullWidth required type="number" label={t('Âge')} value={age} inputProps={{ min: 3, max: 80 }} onChange={event => setAge(event.target.value)} /><FormControl fullWidth><InputLabel>{t('Sexe')}</InputLabel><Select label={t('Sexe')} value={gender} onChange={event => setGender(event.target.value as typeof gender)}><MenuItem value="female">{t('Fille')}</MenuItem><MenuItem value="male">{t('Garçon')}</MenuItem><MenuItem value="woman">{t('Femme')}</MenuItem><MenuItem value="man">{t('Homme')}</MenuItem><MenuItem value="other">{t('Autre')}</MenuItem></Select></FormControl></Stack>
      <FormControl fullWidth disabled={!Number.isInteger(parsedAge)}><InputLabel>{t('Créneau')}</InputLabel><Select label={t('Créneau')} value={selectedConfigurationId} onChange={event => setConfigurationId(event.target.value)}>{compatible.some(item => item.activityType === 'tennis') && <ListSubheader>{t('Tennis')}</ListSubheader>}{compatible.filter(item => item.activityType === 'tennis').map(item => <MenuItem key={item.id} value={item.id}>{`${t('Tennis session')} · ${t(typeLabel(item.type))} · ${item.minAge === item.maxAge ? item.minAge : `${item.minAge}–${item.maxAge}`} ${t('ans')} · ${item.sessionCount} ${t('séances')} · ${formatMoney(item.price, item.currency, language)}`}</MenuItem>)}{compatible.some(item => item.activityType === 'padel') && <ListSubheader>{t('Paddle')}</ListSubheader>}{compatible.filter(item => item.activityType === 'padel').map(item => <MenuItem key={item.id} value={item.id}>{`${t('Paddle')} · ${item.durationMinutes ?? 90} ${t('minutes')} · ${formatMoney(item.price, item.currency, language)}`}</MenuItem>)}</Select></FormControl>
      {Number.isInteger(parsedAge) && !compatible.length && <Alert severity="warning">{t('Aucune configuration active ne correspond à l’âge de ce joueur.')}</Alert>}
      <FormControl fullWidth><InputLabel>{t('Mode de paiement')}</InputLabel><Select label={t('Mode de paiement')} value={paymentMethod} onChange={event => setPaymentMethod(event.target.value as typeof paymentMethod)}><MenuItem value="cash">{t('Cash')}</MenuItem><MenuItem value="card">{t('Carte bancaire')}</MenuItem><MenuItem value="payment_link">{t('Lien de paiement')}</MenuItem><MenuItem value="bank_transfer">{t('Virement bancaire')}</MenuItem></Select></FormControl>
      <Autocomplete options={users.filter(user => user.status === 'active')} value={selectedUser} getOptionLabel={user => `${user.name} · ${user.email}`} isOptionEqualToValue={(option, value) => option.id === value.id} onChange={(_, value) => setUserId(value?.id ?? '')} renderInput={params => <TextField {...params} label={t('Attribuer à un utilisateur (facultatif)')} helperText={t('Vous pourrez également attribuer le joueur plus tard.')} />} />
      {paymentMethod === 'cash' && <Alert severity="info">{t('Le profil restera en attente jusqu’à la confirmation du paiement cash.')}</Alert>}
    </Stack></DialogContent>
    <DialogActions sx={{ p: 3 }}><Button onClick={onClose} disabled={saving}>{t('Annuler')}</Button><Button variant="contained" onClick={submit} disabled={saving}>{saving ? <CircularProgress size={18} color="inherit" /> : t('Créer le joueur')}</Button></DialogActions>
  </Dialog>
}
