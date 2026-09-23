import { useState } from 'react'
import { Alert, Avatar, Button, Card, CardContent, CircularProgress, FormControl, InputLabel, MenuItem, Select, Stack, TextField, Typography } from '@mui/material'
import { SaveRounded } from '@mui/icons-material'
import { useAppSelector } from '../store/hooks'
import { updateMyProfile } from '../services/managementService'
import { useI18n, type Language } from '../i18n'
import { colors } from '../theme'

export function Profile({ notify }: { notify: (message: string) => void }) {
  const admin = useAppSelector(state => state.auth.user)
  const { language, setLanguage, t } = useI18n()
  const [displayName, setDisplayName] = useState(admin?.name ?? '')
  const [phone, setPhone] = useState(admin?.phone ?? '')
  const [preferredLanguage, setPreferredLanguage] = useState<Language>(admin?.preferredLanguage ?? language)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')
  const save = async () => { setLoading(true); setError(''); try { await updateMyProfile({ displayName, phone, preferredLanguage }); setLanguage(preferredLanguage); notify(t('Profil mis à jour')) } catch (reason) { setError(reason instanceof Error ? t(reason.message) : t('Une erreur est survenue')) } finally { setLoading(false) } }
  return <Stack gap={2.5} maxWidth={760}>
    <Card><CardContent><Stack direction="row" gap={2} alignItems="center"><Avatar sx={{ width: 72, height: 72, bgcolor: colors.lilac, fontSize: 22, fontWeight: 900 }}>{admin?.initials}</Avatar><Stack><Typography variant="h5">{admin?.name}</Typography><Typography color="text.secondary">{admin?.email}</Typography><Typography variant="caption" color="text.secondary">{admin?.role ? t(admin.role) : ''}</Typography></Stack></Stack></CardContent></Card>
    <Card><CardContent><Stack gap={2.5}><Typography variant="h6">{t('Informations personnelles')}</Typography>{error && <Alert severity="error">{error}</Alert>}<TextField label={t('Nom d’utilisateur')} value={displayName} onChange={e => setDisplayName(e.target.value)} /><TextField label={t('Adresse e-mail')} value={admin?.email ?? ''} disabled helperText={t('L’adresse e-mail est gérée par Firebase Authentication.')} /><TextField label={t('Téléphone')} value={phone} onChange={e => setPhone(e.target.value)} /><FormControl><InputLabel>{t('Langue préférée')}</InputLabel><Select label={t('Langue préférée')} value={preferredLanguage} onChange={e => setPreferredLanguage(e.target.value as Language)}><MenuItem value="fr">Français</MenuItem><MenuItem value="en">English</MenuItem></Select></FormControl><Button variant="contained" startIcon={loading ? <CircularProgress size={18} color="inherit" /> : <SaveRounded />} disabled={loading || !displayName.trim()} onClick={save} sx={{ alignSelf: 'flex-start' }}>{t('Enregistrer les modifications')}</Button></Stack></CardContent></Card>
  </Stack>
}
