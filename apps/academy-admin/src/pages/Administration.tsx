import { useEffect, useMemo, useState } from 'react'
import { Alert, Box, Button, Card, CardContent, Chip, CircularProgress, Dialog, DialogActions, DialogContent, DialogTitle, FormControl, InputLabel, MenuItem, Select, Stack, TextField, Typography } from '@mui/material'
import { AddRounded, AdminPanelSettingsRounded } from '@mui/icons-material'
import { collection, onSnapshot, query, where } from 'firebase/firestore'
import { db } from '../firebase'
import { createAdministrator, updateAdministratorAccess, type AdminRole } from '../services/managementService'
import { useI18n } from '../i18n'
import { matchesSearch } from '../utils/search'
import { NotificationDeliveries } from '../components/NotificationDeliveries'

interface AdminRow { uid: string; email: string; displayName: string; role: string; status: string; academyIds: string[] }
const roles: AdminRole[] = ['admin', 'academy_manager', 'booking_manager']
const administrativeRoles = new Set(['root', ...roles])

export function Administration({ notify, searchQuery = '' }: { notify: (message: string) => void; searchQuery?: string }) {
  const { t } = useI18n()
  const [admins, setAdmins] = useState<AdminRow[]>([])
  const [open, setOpen] = useState(false)
  const [editing, setEditing] = useState<AdminRow | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')
  const [resetLink, setResetLink] = useState('')
  const [form, setForm] = useState<Record<string, string>>({})

  useEffect(() => onSnapshot(query(collection(db, 'users'), where('role', 'in', [...administrativeRoles])), snap => setAdmins(snap.docs.map(item => ({ uid: item.id, ...item.data() } as AdminRow)).sort((a, b) => (a.displayName ?? '').localeCompare(b.displayName ?? '')))), [])
  const value = (key: string) => form[key] ?? ''
  const setValue = (key: string, next: string) => setForm(current => ({ ...current, [key]: next }))
  const academyIds = () => value('academyIds').split(',').map(item => item.trim()).filter(Boolean)
  const closeDialog = () => {
    if (document.activeElement instanceof HTMLElement) document.activeElement.blur()
    setOpen(false)
  }
  const startCreate = () => { setEditing(null); setForm({ role: 'academy_manager', status: 'active' }); setError(''); setResetLink(''); setOpen(true) }
  const startEdit = (admin: AdminRow) => { setEditing(admin); setForm({ role: admin.role, status: admin.status, academyIds: admin.academyIds?.join(', ') ?? '' }); setError(''); setResetLink(''); setOpen(true) }

  const submit = async () => {
    setLoading(true); setError('')
    try {
      if (editing) {
        await updateAdministratorAccess({ uid: editing.uid, role: value('role') as AdminRole, status: value('status') as 'active' | 'suspended', academyIds: academyIds() })
        notify(t('Accès administrateur mis à jour')); closeDialog()
      } else {
        const result = await createAdministrator({ email: value('email'), displayName: value('displayName'), role: value('role') as AdminRole, academyIds: academyIds() })
        setResetLink(result.data.resetLink); notify(t(result.data.emailStatus === 'queued' ? 'Administrateur créé, invitation en attente d’envoi' : 'Administrateur créé'))
      }
    } catch (reason) {
      const message = reason instanceof Error ? reason.message : ''
      setError(message === 'internal' || message.includes('functions/internal') || message.includes('Failed to fetch')
        ? t('Le service de gestion des administrateurs n’est pas disponible. Déployez les Cloud Functions.')
        : message ? t(message) : t('Une erreur est survenue'))
    }
    finally { setLoading(false) }
  }

  const visibleAdmins = useMemo(() => admins.filter(admin => matchesSearch(searchQuery, admin.uid, admin.displayName, admin.email, admin.role, admin.status, admin.academyIds)), [admins, searchQuery])
  return <Stack gap={2.5}>
    <Card><CardContent><Stack direction={{ xs: 'column', sm: 'row' }} alignItems={{ sm: 'center' }} justifyContent="space-between" gap={2}>
      <Stack direction="row" gap={2} alignItems="center"><AdminPanelSettingsRounded fontSize="large" /><Box><Typography variant="h5">{t('Administrateurs')}</Typography><Typography color="text.secondary">{t('Créez les comptes administrateurs et contrôlez leurs accès.')}</Typography></Box></Stack>
      <Button variant="contained" startIcon={<AddRounded />} onClick={startCreate}>{t('Nouvel administrateur')}</Button>
    </Stack></CardContent></Card>
    {visibleAdmins.map(admin => <Card key={admin.uid}><CardContent><Stack direction={{ xs: 'column', sm: 'row' }} alignItems={{ sm: 'center' }} gap={2}>
      <Box flex={1}><Typography fontWeight={850}>{admin.displayName}</Typography><Typography variant="body2" color="text.secondary">{admin.email}</Typography></Box>
      <Chip label={t(admin.role)} /><Chip color={admin.status === 'active' ? 'success' : 'default'} label={t(admin.status === 'active' ? 'Actif' : 'Suspendu')} />
      {admin.role !== 'root' && <Button variant="outlined" onClick={() => startEdit(admin)}>{t('Modifier les accès')}</Button>}
    </Stack></CardContent></Card>)}
    <NotificationDeliveries />
    <Dialog open={open} onClose={() => !loading && closeDialog()} fullWidth maxWidth="sm"><DialogTitle>{t(editing ? 'Modifier les accès' : 'Nouvel administrateur')}</DialogTitle><DialogContent><Stack gap={2} pt={1}>
      {error && <Alert severity="error">{error}</Alert>}
      {resetLink && <Alert severity="success"><Typography fontWeight={800}>{t('Compte créé')}</Typography><Typography variant="body2" sx={{ wordBreak: 'break-all' }}>{t('Lien de définition du mot de passe')} : {resetLink}</Typography></Alert>}
      {!editing && <><TextField label={t('Nom complet')} value={value('displayName')} onChange={e => setValue('displayName', e.target.value)} /><TextField label={t('Adresse e-mail')} type="email" value={value('email')} onChange={e => setValue('email', e.target.value)} /></>}
      <FormControl><InputLabel>{t('Rôle')}</InputLabel><Select label={t('Rôle')} value={value('role')} onChange={e => setValue('role', e.target.value)}>{roles.map(role => <MenuItem value={role} key={role}>{t(role)}</MenuItem>)}</Select></FormControl>
      {editing && <FormControl><InputLabel>{t('Statut')}</InputLabel><Select label={t('Statut')} value={value('status')} onChange={e => setValue('status', e.target.value)}><MenuItem value="active">{t('Actif')}</MenuItem><MenuItem value="suspended">{t('Suspendu')}</MenuItem></Select></FormControl>}
      <TextField label={t('Académies (facultatif)')} placeholder={t('IDs académies, séparés par des virgules')} helperText={t('Vous pourrez rattacher cet administrateur à une académie plus tard.')} value={value('academyIds')} onChange={e => setValue('academyIds', e.target.value)} />
    </Stack></DialogContent><DialogActions sx={{ p: 3 }}><Button disabled={loading} onClick={closeDialog}>{t('Fermer')}</Button>{!resetLink && <Button variant="contained" disabled={loading} onClick={submit}>{loading ? <CircularProgress size={20} color="inherit" /> : t('Confirmer')}</Button>}</DialogActions></Dialog>
  </Stack>
}
