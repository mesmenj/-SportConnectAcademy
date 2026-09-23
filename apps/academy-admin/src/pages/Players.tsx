import { PaymentInvoiceDialog } from '../components/PaymentInvoiceDialog'
import { useEffect, useMemo, useState } from 'react'
import { Alert, Autocomplete, Avatar, Box, Button, Card, Chip, CircularProgress, Dialog, DialogActions, DialogContent, DialogTitle, Drawer, FormControl, IconButton, InputLabel, LinearProgress, MenuItem, Select, Stack, Tab, Table, TableBody, TableCell, TableContainer, TableHead, TableRow, Tabs, TextField, Tooltip, Typography } from '@mui/material'
import { AddRounded, CheckCircleRounded, CheckRounded, ChevronRightRounded, CloseRounded, DeleteOutlineRounded, EmailOutlined, FamilyRestroomRounded, PersonAddAltRounded, PhoneOutlined, RemoveRounded } from '@mui/icons-material'
import { colors } from '../theme'
import { useI18n } from '../i18n'
import { useAppSelector } from '../store/hooks'
import { subscribePlayerFamily, subscribePlayers, subscribeUsersWithPlayers, type FamilyMember, type PlayerRecord, type UserWithPlayers } from '../services/playerService'
import { adjustPlayerSessionQuota, assignPlayerCommunity, assignPlayerToUser, confirmCashPlayerPayment, softDeletePlayer, updatePlayerPackage } from '../services/managementService'
import { collection, onSnapshot } from 'firebase/firestore'
import { db } from '../firebase'
import { CreatePlayerDialog } from '../components/CreatePlayerDialog'
import { matchesSearch } from '../utils/search'

interface Community { id: string; academyId: string; name: string }

function PlayerPackageControl({ player, loading, onSave, t }: { player: PlayerRecord; loading: boolean; onSave: (sessionCount: number) => Promise<void>; t: (value: string) => string }) {
  const [draft, setDraft] = useState<string | null>(null)
  const value = draft ?? String(player.totalSessions)
  const parsed = Number(value)
  const valid = value.trim() !== '' && Number.isInteger(parsed) && parsed >= 0 && parsed <= 10000
  const save = (sessionCount: number) => { setDraft(null); return onSave(sessionCount) }
  return <Stack direction="row" alignItems="center" gap={.4} onClick={event => event.stopPropagation()}>
    <IconButton size="small" color="error" aria-label={t('Réduire le package')} title={t('Réduire le package')} disabled={loading || player.totalSessions <= 0} onClick={() => void save(player.totalSessions - 1)}><RemoveRounded fontSize="small" /></IconButton>
    <TextField size="small" type="number" value={value} disabled={loading} onChange={event => setDraft(event.target.value)} onKeyDown={event => { if (event.key === 'Enter' && valid && parsed !== player.totalSessions) void save(parsed) }} inputProps={{ min: 0, max: 10000, step: 1, 'aria-label': t('Nombre de cours du package') }} sx={{ width: 76, '& input': { textAlign: 'center', px: .7, py: .7 } }} />
    {loading ? <CircularProgress size={18} /> : <IconButton size="small" color="primary" aria-label={t('Enregistrer le package')} title={t('Enregistrer le package')} disabled={!valid || parsed === player.totalSessions} onClick={() => void save(parsed)}><CheckRounded fontSize="small" /></IconButton>}
    <IconButton size="small" color="success" aria-label={t('Augmenter le package')} title={t('Augmenter le package')} disabled={loading || player.totalSessions >= 10000} onClick={() => void save(player.totalSessions + 1)}><AddRounded fontSize="small" /></IconButton>
  </Stack>
}

export function Players({ searchQuery = '' }: { searchQuery?: string }) {
  const { t } = useI18n()
  const admin = useAppSelector(state => state.auth.user)
  const [players, setPlayers] = useState<PlayerRecord[]>([])
  const [activeTab, setActiveTab] = useState<'players' | 'users'>('players')
  const [selected, setSelected] = useState<PlayerRecord | null>(null)
  const [family, setFamily] = useState<FamilyMember[]>([])
  const [loading, setLoading] = useState(true)
  const [familyLoading, setFamilyLoading] = useState(false)
  const [error, setError] = useState(false)
  const [communities, setCommunities] = useState<Community[]>([])
  const [communityId, setCommunityId] = useState(''); const [savingCommunity, setSavingCommunity] = useState(false); const [communityError, setCommunityError] = useState('')
  const [confirmingPlayer, setConfirmingPlayer] = useState('')
  const [invoicePlayerId, setInvoicePlayerId] = useState('')
  const currentFamilyPlayer = players.find(player => player.id === selected?.id)
  const invoice = players.find(player => player.id === invoicePlayerId)?.invoice ?? null
  const [adjustingPlayer, setAdjustingPlayer] = useState('')
  const [updatingPackagePlayer, setUpdatingPackagePlayer] = useState('')
  const [actionError, setActionError] = useState('')
  const [users, setUsers] = useState<UserWithPlayers[]>([])
  const [createOpen, setCreateOpen] = useState(false)
  const [assignUserId, setAssignUserId] = useState('')
  const [assigningUser, setAssigningUser] = useState(false)
  const [playerToDelete, setPlayerToDelete] = useState<PlayerRecord | null>(null)
  const [deletingPlayer, setDeletingPlayer] = useState(false)

  useEffect(() => {
    if (!admin) return
    return subscribePlayers(admin, rows => { setPlayers(rows); setLoading(false); setError(false) }, () => { setLoading(false); setError(true) })
  }, [admin])

  useEffect(() => {
    if (!admin) return
    return onSnapshot(collection(db, 'communities'), snap => setCommunities(snap.docs.filter(doc => doc.get('active') === true).map(doc => ({ id: doc.id, academyId: doc.get('academyId'), name: doc.get('name') || doc.id }))))
  }, [admin])

  useEffect(() => admin ? subscribeUsersWithPlayers(setUsers, () => setActionError(t('Impossible de charger les utilisateurs.'))) : undefined, [admin, t])

  useEffect(() => {
    if (!selected) return
    return subscribePlayerFamily(selected, rows => { setFamily(rows); setFamilyLoading(false) }, () => setFamilyLoading(false))
  }, [selected])

  const openFamily = (player: PlayerRecord) => {
    setFamily([])
    setFamilyLoading(true)
    setSelected(player)
    setCommunityId(player.communityId ?? '')
    setAssignUserId('')
    setCommunityError('')
  }

  const saveCommunity = async () => {
    if (!selected) return
    setSavingCommunity(true); setCommunityError('')
    try { await assignPlayerCommunity({ playerId: selected.id, communityId: communityId || null }); setSelected({ ...selected, communityId: communityId || null, communityName: communities.find(item => item.id === communityId)?.name ?? 'Non attribuée' }) }
    catch (reason) { setCommunityError(reason instanceof Error ? t(reason.message) : t('Une erreur est survenue')) }
    finally { setSavingCommunity(false) }
  }

  const confirmCashPayment = async (player: PlayerRecord) => {
    setConfirmingPlayer(player.id); setActionError('')
    try { await confirmCashPlayerPayment(player.id); setInvoicePlayerId(player.id) }
    catch (reason) { setActionError(reason instanceof Error ? t(reason.message) : t('Une erreur est survenue')) }
    finally { setConfirmingPlayer('') }
  }

  const adjustSessionQuota = async (player: PlayerRecord, delta: -1 | 1) => {
    setAdjustingPlayer(player.id); setActionError('')
    try { await adjustPlayerSessionQuota({ playerId: player.id, delta }) }
    catch (reason) { setActionError(reason instanceof Error ? t(reason.message) : t('Une erreur est survenue')) }
    finally { setAdjustingPlayer('') }
  }

  const savePlayerPackage = async (player: PlayerRecord, sessionCount: number) => {
    setUpdatingPackagePlayer(player.id); setActionError('')
    try { await updatePlayerPackage({ playerId: player.id, sessionCount }) }
    catch (reason) { setActionError(reason instanceof Error ? t(reason.message) : t('Une erreur est survenue')) }
    finally { setUpdatingPackagePlayer('') }
  }

  const assignUser = async () => {
    if (!selected || !assignUserId) return
    setAssigningUser(true); setCommunityError('')
    try { await assignPlayerToUser({ playerId: selected.id, userId: assignUserId }); setAssignUserId('') }
    catch (reason) { setCommunityError(reason instanceof Error ? t(reason.message) : t('Une erreur est survenue')) }
    finally { setAssigningUser(false) }
  }

  const deletePlayer = async () => {
    if (!playerToDelete) return
    setDeletingPlayer(true); setActionError('')
    try { await softDeletePlayer(playerToDelete.id); if (selected?.id === playerToDelete.id) setSelected(null); setPlayerToDelete(null) }
    catch (reason) { setActionError(reason instanceof Error ? t(reason.message) : t('Une erreur est survenue')) }
    finally { setDeletingPlayer(false) }
  }

  const visiblePlayers = useMemo(() => players.filter(player => matchesSearch(searchQuery, player.id, player.name, player.age, player.level, player.academy, player.coach, player.status, player.communityName)), [players, searchQuery])
  const visibleUsers = useMemo(() => users.filter(user => matchesSearch(searchQuery, user.id, user.name, user.email, user.phone, user.role, user.status, user.playerIds.map(playerId => players.find(player => player.id === playerId)?.name))), [players, searchQuery, users])
  const assignableUsers = useMemo(() => users.filter(user => user.status === 'active'), [users])

  if (loading) return <Stack alignItems="center" py={10}><CircularProgress /></Stack>
  if (error) return <Alert severity="error">{t('Impossible de charger les joueurs.')}</Alert>

  return <>
    {actionError && <Alert severity="error" sx={{ mb: 2 }}>{actionError}</Alert>}
    <Stack direction={{ xs: 'column', sm: 'row' }} justifyContent="space-between" alignItems={{ sm: 'center' }} gap={1.5} mb={2}><Box><Typography variant="h6">{t('Joueurs & familles')}</Typography><Typography variant="body2" color="text.secondary">{t('Créez les joueurs et rattachez-les à leur famille.')}</Typography></Box><Button variant="contained" startIcon={<AddRounded />} onClick={() => setCreateOpen(true)}>{t('Créer un joueur')}</Button></Stack>
    <Card sx={{ mb: 2 }}><Tabs value={activeTab} onChange={(_, value: 'players' | 'users') => setActiveTab(value)} variant="scrollable" scrollButtons="auto" aria-label={t('Navigation joueurs et familles')}><Tab value="players" label={`${t('Profils joueurs')} (${visiblePlayers.length})`} /><Tab value="users" label={`${t('Utilisateurs et joueurs rattachés')} (${visibleUsers.length})`} /></Tabs></Card>
    {activeTab === 'players' && <>
    {!visiblePlayers.length && <Alert severity="info">{t('Aucun joueur enregistré pour le moment.')}</Alert>}
    {!!visiblePlayers.length && <Card><TableContainer><Table><TableHead><TableRow>{['Joueur', 'Niveau', 'Progression', 'Forfait', 'Cours du joueur', 'Statut', 'Famille', 'Actions'].map(label => <TableCell key={label} sx={{ fontWeight: 800, fontSize: 11, color: 'text.secondary' }}>{t(label)}</TableCell>)}</TableRow></TableHead>
      <TableBody>{visiblePlayers.map(player => <TableRow key={player.id} hover onClick={() => openFamily(player)} sx={{ cursor: 'pointer' }}>
        <TableCell><Stack direction="row" gap={1.2} alignItems="center"><Avatar sx={{ bgcolor: colors.sky, fontSize: 12 }}>{player.initials}</Avatar><Stack><Typography variant="body2" fontWeight={800}>{player.name}</Typography><Typography variant="caption" color="text.secondary">{player.age == null ? t('Âge non renseigné') : `${player.age} ${t('ans')}`}</Typography></Stack></Stack></TableCell>
        <TableCell><Chip size="small" label={t(player.level)} /></TableCell>
        <TableCell sx={{ minWidth: 150 }}><Stack direction="row" alignItems="center" gap={1}><LinearProgress variant="determinate" value={player.progress} sx={{ height: 7, borderRadius: 5, flex: 1 }} /><Typography variant="caption" fontWeight={800}>{player.progress}%</Typography></Stack></TableCell>
        <TableCell><PlayerPackageControl player={player} loading={updatingPackagePlayer === player.id} onSave={sessionCount => savePlayerPackage(player, sessionCount)} t={t} /></TableCell><TableCell><Stack direction="row" alignItems="center" gap={.5} onClick={event => event.stopPropagation()}><IconButton size="small" color="error" aria-label={t('Retirer un cours')} title={t('Retirer un cours')} disabled={Boolean(adjustingPlayer) || player.remainingSessions <= 0} onClick={() => void adjustSessionQuota(player, -1)}><RemoveRounded fontSize="small" /></IconButton><Chip size="small" label={adjustingPlayer === player.id ? <CircularProgress size={14} color="inherit" /> : player.remainingSessions} color={player.remainingSessions <= 0 ? 'error' : player.remainingSessions <= 3 ? 'warning' : 'success'} sx={{ minWidth: 38 }} /><IconButton size="small" color="success" aria-label={t('Ajouter un cours')} title={t('Ajouter un cours')} disabled={Boolean(adjustingPlayer)} onClick={() => void adjustSessionQuota(player, 1)}><AddRounded fontSize="small" /></IconButton></Stack></TableCell><TableCell><Stack alignItems="flex-start" gap={.7}><Chip size="small" label={t(player.status)} color={player.status === 'Actif' ? 'success' : player.status === 'En attente de confirmation' ? 'warning' : 'default'} />{player.status === 'En attente de confirmation' && player.paymentMethod === 'cash' && <Button size="small" color="success" startIcon={confirmingPlayer === player.id ? <CircularProgress size={14} color="inherit" /> : <CheckCircleRounded />} disabled={Boolean(confirmingPlayer)} onClick={event => { event.stopPropagation(); void confirmCashPayment(player) }}>{t('Confirmer le paiement')}</Button>}{player.invoice && <Button size="small" onClick={event => { event.stopPropagation(); setInvoicePlayerId(player.id) }}>{t('Facture')}</Button>}</Stack></TableCell><TableCell><IconButton aria-label={t('Voir la famille')} onClick={event => { event.stopPropagation(); openFamily(player) }}><ChevronRightRounded /></IconButton></TableCell><TableCell><Tooltip title={t('Supprimer le joueur')}><IconButton color="error" aria-label={t('Supprimer le joueur')} onClick={event => { event.stopPropagation(); setPlayerToDelete(player) }}><DeleteOutlineRounded /></IconButton></Tooltip></TableCell>
      </TableRow>)}</TableBody>
    </Table></TableContainer></Card>}
    </>}

    {activeTab === 'users' && <>
    <Box mb={2}><Typography variant="h6">{t('Utilisateurs et joueurs rattachés')}</Typography><Typography variant="body2" color="text.secondary">{t('Consultez chaque parent ou élève et les profils joueurs associés.')}</Typography></Box>
    {!visibleUsers.length ? <Alert severity="info">{t('Aucun utilisateur parent ou élève enregistré.')}</Alert> : <Card><TableContainer><Table><TableHead><TableRow>{['Utilisateur', 'Rôle', 'Contact', 'Joueurs rattachés'].map(label => <TableCell key={label} sx={{ fontWeight: 800, fontSize: 11, color: 'text.secondary' }}>{t(label)}</TableCell>)}</TableRow></TableHead><TableBody>{visibleUsers.map(user => { const visiblePlayerIds = user.playerIds.filter(playerId => players.some(item => item.id === playerId)); return <TableRow key={user.id} hover><TableCell><Typography variant="body2" fontWeight={800}>{user.name}</Typography><Typography variant="caption" color="text.secondary">{user.id}</Typography></TableCell><TableCell><Chip size="small" label={t(user.role)} /></TableCell><TableCell><Typography variant="body2">{user.email}</Typography>{user.phone !== '—' && <Typography variant="caption" color="text.secondary">{user.phone}</Typography>}</TableCell><TableCell><Stack direction="row" gap={.7} flexWrap="wrap">{!visiblePlayerIds.length && <Typography variant="body2" color="text.secondary">{t('Aucun joueur')}</Typography>}{visiblePlayerIds.map(playerId => { const player = players.find(item => item.id === playerId); return <Chip key={playerId} size="small" color="primary" label={player?.name ?? playerId} onClick={() => player && openFamily(player)} /> })}</Stack></TableCell></TableRow> })}</TableBody></Table></TableContainer></Card>}
    </>}

    <Drawer anchor="right" open={Boolean(selected)} onClose={() => setSelected(null)} PaperProps={{ sx: { width: { xs: '100%', sm: 440 }, p: 3 } }}>
      <Stack direction="row" alignItems="center" justifyContent="space-between"><Box><Typography variant="h5">{t('Famille liée')}</Typography><Typography color="text.secondary">{selected?.name}</Typography></Box><IconButton onClick={() => setSelected(null)} aria-label={t('Fermer')}><CloseRounded /></IconButton></Stack>
      <Stack mt={3} gap={1.5}>
        {currentFamilyPlayer?.paymentMethod === 'cash' && <Card variant="outlined"><Box p={2}><Typography fontWeight={800} mb={1}>{t('Paiement')}</Typography>
          {currentFamilyPlayer.paymentStatus === 'cash_pending' && <Button color="success" variant="contained" disabled={Boolean(confirmingPlayer)} onClick={() => void confirmCashPayment(currentFamilyPlayer)}>{t('Confirmer le paiement')}</Button>}
          {currentFamilyPlayer.invoice && <Button variant="outlined" onClick={() => setInvoicePlayerId(currentFamilyPlayer.id)}>{t('Facture')}</Button>}
          {currentFamilyPlayer.paymentStatus === 'confirmed' && !currentFamilyPlayer.invoice && <Typography variant="body2">{t('Ce paiement ancien ne possède pas de facture enregistrée.')}</Typography>}
          {actionError && <Alert severity="error" sx={{ mt: 1 }}>{actionError}</Alert>}
        </Box></Card>}
        <Card variant="outlined"><Box p={2}><Typography fontWeight={800} mb={1.5}>{t('Attribuer à un utilisateur')}</Typography>{family.length > 0 || selected?.assignedUserId ? <Alert severity="info">{t('Ce joueur est déjà attribué à un utilisateur. Un joueur ne peut être lié qu’à un seul utilisateur.')}</Alert> : <><Stack direction={{ xs: 'column', sm: 'row' }} gap={1}><Autocomplete fullWidth options={assignableUsers} value={assignableUsers.find(user => user.id === assignUserId) ?? null} getOptionLabel={user => `${user.name} · ${user.email}`} isOptionEqualToValue={(option, value) => option.id === value.id} onChange={(_, user) => setAssignUserId(user?.id ?? '')} renderInput={params => <TextField {...params} label={t('Rechercher un utilisateur')} placeholder={t('Nom ou adresse e-mail')} />} /><Button variant="contained" startIcon={<PersonAddAltRounded />} disabled={!assignUserId || assigningUser || familyLoading} onClick={assignUser}>{assigningUser ? <CircularProgress size={18} color="inherit" /> : t('Attribuer')}</Button></Stack><Typography variant="caption" color="text.secondary">{t('Le joueur apparaîtra immédiatement dans le profil de cet utilisateur.')}</Typography></>}</Box></Card>
        <Card variant="outlined"><Box p={2}><Typography fontWeight={800} mb={1.5}>{t('Communauté du joueur')}</Typography>{communityError && <Alert severity="error" sx={{ mb: 1.5 }}>{communityError}</Alert>}<Stack direction="row" gap={1}><FormControl fullWidth><InputLabel>{t('Communauté')}</InputLabel><Select label={t('Communauté')} value={communityId} onChange={event => setCommunityId(event.target.value)}><MenuItem value="">{t('Aucune communauté')}</MenuItem>{communities.map(item => <MenuItem key={item.id} value={item.id}>{item.name}</MenuItem>)}</Select></FormControl><Button variant="contained" disabled={savingCommunity || communityId === (selected?.communityId ?? '')} onClick={saveCommunity}>{savingCommunity ? <CircularProgress size={18} color="inherit" /> : t('Attribuer')}</Button></Stack><Typography variant="caption" color="text.secondary">{t('Un joueur ne peut appartenir qu’à une seule communauté.')}</Typography></Box></Card>
        {familyLoading && <Stack alignItems="center" py={5}><CircularProgress /></Stack>}
        {!familyLoading && !family.length && <Alert severity="info">{t('Aucun membre de la famille lié à ce joueur.')}</Alert>}
        {!familyLoading && family.map(person => <Card key={person.id} variant="outlined"><Box p={2}><Stack direction="row" gap={1.5} alignItems="center"><Avatar sx={{ bgcolor: colors.cloud, color: colors.ink }}><FamilyRestroomRounded /></Avatar><Box><Typography fontWeight={800}>{t(person.name)}</Typography><Chip size="small" label={t(person.relationship)} sx={{ mt: .5 }} /></Box></Stack><Stack gap={1} mt={2}>{person.phone !== '—' && <Stack direction="row" gap={1} alignItems="center"><PhoneOutlined fontSize="small" color="disabled"/><Typography variant="body2">{person.phone}</Typography></Stack>}{person.email !== '—' && <Stack direction="row" gap={1} alignItems="center"><EmailOutlined fontSize="small" color="disabled"/><Typography variant="body2">{person.email}</Typography></Stack>}</Stack></Box></Card>)}
      </Stack>
    </Drawer>
    <PaymentInvoiceDialog invoice={invoice} onClose={() => setInvoicePlayerId('')} />
    <CreatePlayerDialog open={createOpen} users={users} onClose={() => setCreateOpen(false)} onCreated={() => setCreateOpen(false)} />
    <Dialog open={Boolean(playerToDelete)} onClose={() => !deletingPlayer && setPlayerToDelete(null)} fullWidth maxWidth="xs"><DialogTitle>{t('Supprimer le joueur ?')}</DialogTitle><DialogContent><Typography>{t('Ce joueur sera masqué de toutes les listes sans supprimer définitivement ses données.')}</Typography><Typography fontWeight={800} mt={1}>{playerToDelete?.name}</Typography></DialogContent><DialogActions><Button onClick={() => setPlayerToDelete(null)} disabled={deletingPlayer}>{t('Annuler')}</Button><Button variant="contained" color="error" onClick={() => void deletePlayer()} disabled={deletingPlayer} startIcon={deletingPlayer ? <CircularProgress size={16} color="inherit" /> : <DeleteOutlineRounded />}>{t('Supprimer')}</Button></DialogActions></Dialog>
  </>
}
