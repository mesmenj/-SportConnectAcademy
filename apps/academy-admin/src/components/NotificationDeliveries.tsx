import { useRef, useState } from 'react'
import { Alert, Box, Button, Card, CardContent, Chip, CircularProgress, MenuItem, Stack, TextField, Typography } from '@mui/material'
import { listNotificationDeliveries, retryNotificationDelivery, type NotificationDelivery } from '../services/managementService'
import { useAppSelector } from '../store/hooks'
import { localeFor, useI18n } from '../i18n'

const labels: Record<string, string> = {
  queued: 'En attente d’envoi', pending: 'Ancien envoi en attente', sending: 'Envoi en cours', retry: 'Nouvelle tentative programmée',
  accepted: 'Accepté par le service email', sent: 'Envoyé (ancien suivi)', delivered: 'Livré', deferred: 'Livraison différée',
  failed: 'Échec', unknown: 'Résultat à vérifier', bounced: 'Adresse rejetée', blocked: 'Email bloqué', complained: 'Signalé comme indésirable',
  skipped: 'Rappel devenu inutile',
}

export function NotificationDeliveries() {
  const { t, language } = useI18n()
  const admin = useAppSelector(state => state.auth.user)
  const [academyId, setAcademyId] = useState(admin?.role === 'root' ? '' : admin?.academyIds[0] ?? '')
  const [rows, setRows] = useState<NotificationDelivery[]>([])
  const [cursor, setCursor] = useState<string | null>(null)
  const [loaded, setLoaded] = useState(false)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')
  const generation = useRef(0)

  const load = async (append = false) => {
    const requestId = ++generation.current
    setLoading(true); setError('')
    try {
      const result = await listNotificationDeliveries({ academyId: academyId || undefined, beforeId: append ? cursor ?? undefined : undefined })
      if (generation.current !== requestId) return
      setRows(previous => append ? [...previous, ...result.data.deliveries] : result.data.deliveries)
      setCursor(result.data.nextCursor); setLoaded(true)
    } catch (reason) {
      if (generation.current === requestId) setError(reason instanceof Error ? t(reason.message) : t('Une erreur est survenue'))
    } finally { if (generation.current === requestId) setLoading(false) }
  }

  const retry = async (id: string) => {
    setLoading(true); setError('')
    try { await retryNotificationDelivery(id); await load() }
    catch (reason) { setError(reason instanceof Error ? t(reason.message) : t('Une erreur est survenue')); setLoading(false) }
  }

  return <Card><CardContent><Stack gap={2}>
    <Typography variant="h6">{t('Suivi des emails')}</Typography>
    <Typography color="text.secondary">{t('Consultez les livraisons et relancez les échecs récupérables.')}</Typography>
    <Stack direction={{ xs: 'column', sm: 'row' }} gap={1}>
      <TextField select label={t('Académie')} value={academyId} disabled={loading} sx={{ minWidth: 220 }} onChange={event => { ++generation.current; setAcademyId(event.target.value); setRows([]); setCursor(null); setLoaded(false); setError('') }}>
        {admin?.role === 'root' && <MenuItem value="">{t('Toutes les académies')}</MenuItem>}
        {admin?.academyIds.map(id => <MenuItem key={id} value={id}>{id}</MenuItem>)}
      </TextField>
      <Button variant="outlined" disabled={loading || admin?.role !== 'root' && !academyId} onClick={() => void load()}>{t(loaded ? 'Actualiser' : 'Afficher les notifications')}</Button>
    </Stack>
    {error && <Alert severity="error">{error}</Alert>}
    {rows.some(row => row.status === 'unknown') && <Alert severity="warning">{t('Certains envois ont un résultat incertain. Vérifiez leur historique dans Brevo avant tout nouvel envoi.')}</Alert>}
    {loaded && !rows.length && <Typography>{t('Aucune notification')}</Typography>}
    {rows.map(row => <Box key={row.id} sx={{ borderTop: '1px solid', borderColor: 'divider', pt: 2 }}>
      <Stack direction={{ xs: 'column', sm: 'row' }} gap={1} alignItems={{ sm: 'center' }}>
        <Box flex={1}><Typography fontWeight={700}>{row.recipient?.email ?? t('Adresse manquante')}</Typography><Typography variant="body2" color="text.secondary">{row.recipient?.name} · {row.createdAt ? new Date(row.createdAt).toLocaleString(localeFor(language)) : '—'}</Typography></Box>
        <Chip label={t(labels[row.status] ?? row.status)} color={row.status === 'delivered' ? 'success' : ['failed', 'bounced', 'blocked', 'complained'].includes(row.status) ? 'error' : 'default'} />
        {row.status === 'failed' && row.retryable && <Button disabled={loading} onClick={() => void retry(row.id)}>{t('Relancer l’envoi')}</Button>}
      </Stack>
      {row.bookingId && <Typography variant="caption">{t('Réservation')} : {row.bookingId}</Typography>}
      {row.lastError && <Typography variant="body2" color="error">{t('Motif')} : {row.lastError}</Typography>}
      {row.providerMessageId && <Typography variant="caption" display="block" sx={{ overflowWrap: 'anywhere' }}>{t('Référence email')} : {row.providerMessageId}</Typography>}
    </Box>)}
    {loading && <CircularProgress size={24} />}
    {cursor && <Button disabled={loading} onClick={() => void load(true)}>{t('Afficher la suite')}</Button>}
  </Stack></CardContent></Card>
}
