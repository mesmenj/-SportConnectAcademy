import { useEffect, useMemo, useState } from 'react'
import { Alert, Avatar, Box, Button, Card, CardContent, Chip, CircularProgress, Dialog, DialogActions, DialogContent, DialogTitle, FormControl, IconButton, InputLabel, Menu, MenuItem, Select, Stack, TextField, Typography } from '@mui/material'
import { AddRounded, ContentCopyRounded, DeleteOutlineRounded, MoreVertRounded, SendRounded } from '@mui/icons-material'
import { collection, onSnapshot, orderBy, query } from 'firebase/firestore'
import { db } from '../firebase'
import { createCoach, deleteCoach, resendCoachPasswordLink } from '../services/managementService'
import { colors } from '../theme'
import { useI18n } from '../i18n'
import { matchesSearch } from '../utils/search'

interface Coach { id: string; academyId: string; displayName: string; email: string; specialties: string[]; status: string }
interface Academy { id: string; name: string }

export function Coaches({ notify, searchQuery = '' }: { notify: (message: string) => void; searchQuery?: string }) {
  const { t } = useI18n()
  const [rows, setRows] = useState<Coach[]>([])
  const [academies, setAcademies] = useState<Academy[]>([])
  const [open, setOpen] = useState(false)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')
  const [resetLink, setResetLink] = useState('')
  const [linkCoach, setLinkCoach] = useState<Coach | null>(null)
  const [coachToDelete, setCoachToDelete] = useState<Coach | null>(null)
  const [menuAnchor, setMenuAnchor] = useState<HTMLElement | null>(null)
  const [menuCoach, setMenuCoach] = useState<Coach | null>(null)
  const [form, setForm] = useState({ academyId: '', displayName: '', email: '', specialties: '' })

  useEffect(() => {
    const stopCoaches = onSnapshot(query(collection(db, 'coaches'), orderBy('displayName')), snap => setRows(snap.docs.map(item => ({ id: item.id, ...item.data() } as Coach))))
    const stopAcademies = onSnapshot(query(collection(db, 'academies'), orderBy('name')), snap => setAcademies(snap.docs.map(item => ({ id: item.id, ...item.data() } as Academy))))
    return () => { stopCoaches(); stopAcademies() }
  }, [])

  const submit = async () => {
    setLoading(true); setError(''); setResetLink('')
    try {
      const result = await createCoach({ academyId: form.academyId, displayName: form.displayName, email: form.email, specialties: form.specialties.split(',').map(item => item.trim()).filter(Boolean) })
      setResetLink(result.data.resetLink); notify(t(result.data.emailStatus === 'queued' ? 'Coach créé, invitation en attente d’envoi' : result.data.emailStatus === 'sent' ? 'Coach créé et invitation envoyée' : 'Coach créé, mais l’envoi de l’invitation a échoué'))
    } catch (reason) { setError(reason instanceof Error ? t(reason.message) : t('Une erreur est survenue')) }
    finally { setLoading(false) }
  }

  const resendLink = async (coach: Coach) => {
    setMenuAnchor(null); setLinkCoach(coach); setResetLink(''); setError(''); setLoading(true)
    try {
      const result = await resendCoachPasswordLink(coach.id)
      setResetLink(result.data.resetLink); notify(t(result.data.emailStatus === 'queued' ? 'Invitation en attente d’envoi' : result.data.emailStatus === 'sent' ? 'Nouveau lien généré et envoyé' : 'Nouveau lien généré, mais l’envoi a échoué'))
    } catch (reason) { setError(reason instanceof Error ? t(reason.message) : t('Une erreur est survenue')) }
    finally { setLoading(false) }
  }

  const confirmDelete = async () => {
    if (!coachToDelete) return
    setLoading(true); setError('')
    try {
      await deleteCoach(coachToDelete.id)
      setCoachToDelete(null); notify(t('Coach supprimé'))
    } catch (reason) { setError(reason instanceof Error ? t(reason.message) : t('Une erreur est survenue')) }
    finally { setLoading(false) }
  }

  const visibleRows = useMemo(() => rows.filter(coach => matchesSearch(searchQuery, coach.id, coach.displayName, coach.email, coach.specialties, coach.status, academies.find(item => item.id === coach.academyId)?.name)), [academies, rows, searchQuery])
  const closeLinkDialog = () => { if (!loading) { setLinkCoach(null); setResetLink(''); setError('') } }

  return <Stack gap={2.5}>
    <Card><CardContent><Stack direction={{ xs: 'column', sm: 'row' }} justifyContent="space-between" alignItems={{ sm: 'center' }} gap={2}><Box><Typography variant="h5">{t('Équipe des coachs')}</Typography><Typography color="text.secondary">{t('Créez les coachs et rattachez-les à leur académie.')}</Typography></Box><Button variant="contained" startIcon={<AddRounded />} onClick={() => { setResetLink(''); setError(''); setOpen(true) }}>{t('Nouveau coach')}</Button></Stack></CardContent></Card>
    <Box sx={{ display: 'grid', gridTemplateColumns: { xs: '1fr', sm: 'repeat(2,1fr)', xl: 'repeat(4,1fr)' }, gap: 2 }}>{visibleRows.map((coach, index) => <Card key={coach.id}><CardContent><Stack direction="row" justifyContent="space-between"><Avatar sx={{ width: 54, height: 54, bgcolor: [colors.blue, colors.lilac, colors.green, colors.orange][index % 4], fontWeight: 800 }}>{coach.displayName.split(/\s+/).slice(0,2).map(p => p[0]).join('')}</Avatar><Stack direction="row" alignItems="flex-start"><Chip size="small" label={t(coach.status === 'active' ? 'Actif' : 'Suspendu')} color={coach.status === 'active' ? 'success' : 'default'} /><IconButton aria-label={t('Actions du coach')} onClick={event => { setMenuAnchor(event.currentTarget); setMenuCoach(coach) }}><MoreVertRounded /></IconButton></Stack></Stack><Typography variant="h6" mt={2}>{coach.displayName}</Typography><Typography variant="body2" color="text.secondary">{coach.email}</Typography><Stack direction="row" gap={.7} flexWrap="wrap" mt={2}>{coach.specialties?.map(item => <Chip size="small" key={item} label={t(item)} />)}</Stack></CardContent></Card>)}</Box>

    <Menu anchorEl={menuAnchor} open={Boolean(menuAnchor)} onClose={() => setMenuAnchor(null)}><MenuItem onClick={() => menuCoach && resendLink(menuCoach)}><SendRounded fontSize="small" sx={{ mr: 1.5 }} />{t('Renvoyer le lien de mot de passe')}</MenuItem><MenuItem sx={{ color: 'error.main' }} onClick={() => { setCoachToDelete(menuCoach); setMenuAnchor(null); setError('') }}><DeleteOutlineRounded fontSize="small" sx={{ mr: 1.5 }} />{t('Supprimer le coach')}</MenuItem></Menu>

    <Dialog open={open} onClose={() => !loading && setOpen(false)} fullWidth maxWidth="sm"><DialogTitle>{t('Nouveau coach')}</DialogTitle><DialogContent><Stack gap={2} pt={1}>{error && <Alert severity="error">{error}</Alert>}{resetLink ? <><Alert severity="success">{t('Compte coach créé. Le lien reste disponible pour un partage manuel si nécessaire.')}</Alert><TextField value={resetLink} label={t('Lien de création du mot de passe')} multiline minRows={3} slotProps={{ input: { readOnly: true } }} /><Button startIcon={<ContentCopyRounded />} onClick={() => navigator.clipboard.writeText(resetLink)}>{t('Copier le lien')}</Button></> : <><FormControl><InputLabel>{t('Académie')}</InputLabel><Select label={t('Académie')} value={form.academyId} onChange={e => setForm({ ...form, academyId: e.target.value })}>{academies.map(a => <MenuItem key={a.id} value={a.id}>{a.name}</MenuItem>)}</Select></FormControl><TextField label={t('Nom complet')} value={form.displayName} onChange={e => setForm({ ...form, displayName: e.target.value })} /><TextField type="email" label={t('Adresse e-mail')} value={form.email} onChange={e => setForm({ ...form, email: e.target.value })} /><TextField label={t('Spécialités, séparées par des virgules')} value={form.specialties} onChange={e => setForm({ ...form, specialties: e.target.value })} /></>}</Stack></DialogContent><DialogActions sx={{ p: 3 }}><Button onClick={() => setOpen(false)} disabled={loading}>{t(resetLink ? 'Fermer' : 'Annuler')}</Button>{!resetLink && <Button variant="contained" disabled={loading || !form.academyId || !form.displayName || !form.email} onClick={submit}>{loading ? <CircularProgress size={20} /> : t('Créer')}</Button>}</DialogActions></Dialog>

    <Dialog open={Boolean(linkCoach)} onClose={closeLinkDialog} fullWidth maxWidth="sm"><DialogTitle>{t('Lien de mot de passe')}</DialogTitle><DialogContent><Stack gap={2} pt={1}>{error && <Alert severity="error">{error}</Alert>}{loading && <Box textAlign="center"><CircularProgress /></Box>}{resetLink && <><Alert severity="success">{t('Un nouveau lien a été généré. Il reste disponible pour un partage manuel si nécessaire.')}</Alert><TextField value={resetLink} label={t('Nouveau lien de mot de passe')} multiline minRows={3} slotProps={{ input: { readOnly: true } }} /><Button startIcon={<ContentCopyRounded />} onClick={() => navigator.clipboard.writeText(resetLink)}>{t('Copier le lien')}</Button></>}</Stack></DialogContent><DialogActions sx={{ p: 3 }}><Button onClick={closeLinkDialog} disabled={loading}>{t('Fermer')}</Button>{error && <Button onClick={() => linkCoach && resendLink(linkCoach)} disabled={loading}>{t('Réessayer')}</Button>}</DialogActions></Dialog>

    <Dialog open={Boolean(coachToDelete)} onClose={() => !loading && setCoachToDelete(null)} maxWidth="xs" fullWidth><DialogTitle>{t('Supprimer le coach ?')}</DialogTitle><DialogContent><Stack gap={2} pt={1}>{error && <Alert severity="error">{error}</Alert>}<Typography>{t('Le compte de')} <strong>{coachToDelete?.displayName}</strong> {t('sera définitivement supprimé. Cette action est irréversible.')}</Typography><Alert severity="warning">{t('La suppression sera refusée si ce coach possède encore une séance future.')}</Alert></Stack></DialogContent><DialogActions sx={{ p: 3 }}><Button onClick={() => setCoachToDelete(null)} disabled={loading}>{t('Annuler')}</Button><Button color="error" variant="contained" onClick={confirmDelete} disabled={loading}>{loading ? <CircularProgress size={20} color="inherit" /> : t('Supprimer')}</Button></DialogActions></Dialog>
  </Stack>
}
