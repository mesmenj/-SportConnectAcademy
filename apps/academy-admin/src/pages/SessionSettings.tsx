import { useEffect, useState } from 'react'
import { Alert, Box, Button, Card, CardContent, CircularProgress, FormControl, InputAdornment, InputLabel, MenuItem, Select, Stack, Tab, Table, TableBody, TableCell, TableContainer, TableHead, TableRow, Tabs, TextField, Typography } from '@mui/material'
import { DeleteRounded, EditRounded, GroupsRounded, LockPersonRounded, SaveRounded, SupervisorAccountRounded } from '@mui/icons-material'
import { collection, onSnapshot, orderBy, query, where, type QueryConstraint } from 'firebase/firestore'
import { db } from '../firebase'
import { deleteSessionConfiguration, updateSessionConfiguration, type SessionActivityType, type SessionConfigurationType, type SessionCurrency } from '../services/managementService'
import { useAppSelector } from '../store/hooks'
import { formatMoney, useI18n } from '../i18n'
import { SessionPlanner } from '../components/SessionPlanner'
import { PadelSlotPlanner } from '../components/PadelSlotPlanner'
import { CommunityManager } from '../components/CommunityManager'

interface Academy { id: string; name: string }
interface Configuration { type: SessionConfigurationType; price: string; sessionCount: string; currency: SessionCurrency; minAge: string; maxAge: string }
interface SavedConfiguration extends Configuration { id: string; activityType: SessionActivityType }
const TYPES: Array<{ type: SessionConfigurationType; label: string; description: string; icon: typeof LockPersonRounded }> = [
  { type: 'private', label: 'Séance privée', description: 'Un joueur avec un coach.', icon: LockPersonRounded },
  { type: 'semi_private', label: 'Séance semi-privée', description: 'Un petit groupe avec un accompagnement rapproché.', icon: SupervisorAccountRounded },
  { type: 'group', label: 'Séance de groupe', description: 'Un cours collectif pour plusieurs joueurs.', icon: GroupsRounded },
]
const CURRENCIES: Array<{ code: SessionCurrency; label: string; symbol: string }> = [
  { code: 'AED', label: 'Dirham des Émirats arabes unis', symbol: 'AED' }, { code: 'XAF', label: 'Franc CFA', symbol: 'FCFA' },
  { code: 'EUR', label: 'Euro', symbol: '€' }, { code: 'USD', label: 'Dollar américain', symbol: '$' }, { code: 'MAD', label: 'Dirham marocain', symbol: 'MAD' },
]
const empty = (type: SessionConfigurationType): Configuration => ({ type, price: '', sessionCount: '', currency: 'AED', minAge: '', maxAge: '' })

export function SessionSettings({ notify }: { notify: (message: string) => void }) {
  const { t, language } = useI18n(); const admin = useAppSelector(state => state.auth.user)
  const [academies, setAcademies] = useState<Academy[]>([]); const [academyId, setAcademyId] = useState('')
  const [configs, setConfigs] = useState<Record<SessionConfigurationType, Configuration>>({ private: empty('private'), semi_private: empty('semi_private'), group: empty('group') })
  const [rows, setRows] = useState<SavedConfiguration[]>([]); const [saving, setSaving] = useState<SessionConfigurationType | null>(null); const [error, setError] = useState('')
  const [activeTab, setActiveTab] = useState(0)
  const [activityType, setActivityType] = useState<SessionActivityType>('tennis')

  useEffect(() => {
    if (!admin) return
    const constraints: QueryConstraint[] = [orderBy('name')]
    if (admin.role !== 'root') { if (!admin.academyIds.length) return; constraints.unshift(where('__name__', 'in', admin.academyIds.slice(0, 10))) }
    return onSnapshot(query(collection(db, 'academies'), ...constraints), snapshot => { const items = snapshot.docs.map(doc => ({ id: doc.id, name: doc.get('name') || doc.id })); setAcademies(items); setAcademyId(current => current || items[0]?.id || '') })
  }, [admin])

  useEffect(() => {
    if (!academyId) return
    return onSnapshot(query(collection(db, 'sessionConfigurations'), where('academyId', '==', academyId)), snapshot => setRows(snapshot.docs.map(doc => {
      const data = doc.data(); const maximumAge = data.maximumAge === null ? '' : data.maximumAge ?? (Number(data.maxAge) < 100 ? data.maxAge : ''); return { id: doc.id, activityType: (data.activityType ?? 'tennis') as SessionActivityType, type: data.type as SessionConfigurationType, price: String(data.price ?? ''), sessionCount: String(data.sessionCount ?? 1), currency: (data.currency ?? 'AED') as SessionCurrency, minAge: String(data.minAge ?? ''), maxAge: String(maximumAge), active: data.active === true }
    }).filter(item => item.active && item.activityType === activityType).sort((a, b) => a.type.localeCompare(b.type) || Number(a.minAge) - Number(b.minAge))))
  }, [academyId, activityType])

  const change = (type: SessionConfigurationType, field: 'price' | 'sessionCount' | 'minAge' | 'maxAge' | 'currency', value: string) => setConfigs(current => ({ ...current, [type]: { ...current[type], [field]: value } }))
  const edit = (row: SavedConfiguration) => { setConfigs(current => ({ ...current, [row.type]: { ...row } })); window.scrollTo({ top: 0, behavior: 'smooth' }) }
  const save = async (type: SessionConfigurationType) => {
    const value = configs[type]; const price = Number(value.price); const sessionCount = Number(value.sessionCount); const minAge = Number(value.minAge); const maxAge = value.maxAge === '' ? null : Number(value.maxAge)
    if (!academyId || !Number.isInteger(price) || price < 0 || !Number.isInteger(sessionCount) || sessionCount < 1 || sessionCount > 1000 || !Number.isInteger(minAge) || minAge < 2 || minAge > 100 || maxAge !== null && (!Number.isInteger(maxAge) || maxAge < minAge || maxAge > 100)) { setError(t('Vérifiez le prix, le nombre de séances et les âges renseignés.')); return }
    setSaving(type); setError('')
    try { await updateSessionConfiguration({ academyId, activityType, type, price, sessionCount, minAge, maxAge, currency: value.currency }); notify(t('Configuration enregistrée')) }
    catch (reason) { setError(reason instanceof Error ? t(reason.message) : t('Une erreur est survenue')) } finally { setSaving(null) }
  }
  const remove = async (row: SavedConfiguration) => {
    if (!window.confirm(t('Supprimer cette configuration de séance ?'))) return
    setError('')
    try { await deleteSessionConfiguration(row.id); notify(t('Configuration supprimée')) }
    catch (reason) { setError(reason instanceof Error ? t(reason.message) : t('Une erreur est survenue')) }
  }

  return <Stack gap={2.5}>
    <Card><CardContent><Stack direction={{ xs: 'column', md: 'row' }} justifyContent="space-between" gap={2} alignItems={{ md: 'center' }}><Box><Typography variant="h5">{t(activityType === 'padel' ? 'Configuration des créneaux Paddle' : 'Catalogue des séances')}</Typography><Typography color="text.secondary">{t(activityType === 'padel' ? 'Configurez les durées et montants proposés pour le Paddle.' : 'Configurez le prix et l’âge minimum. Ces valeurs seront appliquées aux nouvelles réservations.')}</Typography></Box><FormControl sx={{ minWidth: 280 }}><InputLabel>{t('Session')}</InputLabel><Select value={activityType} label={t('Session')} onChange={event => { setActivityType(event.target.value as SessionActivityType); setActiveTab(0); setConfigs({ private: empty('private'), semi_private: empty('semi_private'), group: empty('group') }) }}><MenuItem value="tennis">{t('Tennis session')}</MenuItem><MenuItem value="padel">{t('Paddle session')}</MenuItem></Select></FormControl></Stack></CardContent></Card>
    {!academies.length && <Alert severity="info">{t('Créez ou rattachez d’abord une académie à votre compte.')}</Alert>}
    {academyId && <><Card><Tabs value={activeTab} onChange={(_, value) => setActiveTab(value)} variant="fullWidth" sx={{ px: 1, borderBottom: 1, borderColor: 'divider' }}><Tab value={0} label={t(activityType === 'padel' ? 'Configuration des créneaux' : 'Configuration des séances')} />{activityType === 'tennis' && <Tab value={1} label={t('Créneaux planifiés')} />}<Tab value={2} label={t('Communautés')} /></Tabs></Card>
    {activeTab === 0 && (activityType === 'padel' ? <PadelSlotPlanner academyId={academyId} notify={notify} /> : <Stack gap={2.5}>{error && <Alert severity="error">{error}</Alert>}<Alert severity="info">{t('Une configuration existante avec le même âge minimum sera mise à jour.')}</Alert>
      <Box sx={{ display: 'grid', gridTemplateColumns: { xs: '1fr', lg: 'repeat(3, 1fr)' }, gap: 2 }}>{TYPES.map(item => { const Icon = item.icon; const value = configs[item.type]; const selectedCurrency = CURRENCIES.find(option => option.code === value.currency)!; return <Card key={item.type}><CardContent sx={{ p: 3 }}><Stack gap={2.2}><Box sx={{ width: 48, height: 48, borderRadius: 3, bgcolor: 'rgba(91,192,235,.15)', display: 'grid', placeItems: 'center' }}><Icon color="primary" /></Box><Box><Typography variant="h6">{t(item.label)}</Typography><Typography variant="body2" color="text.secondary">{t(item.description)}</Typography></Box><FormControl fullWidth><InputLabel>{t('Devise')}</InputLabel><Select label={t('Devise')} value={value.currency} onChange={event => change(item.type, 'currency', event.target.value)}>{CURRENCIES.map(option => <MenuItem key={option.code} value={option.code}>{t(option.label)} ({option.code})</MenuItem>)}</Select></FormControl><TextField type="number" label={t('Prix')} value={value.price} onChange={event => change(item.type, 'price', event.target.value)} inputProps={{ min: 0, step: value.currency === 'XAF' ? 500 : 1 }} InputProps={{ endAdornment: <InputAdornment position="end">{selectedCurrency.symbol}</InputAdornment> }} /><TextField type="number" required label={t('Nombre de séances')} value={value.sessionCount} onChange={event => change(item.type, 'sessionCount', event.target.value)} inputProps={{ min: 1, max: 1000 }} /><Stack direction="row" gap={1.5}><TextField fullWidth type="number" required label={t('Âge minimum')} value={value.minAge} inputProps={{ min: 2, max: 100 }} onChange={event => change(item.type, 'minAge', event.target.value)} /><TextField fullWidth type="number" label={t('Âge maximum (facultatif)')} value={value.maxAge} inputProps={{ min: Number(value.minAge) || 2, max: 100 }} onChange={event => change(item.type, 'maxAge', event.target.value)} /></Stack><Button variant="contained" startIcon={saving === item.type ? <CircularProgress size={18} color="inherit" /> : <SaveRounded />} disabled={saving !== null} onClick={() => save(item.type)}>{t('Enregistrer')}</Button></Stack></CardContent></Card> })}</Box>
      <Card><CardContent><Typography variant="h6">{t('Configurations enregistrées')}</Typography><Typography color="text.secondary" mb={2}>{t('L’âge maximum est facultatif.')}</Typography>{!rows.length ? <Alert severity="info">{t('Aucune configuration enregistrée.')}</Alert> : <TableContainer><Table><TableHead><TableRow><TableCell>{t('Type de séance')}</TableCell><TableCell>{t('Tranche d’âge')}</TableCell><TableCell>{t('Nombre de séances')}</TableCell><TableCell>{t('Prix')}</TableCell><TableCell align="right">{t('Actions')}</TableCell></TableRow></TableHead><TableBody>{rows.map(row => <TableRow key={row.id}><TableCell>{t(TYPES.find(item => item.type === row.type)?.label ?? row.type)}</TableCell><TableCell>{row.maxAge ? `${row.minAge}–${row.maxAge} ${t('ans')}` : `${row.minAge} ${t('ans')}`}</TableCell><TableCell>{row.sessionCount}</TableCell><TableCell>{formatMoney(Number(row.price), row.currency, language)}</TableCell><TableCell align="right"><Stack direction="row" justifyContent="flex-end"><Button size="small" startIcon={<EditRounded />} onClick={() => edit(row)}>{t('Modifier')}</Button><Button size="small" color="error" startIcon={<DeleteRounded />} onClick={() => remove(row)}>{t('Supprimer')}</Button></Stack></TableCell></TableRow>)}</TableBody></Table></TableContainer>}</CardContent></Card>
    </Stack>)}
      {activeTab === 1 && activityType === 'tennis' && <SessionPlanner academyId={academyId} activityType={activityType} notify={notify} />}
      {activeTab === 2 && <CommunityManager academyId={academyId} notify={notify} />}
    </>}
  </Stack>
}
