import { useEffect, useMemo, useState } from 'react'
import { Alert, Box, Button, Card, CardContent, CircularProgress, Dialog, DialogActions, DialogContent, DialogTitle, FormControl, InputLabel, MenuItem, Select, Stack, TextField, Typography } from '@mui/material'
import { AddRounded, StadiumRounded } from '@mui/icons-material'
import { collection, onSnapshot, orderBy, query } from 'firebase/firestore'
import { db } from '../firebase'
import { createStadium } from '../services/managementService'
import { useI18n } from '../i18n'
import { matchesSearch } from '../utils/search'

interface Academy { id: string; name: string }
interface Stadium { id: string; name: string; address: string; courtCount: number; academyId: string }
export function Stadiums({ notify, searchQuery = '' }: { notify: (message: string) => void; searchQuery?: string }) {
  const { t } = useI18n(); const [rows, setRows] = useState<Stadium[]>([]); const [academies, setAcademies] = useState<Academy[]>([]); const [open, setOpen] = useState(false); const [loading, setLoading] = useState(false); const [error, setError] = useState(''); const [form, setForm] = useState({ academyId: '', name: '', address: '', courtCount: 1 })
  useEffect(() => { const a = onSnapshot(query(collection(db, 'stadiums'), orderBy('name')), snap => setRows(snap.docs.map(item => ({ id: item.id, ...item.data() } as Stadium)))); const b = onSnapshot(query(collection(db, 'academies'), orderBy('name')), snap => setAcademies(snap.docs.map(item => ({ id: item.id, ...item.data() } as Academy)))); return () => { a(); b() } }, [])
  const submit = async () => { setLoading(true); setError(''); try { await createStadium(form); notify(t('Stade créé')); setOpen(false) } catch (reason) { setError(reason instanceof Error ? t(reason.message) : t('Une erreur est survenue')) } finally { setLoading(false) } }
  const visibleRows = useMemo(() => rows.filter(row => matchesSearch(searchQuery, row.id, row.name, row.address, row.courtCount, academies.find(item => item.id === row.academyId)?.name)), [academies, rows, searchQuery])
  return <Stack gap={2.5}><Card><CardContent><Stack direction={{ xs: 'column', sm: 'row' }} justifyContent="space-between" alignItems={{ sm: 'center' }} gap={2}><Box><Typography variant="h5">{t('Stades')}</Typography><Typography color="text.secondary">{t('Gérez les sites sportifs et leurs terrains.')}</Typography></Box><Button variant="contained" startIcon={<AddRounded />} onClick={() => setOpen(true)}>{t('Nouveau stade')}</Button></Stack></CardContent></Card>
    <Box sx={{ display: 'grid', gridTemplateColumns: { xs: '1fr', md: 'repeat(2,1fr)', xl: 'repeat(3,1fr)' }, gap: 2 }}>{visibleRows.map(row => <Card key={row.id}><CardContent><StadiumRounded /><Typography variant="h6" mt={2}>{row.name}</Typography><Typography color="text.secondary" variant="body2">{row.address}</Typography><Typography mt={1} fontWeight={800}>{row.courtCount} {t('terrains')}</Typography></CardContent></Card>)}</Box>
    <Dialog open={open} onClose={() => setOpen(false)} fullWidth maxWidth="sm"><DialogTitle>{t('Nouveau stade')}</DialogTitle><DialogContent><Stack gap={2} pt={1}>{error && <Alert severity="error">{error}</Alert>}<FormControl><InputLabel>{t('Académie')}</InputLabel><Select label={t('Académie')} value={form.academyId} onChange={e => setForm({ ...form, academyId: e.target.value })}>{academies.map(a => <MenuItem key={a.id} value={a.id}>{a.name}</MenuItem>)}</Select></FormControl><TextField label={t('Nom du stade')} value={form.name} onChange={e => setForm({ ...form, name: e.target.value })} /><TextField label={t('Adresse')} value={form.address} onChange={e => setForm({ ...form, address: e.target.value })} /><TextField type="number" label={t('Nombre de terrains')} value={form.courtCount} onChange={e => setForm({ ...form, courtCount: Number(e.target.value) })} /></Stack></DialogContent><DialogActions sx={{ p: 3 }}><Button onClick={() => setOpen(false)}>{t('Annuler')}</Button><Button variant="contained" disabled={loading || !form.academyId || !form.name} onClick={submit}>{loading ? <CircularProgress size={20} /> : t('Créer')}</Button></DialogActions></Dialog>
  </Stack>
}
