import { useEffect, useMemo, useState, type ChangeEvent } from 'react'
import { AddRounded, DeleteRounded, EditRounded, EmojiEventsRounded, ImageRounded } from '@mui/icons-material'
import { Alert, Avatar, Box, Button, Card, CardContent, Chip, CircularProgress, Dialog, DialogActions, DialogContent, DialogTitle, FormControl, IconButton, InputLabel, LinearProgress, MenuItem, Select, Stack, TextField, Tooltip, Typography } from '@mui/material'
import { collection, onSnapshot, orderBy, query, type Timestamp } from 'firebase/firestore'
import { db } from '../firebase'
import { createTournament, softDeleteTournament, updateTournament } from '../services/managementService'
import { colors } from '../theme'
import { useI18n } from '../i18n'
import { matchesSearch } from '../utils/search'

interface Tournament { id: string; academyId: string | null; name: string; venue: string; category: string; description: string; startsAt: Timestamp; capacity: number; registeredCount: number; status: string; imageUrl: string | null; isDelete?: boolean }
interface Academy { id: string; name: string }
const emptyForm = { academyId: '', name: '', venue: '', category: '', description: '', startsAt: '', capacity: '16', imageDataUrl: null as string | null }

export function Tournaments({ notify, searchQuery = '' }: { notify: (message: string) => void; searchQuery?: string }) {
  const { t, language } = useI18n()
  const [rows, setRows] = useState<Tournament[]>([])
  const [academies, setAcademies] = useState<Academy[]>([])
  const [open, setOpen] = useState(false)
  const [editing, setEditing] = useState<Tournament | null>(null)
  const [currentImageUrl, setCurrentImageUrl] = useState<string | null>(null)
  const [deletingId, setDeletingId] = useState<string | null>(null)
  const [form, setForm] = useState(emptyForm)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')
  useEffect(() => {
    const stopTournaments = onSnapshot(query(collection(db, 'tournaments'), orderBy('startsAt')), snapshot => setRows(snapshot.docs.map(document => ({ id: document.id, ...document.data() } as Tournament)).filter(item => item.isDelete !== true)))
    const stopAcademies = onSnapshot(query(collection(db, 'academies'), orderBy('name')), snapshot => { const items = snapshot.docs.map(document => ({ id: document.id, name: document.get('name') || document.id })); setAcademies(items); setForm(current => ({ ...current, academyId: current.academyId || items[0]?.id || '' })) })
    return () => { stopTournaments(); stopAcademies() }
  }, [])
  const visibleRows = useMemo(() => rows.filter(item => matchesSearch(searchQuery, item.name, item.venue, item.category, item.description, item.status)), [rows, searchQuery])
  const selectImage = (event: ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0]
    if (!file) return
    if (!['image/png', 'image/jpeg', 'image/webp'].includes(file.type) || file.size > 2_000_000) { setError(t('Choisissez une image PNG, JPEG ou WebP de 2 Mo maximum.')); return }
    const reader = new FileReader(); reader.onload = () => setForm(current => ({ ...current, imageDataUrl: String(reader.result) })); reader.readAsDataURL(file)
  }
  const submit = async () => {
    const capacity = Number(form.capacity)
    if (!form.academyId || !form.name.trim() || !form.venue.trim() || !form.category.trim() || !form.startsAt || !Number.isInteger(capacity) || capacity < 2) { setError(t('Renseignez tous les champs obligatoires.')); return }
    setSaving(true); setError('')
    try {
      const input = { ...form, academyId: form.academyId, name: form.name.trim(), venue: form.venue.trim(), category: form.category.trim(), description: form.description.trim(), startsAt: new Date(form.startsAt).toISOString(), capacity }
      if (editing) {
        await updateTournament({ ...input, tournamentId: editing.id })
        notify(t('Tournoi modifié'))
      } else {
        await createTournament(input)
        notify(t('Tournoi créé'))
      }
      setOpen(false); setEditing(null); setCurrentImageUrl(null); setForm({ ...emptyForm, academyId: academies[0]?.id ?? '' })
    } catch (reason) { setError(reason instanceof Error ? t(reason.message) : t('Une erreur est survenue')) }
    finally { setSaving(false) }
  }
  const openCreate = () => { setEditing(null); setCurrentImageUrl(null); setForm({ ...emptyForm, academyId: academies[0]?.id ?? '' }); setError(''); setOpen(true) }
  const openEdit = (tournament: Tournament) => {
    const date = tournament.startsAt.toDate(); const localDate = new Date(date.getTime() - date.getTimezoneOffset() * 60_000).toISOString().slice(0, 16)
    setEditing(tournament); setCurrentImageUrl(tournament.imageUrl); setForm({ academyId: tournament.academyId ?? '', name: tournament.name, venue: tournament.venue, category: tournament.category, description: tournament.description, startsAt: localDate, capacity: String(tournament.capacity), imageDataUrl: null }); setError(''); setOpen(true)
  }
  const remove = async (tournament: Tournament) => {
    if (!window.confirm(t('Supprimer ce tournoi ?'))) return
    setDeletingId(tournament.id)
    try { await softDeleteTournament(tournament.id); notify(t('Tournoi supprimé')) }
    catch (reason) { notify(reason instanceof Error ? t(reason.message) : t('Une erreur est survenue')) }
    finally { setDeletingId(null) }
  }
  const formatDate = (value: Timestamp) => value?.toDate ? new Intl.DateTimeFormat(language === 'fr' ? 'fr-FR' : 'en-GB', { dateStyle: 'medium', timeStyle: 'short' }).format(value.toDate()) : '—'
  return <Stack gap={2}>
    <Card><CardContent><Stack direction={{ xs: 'column', sm: 'row' }} justifyContent="space-between" alignItems={{ sm: 'center' }} gap={2}><Box><Typography variant="h5">{t('Tournois')}</Typography><Typography color="text.secondary">{t('Créez et publiez les prochains tournois.')}</Typography></Box><Button variant="contained" startIcon={<AddRounded />} onClick={openCreate}>{t('Créer un tournoi')}</Button></Stack></CardContent></Card>
    {!visibleRows.length && <Alert severity="info">{t('Aucun tournoi publié.')}</Alert>}
    {visibleRows.map((tournament, index) => <Card key={tournament.id}><CardContent><Stack direction={{ xs: 'column', md: 'row' }} gap={2.5} alignItems={{ md: 'center' }}>
      <Avatar src={tournament.imageUrl ?? undefined} variant="rounded" sx={{ width: 100, height: 84, bgcolor: [`${colors.orange}20`, `${colors.sky}20`, `${colors.lilac}20`][index % 3], color: [colors.orange, colors.blue, colors.lilac][index % 3] }}>{!tournament.imageUrl && <EmojiEventsRounded fontSize="large" />}</Avatar>
      <Box flex={1}><Stack direction="row" gap={1} alignItems="center" flexWrap="wrap"><Typography variant="h6">{tournament.name}</Typography><Chip size="small" label={t(tournament.status === 'open' ? 'Inscriptions ouvertes' : tournament.status)} color={tournament.registeredCount >= tournament.capacity ? 'default' : 'success'} /></Stack><Typography variant="body2" color="text.secondary" mt={.5}>{formatDate(tournament.startsAt)} · {tournament.venue} · {tournament.category}</Typography>{tournament.description && <Typography variant="body2" mt={1}>{tournament.description}</Typography>}<Stack direction="row" alignItems="center" gap={1.5} mt={1.5} maxWidth={450}><LinearProgress variant="determinate" value={Math.min(100, tournament.registeredCount / tournament.capacity * 100)} sx={{ height: 8, borderRadius: 8, flex: 1 }} /><Typography variant="caption" fontWeight={800}>{tournament.registeredCount}/{tournament.capacity} {t('inscrits')}</Typography></Stack></Box>
      <Stack direction="row"><Tooltip title={t('Modifier')}><IconButton color="primary" onClick={() => openEdit(tournament)}><EditRounded /></IconButton></Tooltip><Tooltip title={t('Supprimer')}><span><IconButton color="error" disabled={deletingId === tournament.id} onClick={() => remove(tournament)}>{deletingId === tournament.id ? <CircularProgress size={20} /> : <DeleteRounded />}</IconButton></span></Tooltip></Stack>
    </Stack></CardContent></Card>)}
    <Dialog open={open} onClose={() => !saving && setOpen(false)} fullWidth maxWidth="sm"><DialogTitle>{t(editing ? 'Modifier le tournoi' : 'Créer un tournoi')}</DialogTitle><DialogContent><Stack gap={2} pt={1}>{error && <Alert severity="error">{error}</Alert>}<FormControl fullWidth><InputLabel>{t('Académie')}</InputLabel><Select disabled={Boolean(editing)} value={form.academyId} label={t('Académie')} onChange={event => setForm({ ...form, academyId: event.target.value })}>{academies.map(item => <MenuItem key={item.id} value={item.id}>{item.name}</MenuItem>)}</Select></FormControl><TextField required label={t('Nom du tournoi')} value={form.name} onChange={event => setForm({ ...form, name: event.target.value })} /><Stack direction={{ xs: 'column', sm: 'row' }} gap={1.5}><TextField fullWidth required type="datetime-local" label={t('Date et heure')} InputLabelProps={{ shrink: true }} value={form.startsAt} onChange={event => setForm({ ...form, startsAt: event.target.value })} /><TextField fullWidth required type="number" label={t('Capacité')} value={form.capacity} inputProps={{ min: 2, max: 10000 }} onChange={event => setForm({ ...form, capacity: event.target.value })} /></Stack><TextField required label={t('Lieu')} value={form.venue} onChange={event => setForm({ ...form, venue: event.target.value })} /><TextField required label={t('Catégorie')} value={form.category} onChange={event => setForm({ ...form, category: event.target.value })} /><TextField multiline minRows={3} label={t('Description facultative')} value={form.description} onChange={event => setForm({ ...form, description: event.target.value })} /><Button component="label" variant="outlined" startIcon={<ImageRounded />}>{t(form.imageDataUrl || currentImageUrl ? 'Changer l’image' : 'Ajouter une image')}<input hidden type="file" accept="image/png,image/jpeg,image/webp" onChange={selectImage} /></Button>{(form.imageDataUrl || currentImageUrl) && <Box component="img" src={form.imageDataUrl || currentImageUrl || ''} alt="" sx={{ width: '100%', height: 180, objectFit: 'cover', borderRadius: 3 }} />}</Stack></DialogContent><DialogActions sx={{ p: 3 }}><Button disabled={saving} onClick={() => setOpen(false)}>{t('Annuler')}</Button><Button variant="contained" disabled={saving} onClick={submit}>{saving ? <CircularProgress size={18} color="inherit" /> : t(editing ? 'Enregistrer' : 'Publier')}</Button></DialogActions></Dialog>
  </Stack>
}
