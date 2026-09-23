import { useEffect, useMemo, useState } from 'react'
import { AddRounded, DeleteOutlineRounded, EditRounded, SaveRounded } from '@mui/icons-material'
import { Alert, Box, Button, Card, CardContent, CircularProgress, Dialog, DialogActions, DialogContent, DialogTitle, FormControl, IconButton, InputAdornment, InputLabel, MenuItem, Select, Stack, TextField, Tooltip, Typography } from '@mui/material'
import { collection, onSnapshot, query, where } from 'firebase/firestore'
import { db } from '../firebase'
import { deletePadelSlotTemplate, upsertPadelSlotTemplate, type SessionCurrency } from '../services/managementService'
import { formatMoney, useI18n } from '../i18n'

interface PadelSlotTemplate {
  id: string
  durationMinutes: number
  price: number
  currency: SessionCurrency
}

const currencies: SessionCurrency[] = ['AED', 'XAF', 'EUR', 'USD', 'MAD']
const emptyForm = { durationMinutes: 90, price: 0, currency: 'AED' as SessionCurrency }

export function PadelSlotPlanner({ academyId, notify }: { academyId: string; notify: (message: string) => void }) {
  const { t, language } = useI18n()
  const [templates, setTemplates] = useState<PadelSlotTemplate[]>([])
  const [open, setOpen] = useState(false)
  const [editingId, setEditingId] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')
  const [form, setForm] = useState(emptyForm)

  useEffect(() => {
    if (!academyId) return
    return onSnapshot(query(collection(db, 'padelSlotTemplates'), where('academyId', '==', academyId)), snapshot => {
      setTemplates(snapshot.docs
        .filter(document => document.get('active') === true)
        .map(document => ({
          id: document.id,
          durationMinutes: Number(document.get('durationMinutes')),
          price: Number(document.get('price')),
          currency: (document.get('currency') ?? 'AED') as SessionCurrency,
        }))
        .sort((a, b) => a.durationMinutes - b.durationMinutes))
    }, () => setError(t('Impossible de charger les créneaux Paddle.')))
  }, [academyId, t])

  const close = () => {
    if (loading) return
    setOpen(false); setEditingId(null); setForm(emptyForm); setError('')
  }
  const create = () => { setEditingId(null); setForm(emptyForm); setError(''); setOpen(true) }
  const edit = (template: PadelSlotTemplate) => {
    setEditingId(template.id)
    setForm({ durationMinutes: template.durationMinutes, price: template.price, currency: template.currency })
    setError(''); setOpen(true)
  }
  const valid = useMemo(() => Number.isInteger(form.durationMinutes) && form.durationMinutes >= 15 && form.durationMinutes <= 480 && Number.isInteger(form.price) && form.price >= 0, [form])
  const submit = async () => {
    if (!valid) { setError(t('Vérifiez la durée et le montant.')); return }
    setLoading(true); setError('')
    try {
      await upsertPadelSlotTemplate({ ...(editingId ? { templateId: editingId } : {}), academyId, ...form })
      notify(t(editingId ? 'Créneau Paddle modifié' : 'Créneau Paddle ajouté'))
      setOpen(false); setEditingId(null); setForm(emptyForm)
    } catch (reason) { setError(reason instanceof Error ? t(reason.message) : t('Une erreur est survenue')) } finally { setLoading(false) }
  }
  const remove = async (template: PadelSlotTemplate) => {
    if (!window.confirm(t('Supprimer ce créneau Paddle ?'))) return
    try { await deletePadelSlotTemplate(template.id); notify(t('Créneau Paddle supprimé')) }
    catch (reason) { notify(reason instanceof Error ? t(reason.message) : t('Une erreur est survenue')) }
  }

  return <Card><CardContent>
    <Stack direction={{ xs: 'column', sm: 'row' }} justifyContent="space-between" alignItems={{ sm: 'center' }} gap={2}>
      <Box><Typography variant="h6">{t('Créneaux Paddle')}</Typography><Typography color="text.secondary">{t('Configurez la durée et le montant de chaque créneau.')}</Typography></Box>
      <Button variant="contained" startIcon={<AddRounded />} onClick={create}>{t('Ajouter un créneau')}</Button>
    </Stack>
    <Stack gap={1.2} mt={2}>
      {error && !open && <Alert severity="error">{error}</Alert>}
      {!templates.length && <Alert severity="info">{t('Aucun créneau Paddle configuré.')}</Alert>}
      {templates.map(template => <Box key={template.id} sx={{ p: 2, border: '1px solid', borderColor: 'divider', borderRadius: 3 }}>
        <Stack direction={{ xs: 'column', sm: 'row' }} justifyContent="space-between" alignItems={{ sm: 'center' }} gap={1.5}>
          <Box><Typography fontWeight={800}>{template.durationMinutes} {t('minutes')}</Typography><Typography variant="body2" color="text.secondary">{formatMoney(template.price, template.currency, language)}</Typography></Box>
          <Stack direction="row"><Tooltip title={t('Modifier')}><IconButton onClick={() => edit(template)} aria-label={t('Modifier')}><EditRounded /></IconButton></Tooltip><Tooltip title={t('Supprimer')}><IconButton color="error" onClick={() => remove(template)} aria-label={t('Supprimer')}><DeleteOutlineRounded /></IconButton></Tooltip></Stack>
        </Stack>
      </Box>)}
    </Stack>
    <Dialog open={open} onClose={close} fullWidth maxWidth="sm"><DialogTitle>{t(editingId ? 'Modifier le créneau Paddle' : 'Nouveau créneau Paddle')}</DialogTitle><DialogContent><Stack gap={2} pt={1}>
      {error && <Alert severity="error">{error}</Alert>}
      <TextField fullWidth type="number" label={t('Durée')} value={form.durationMinutes} inputProps={{ min: 15, max: 480, step: 5 }} InputProps={{ endAdornment: <InputAdornment position="end">{t('minutes')}</InputAdornment> }} onChange={event => setForm({ ...form, durationMinutes: Number(event.target.value) })} />
      <Stack direction={{ xs: 'column', sm: 'row' }} gap={1.5}><TextField fullWidth type="number" label={t('Montant')} value={form.price} inputProps={{ min: 0, max: 100000000, step: 1 }} onChange={event => setForm({ ...form, price: Number(event.target.value) })} /><FormControl sx={{ minWidth: 130 }}><InputLabel>{t('Devise')}</InputLabel><Select value={form.currency} label={t('Devise')} onChange={event => setForm({ ...form, currency: event.target.value as SessionCurrency })}>{currencies.map(currency => <MenuItem value={currency} key={currency}>{currency}</MenuItem>)}</Select></FormControl></Stack>
    </Stack></DialogContent><DialogActions sx={{ p: 3 }}><Button onClick={close} disabled={loading}>{t('Annuler')}</Button><Button variant="contained" onClick={submit} disabled={loading} startIcon={loading ? <CircularProgress color="inherit" size={18} /> : <SaveRounded />}>{t('Enregistrer')}</Button></DialogActions></Dialog>
  </CardContent></Card>
}
