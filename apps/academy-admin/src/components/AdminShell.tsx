import { useEffect, useState, type ReactNode } from 'react'
import { AppBar, Avatar, Badge, Box, Button, ButtonBase, Card, CardContent, Chip, Divider, Drawer, IconButton, InputAdornment, List, ListItemButton, ListItemIcon, ListItemText, Menu, MenuItem, Stack, TextField, Toolbar, Tooltip, Typography, useMediaQuery, useTheme } from '@mui/material'
import { AdminPanelSettingsRounded, BusinessRounded, CalendarMonthRounded, CampaignRounded, CloseRounded, DashboardRounded, EmojiEventsRounded, GroupsRounded, HelpOutlineRounded, LanguageRounded, LogoutRounded, MenuRounded, MessageRounded, NotificationsNoneRounded, PriceChangeRounded, SchoolRounded, SearchRounded, SettingsRounded, SportsTennisRounded, StadiumRounded } from '@mui/icons-material'
import { colors } from '../theme'
import { useI18n, type Language } from '../i18n'

import type { Page } from '../store/uiSlice'
import { useAppSelector } from '../store/hooks'
import { doc, onSnapshot } from 'firebase/firestore'
import { db } from '../firebase'
export type { Page } from '../store/uiSlice'
const drawerWidth = 252
const items: Array<{ id: Page; label: string; icon: ReactNode }> = [
  { id: 'dashboard', label: 'Vue d’ensemble', icon: <DashboardRounded /> },
  { id: 'bookings', label: 'Réservations', icon: <CalendarMonthRounded /> },
  { id: 'sessionSettings', label: 'Configuration des séances', icon: <PriceChangeRounded /> },
  { id: 'players', label: 'Joueurs & familles', icon: <GroupsRounded /> },
  { id: 'coaches', label: 'Coachs', icon: <SchoolRounded /> },
  { id: 'academies', label: 'Académies', icon: <BusinessRounded /> },
  { id: 'stadiums', label: 'Stades', icon: <StadiumRounded /> },
  { id: 'tournaments', label: 'Tournois', icon: <EmojiEventsRounded /> },
  { id: 'messages', label: 'Communication', icon: <MessageRounded /> },
  { id: 'administration', label: 'Administration', icon: <AdminPanelSettingsRounded /> },
]

const searchPlaceholders: Partial<Record<Page, string>> = {
  bookings: 'Rechercher une réservation ou un joueur...',
  players: 'Rechercher un joueur ou une famille...',
  coaches: 'Rechercher un coach...',
  academies: 'Rechercher une académie...',
  stadiums: 'Rechercher un stade...',
  tournaments: 'Rechercher un tournoi...',
  administration: 'Rechercher un administrateur...',
}

export function AdminShell({ page, onNavigate, onLogout, pendingBookings, playerCount, searchQuery, onSearchChange, children }: { page: Page; onNavigate: (page: Page) => void; onLogout: () => void; pendingBookings: number; playerCount: number; searchQuery: string; onSearchChange: (value: string) => void; children: ReactNode }) {
  const theme = useTheme()
  const mobile = useMediaQuery(theme.breakpoints.down('md'))
  const [drawerOpen, setDrawerOpen] = useState(false)
  const [anchor, setAnchor] = useState<HTMLElement | null>(null)
  const [languageAnchor, setLanguageAnchor] = useState<HTMLElement | null>(null)
  const { language, setLanguage, t } = useI18n()
  const admin = useAppSelector(state => state.auth.user)
  const academyId = admin?.academyIds?.[0]
  const [academyBranding, setAcademyBranding] = useState({ name: '', logoUrl: '' })
  useEffect(() => {
    if (!academyId) return
    return onSnapshot(doc(db, 'academies', academyId), snapshot => setAcademyBranding({ name: snapshot.get('name') || 'SportA', logoUrl: snapshot.get('logoUrl') || '' }), () => setAcademyBranding({ name: 'SportA', logoUrl: '' }))
  }, [academyId])
  const visibleItems = items.filter(item => {
    if (item.id === 'messages') return false
    if (item.id === 'administration') return admin?.permissions.includes('admins.manage')
    if (item.id === 'academies') return admin?.permissions.includes('academies.manage')
    if (item.id === 'stadiums') return admin?.permissions.includes('stadiums.manage')
    if (item.id === 'coaches') return admin?.permissions.includes('coaches.manage')
    if (item.id === 'sessionSettings') return admin?.permissions.includes('sessions.manage') || admin?.permissions.includes('academies.manage')
    return true
  })
  const navigate = (target: Page) => { onSearchChange(''); onNavigate(target); setDrawerOpen(false) }
  const searchPlaceholder = searchPlaceholders[page]
  const sidebar = <Stack height="100%" p={2}>
    <Stack direction="row" alignItems="center" gap={1.2} px={1} height={64}>
      <Avatar variant="rounded" src={academyId ? academyBranding.logoUrl || '/challengeme-academy-logo.jpg' : '/challengeme-academy-logo.jpg'} alt={academyBranding.name || 'SportA'} sx={{ bgcolor: 'white' }}><SportsTennisRounded /></Avatar>
      <Box><Typography fontWeight={900} letterSpacing={-0.7}>SportA</Typography><Typography variant="caption" color="text.secondary">ACADEMY · ADMIN</Typography></Box>
    </Stack>
    <Typography variant="overline" color="text.secondary" fontWeight={800} px={1.5} mt={2}>{t('GESTION')}</Typography>
    <List sx={{ mt: 0.5 }}>{visibleItems.map(item => <ListItemButton key={item.id} selected={page === item.id} onClick={() => navigate(item.id)}
      sx={{ borderRadius: 3, mb: 0.5, minHeight: 47, '&.Mui-selected': { bgcolor: 'rgba(91,192,235,.16)' } }}>
      <ListItemIcon sx={{ minWidth: 38, color: page === item.id ? colors.ink : 'text.secondary' }}>{item.icon}</ListItemIcon>
      <ListItemText primary={t(item.label)} primaryTypographyProps={{ fontSize: 13, fontWeight: page === item.id ? 800 : 600 }} />
      {item.id === 'bookings' && pendingBookings > 0 && <Chip size="small" label={pendingBookings} sx={{ height: 22, bgcolor: page === item.id ? colors.ink : colors.cloud, color: page === item.id ? 'white' : 'text.secondary' }} />}
    </ListItemButton>)}</List>
    <Box flex={1} /><Divider />
    <List>
      <ListItemButton onClick={() => navigate('profile')} sx={{ borderRadius: 3 }}><ListItemIcon sx={{ minWidth: 38 }}><SettingsRounded /></ListItemIcon><ListItemText primary={t('Mon profil')} primaryTypographyProps={{ fontSize: 13, fontWeight: 700 }} /></ListItemButton>
      <ListItemButton sx={{ borderRadius: 3 }}><ListItemIcon sx={{ minWidth: 38 }}><HelpOutlineRounded /></ListItemIcon><ListItemText primary={t('Centre d’aide')} primaryTypographyProps={{ fontSize: 13, fontWeight: 700 }} /></ListItemButton>
      <ListItemButton onClick={onLogout} sx={{ borderRadius: 3, color: 'error.main' }}><ListItemIcon sx={{ minWidth: 38, color: 'error.main' }}><LogoutRounded /></ListItemIcon><ListItemText primary={t('Déconnexion')} primaryTypographyProps={{ fontSize: 13, fontWeight: 800 }} /></ListItemButton>
    </List>
    <Card sx={{ bgcolor: colors.ink, color: 'white' }}><CardContent sx={{ p: '16px!important' }}>
      <Typography variant="caption" color={colors.sky} fontWeight={800}>{t('ACADÉMIE ACTIVE')}</Typography>
      <Typography fontWeight={800} fontSize={13} mt={0.5}>{academyId ? academyBranding.name || 'SportA' : 'SportA'}</Typography><Typography variant="caption" sx={{ opacity: 0.65 }}>{playerCount} {t('joueurs')}</Typography>
    </CardContent></Card>
  </Stack>
  return <Box sx={{ display: 'flex', minHeight: '100vh' }}>
    <AppBar position="fixed" color="inherit" elevation={0} sx={{ ml: { md: `${drawerWidth}px` }, width: { md: `calc(100% - ${drawerWidth}px)` }, borderBottom: `1px solid ${colors.line}`, bgcolor: 'rgba(255,255,255,.92)', backdropFilter: 'blur(14px)' }}>
      <Toolbar sx={{ gap: 1.5, minHeight: '72px!important' }}>
        {mobile && <IconButton onClick={() => setDrawerOpen(true)}><MenuRounded /></IconButton>}
        <TextField value={searchQuery} disabled={!searchPlaceholder} onChange={event => onSearchChange(event.target.value)} placeholder={t(searchPlaceholder ?? 'Recherche indisponible dans ce module')} inputProps={{ 'aria-label': t(searchPlaceholder ?? 'Recherche') }} sx={{ width: { xs: '100%', sm: 380 }, '& .MuiOutlinedInput-root': { bgcolor: colors.cloud, borderRadius: 3 } }} InputProps={{ startAdornment: <InputAdornment position="start"><SearchRounded color="disabled" /></InputAdornment>, endAdornment: searchQuery ? <InputAdornment position="end"><IconButton size="small" aria-label={t('Effacer la recherche')} onClick={() => onSearchChange('')}><CloseRounded fontSize="small" /></IconButton></InputAdornment> : undefined }} />
        <Box flex={1} /><Tooltip title={t('Notifications')}><IconButton aria-label={t('Notifications')} onClick={e => setAnchor(e.currentTarget)}><Badge badgeContent={4} color="error"><NotificationsNoneRounded /></Badge></IconButton></Tooltip>
        <Button size="small" variant="outlined" startIcon={<LanguageRounded />} onClick={e => setLanguageAnchor(e.currentTarget)} sx={{ minWidth: 76 }}>{language.toUpperCase()}</Button>
        <Divider orientation="vertical" flexItem sx={{ my: 2 }} /><ButtonBase onClick={() => navigate('profile')} sx={{ borderRadius: 3, p: .5 }}><Stack direction="row" gap={1.2} alignItems="center"><Avatar sx={{ bgcolor: colors.lilac, width: 38, height: 38, fontSize: 13, fontWeight: 800 }}>{admin?.initials}</Avatar><Box sx={{ display: { xs: 'none', sm: 'block' }, textAlign: 'left' }}><Typography variant="body2" fontWeight={800}>{admin?.name}</Typography><Typography variant="caption" color="text.secondary">{admin?.role ? t(admin.role) : ''}</Typography></Box></Stack></ButtonBase>
      </Toolbar>
    </AppBar>
    <Box component="nav" sx={{ width: { md: drawerWidth }, flexShrink: { md: 0 } }}><Drawer variant={mobile ? 'temporary' : 'permanent'} open={mobile ? drawerOpen : true} onClose={() => setDrawerOpen(false)} ModalProps={{ keepMounted: true }} sx={{ '& .MuiDrawer-paper': { width: drawerWidth, borderRight: `1px solid ${colors.line}`, boxSizing: 'border-box' } }}>{sidebar}</Drawer></Box>
    <Box component="main" sx={{ flexGrow: 1, minWidth: 0, width: { md: `calc(100% - ${drawerWidth}px)` }, bgcolor: colors.cloud }}>
      <Toolbar sx={{ minHeight: '72px!important' }} />
      <Box sx={{ width: '100%', maxWidth: 1480, mx: 'auto', px: { xs: 2, sm: 3, lg: 4 }, pt: { xs: 3, md: 4 }, pb: 7 }}>
        {children}
      </Box>
    </Box>
    <Menu anchorEl={anchor} open={Boolean(anchor)} onClose={() => setAnchor(null)} PaperProps={{ sx: { width: 350, p: 1, borderRadius: 3 } }}>
      <Typography fontWeight={800} px={2} py={1}>{t('Notifications récentes')}</Typography>
      {['3 réservations attendent validation', 'Lucas a gagné un nouveau badge', 'Tournoi complet à 80%', 'Message de Mme Ngono'].map((notice, i) => <MenuItem key={notice} onClick={() => setAnchor(null)} sx={{ borderRadius: 2, whiteSpace: 'normal' }}><Avatar sx={{ width: 34, height: 34, mr: 1.5, bgcolor: [colors.orange, colors.sky, colors.green, colors.lilac][i] }}><CampaignRounded fontSize="small" /></Avatar><Typography variant="body2">{t(notice)}</Typography></MenuItem>)}
    </Menu>
    <Menu anchorEl={languageAnchor} open={Boolean(languageAnchor)} onClose={() => setLanguageAnchor(null)}>
      {[['fr','🇫🇷 Français'],['en','🇬🇧 English']].map(option => <MenuItem key={option[0]} selected={language === option[0]} onClick={() => { setLanguage(option[0] as Language); setLanguageAnchor(null) }}>{option[1]}</MenuItem>)}
    </Menu>
  </Box>
}
