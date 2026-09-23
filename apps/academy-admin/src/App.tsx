import { lazy, Suspense, useDeferredValue, useEffect, useRef, useState } from 'react'
import { Box, Button, CircularProgress, Snackbar, Stack, Typography } from '@mui/material'
import { AddRounded } from '@mui/icons-material'
import { AdminShell, type Page } from './components/AdminShell'
import './App.css'
import { localeFor, useI18n } from './i18n'
import { AdminLogin } from './components/AdminLogin'
import { useAppDispatch, useAppSelector } from './store/hooks'
import { bookingSelectors, bookingsReceived } from './store/bookingsSlice'
import { firebaseSessionResolved, loggedOut } from './store/authSlice'
import { bookingDialogClosed, bookingDialogOpened, pageChanged, toastClosed, toastShown, uiReset } from './store/uiSlice'
import { onAuthStateChanged } from 'firebase/auth'
import { auth } from './firebase'
import { logoutFromFirebase, subscribeToAdminProfile } from './services/authService'
import { completeFirebaseBooking, decideFirebaseBooking, subscribeBookings } from './services/bookingService'

const Dashboard = lazy(() => import('./pages/Dashboard').then(module => ({ default: module.Dashboard })))
const Operations = lazy(() => import('./pages/Operations').then(module => ({ default: module.Operations })))
const SessionSettings = lazy(() => import('./pages/SessionSettings').then(module => ({ default: module.SessionSettings })))
const Players = lazy(() => import('./pages/Players').then(module => ({ default: module.Players })))
const Coaches = lazy(() => import('./pages/Coaches').then(module => ({ default: module.Coaches })))
const Academies = lazy(() => import('./pages/Academies').then(module => ({ default: module.Academies })))
const Stadiums = lazy(() => import('./pages/Stadiums').then(module => ({ default: module.Stadiums })))
const Tournaments = lazy(() => import('./pages/Tournaments').then(module => ({ default: module.Tournaments })))
const Communication = lazy(() => import('./pages/Communication').then(module => ({ default: module.Communication })))
const Administration = lazy(() => import('./pages/Administration').then(module => ({ default: module.Administration })))
const Profile = lazy(() => import('./pages/Profile').then(module => ({ default: module.Profile })))
const CreateBooking = lazy(() => import('./components/CreateBooking').then(module => ({ default: module.CreateBooking })))

const copy: Record<Page, [string, string]> = {
  dashboard: ['Vue d’ensemble', 'Voici ce qui se passe dans votre académie aujourd’hui.'],
  bookings: ['Réservations & séances', 'Planifiez et suivez les opérations du club.'],
  sessionSettings: ['Configuration des séances', 'Définissez les tarifs et les tranches d’âge autorisées.'],
  players: ['Joueurs & familles', 'Suivez chaque enfant depuis son inscription.'],
  coaches: ['Équipe des coachs', 'Pilotez les disponibilités et affectations.'],
  academies: ['Académies', 'Gérez les clubs et centres de formation du réseau.'],
  stadiums: ['Stades & terrains', 'Gérez les infrastructures sportives du réseau.'],
  tournaments: ['Tournois', 'Gérez les inscriptions et les préparatifs.'],
  messages: ['Communication', 'Gardez les familles informées et engagées.'],
  administration: ['Administration', 'Gérez les accès et les ressources du réseau.'],
  profile: ['Mon profil', 'Gérez vos informations personnelles et vos préférences.'],
}

export default function App() {
  const { t, language, setLanguage } = useI18n()
  const dispatch = useAppDispatch()
  const authenticated = useAppSelector(state => state.auth.isAuthenticated)
  const authInitialized = useAppSelector(state => state.auth.initialized)
  const permissions = useAppSelector(state => state.auth.user?.permissions ?? [])
  const currentAdmin = useAppSelector(state => state.auth.user)
  const page = useAppSelector(state => state.ui.page)
  const createOpen = useAppSelector(state => state.ui.createBookingOpen)
  const toast = useAppSelector(state => state.ui.toast)
  const bookings = useAppSelector(bookingSelectors.selectAll)
  const [searchQuery, setSearchQuery] = useState('')
  const deferredSearchQuery = useDeferredValue(searchQuery)
  const languageAppliedFor = useRef('')
  const pendingBookings = bookings.filter(booking => booking.status === 'En attente').length
  const playerCount = new Set(bookings.map(booking => booking.student)).size
  const currentDate = new Intl.DateTimeFormat(localeFor(language), { weekday: 'long', day: 'numeric', month: 'long' })
    .format(new Date()).toLocaleUpperCase(localeFor(language))
  useEffect(() => {
    let unsubscribeProfile: (() => void) | undefined
    const unsubscribeAuth = onAuthStateChanged(auth, firebaseUser => {
      unsubscribeProfile?.()
      if (!firebaseUser) { dispatch(firebaseSessionResolved(null)); return }
      unsubscribeProfile = subscribeToAdminProfile(firebaseUser, admin => {
        dispatch(firebaseSessionResolved(admin))
        if (!admin) void logoutFromFirebase()
      })
    })
    return () => { unsubscribeProfile?.(); unsubscribeAuth() }
  }, [dispatch])
  useEffect(() => currentAdmin ? subscribeBookings(currentAdmin, language, rows => dispatch(bookingsReceived(rows))) : undefined, [currentAdmin, dispatch, language])
  useEffect(() => {
    if (currentAdmin?.uid && languageAppliedFor.current !== currentAdmin.uid) {
      languageAppliedFor.current = currentAdmin.uid
      if (currentAdmin.preferredLanguage && currentAdmin.preferredLanguage !== language) setLanguage(currentAdmin.preferredLanguage)
    }
  }, [currentAdmin?.uid, currentAdmin?.preferredLanguage, language, setLanguage])
  useEffect(() => {
    const required: Partial<Record<Page, string>> = { administration: 'admins.manage', academies: 'academies.manage', stadiums: 'stadiums.manage', coaches: 'coaches.manage' }
    const permission = required[page]
    if (permission && !permissions.includes(permission)) dispatch(pageChanged('dashboard'))
    if (page === 'sessionSettings' && !permissions.includes('sessions.manage') && !permissions.includes('academies.manage')) dispatch(pageChanged('dashboard'))
    if (page === 'messages') dispatch(pageChanged('dashboard'))
  }, [dispatch, page, permissions])

  if (!authInitialized) return <Stack minHeight="100vh" alignItems="center" justifyContent="center"><CircularProgress /></Stack>
  if (!authenticated) return <AdminLogin />

  return (
    <AdminShell page={page} pendingBookings={pendingBookings} playerCount={playerCount} searchQuery={searchQuery} onSearchChange={setSearchQuery} onNavigate={target => dispatch(pageChanged(target))} onLogout={async () => { await logoutFromFirebase(); dispatch(loggedOut()); dispatch(uiReset()) }}>
      <Box sx={{
        mb: { xs: 3, md: 4 }, p: { xs: 2.5, sm: 3.5 },
        borderRadius: 5, color: 'white', overflow: 'hidden', position: 'relative',
        background: 'linear-gradient(120deg, #111111 0%, #1D3049 70%, #286384 100%)',
        boxShadow: '0 18px 45px rgba(16,35,63,.16)',
      }}>
        <Box sx={{ position: 'absolute', width: 190, height: 190, borderRadius: '50%', bgcolor: 'rgba(91,192,235,.13)', right: -45, top: -80 }} />
        <Stack direction={{ xs: 'column', sm: 'row' }} justifyContent="space-between" alignItems={{ sm: 'center' }} gap={2} position="relative">
          <Box>
            <Typography variant="overline" sx={{ color: '#5BC0EB', fontWeight: 800, letterSpacing: 1.2 }}>{currentDate}</Typography>
            <Typography variant="h4" sx={{ color: 'white', mt: 0.4 }}>{page === 'dashboard' ? `${t('Bonjour')} ${currentAdmin?.name ?? ''} 👋` : t(copy[page][0])}</Typography>
            <Typography sx={{ color: 'rgba(255,255,255,.67)', mt: 0.8 }}>{t(copy[page][1])}</Typography>
          </Box>
          {(page === 'dashboard' || page === 'bookings') && <Button variant="contained" startIcon={<AddRounded />} onClick={() => dispatch(bookingDialogOpened())}
            sx={{ bgcolor: 'white', color: '#111', px: 2.5, '&:hover': { bgcolor: '#EAF8FD' } }}>{t('Nouvelle réservation')}</Button>}
        </Stack>
      </Box>
      <Suspense fallback={<Stack alignItems="center" py={10}><CircularProgress /></Stack>}>
        {page === 'dashboard' && <Dashboard bookings={bookings} navigate={target => dispatch(pageChanged(target))} />}
        {page === 'bookings' && <Operations bookings={bookings} searchQuery={deferredSearchQuery} onDecision={async (id, decision) => { await decideFirebaseBooking(id, decision); dispatch(toastShown(t(decision === 'approve' ? 'Réservation approuvée' : 'Réservation refusée'))) }} onComplete={async id => { await completeFirebaseBooking(id); dispatch(toastShown(t('Réservation terminée'))) }} />}
        {page === 'sessionSettings' && <SessionSettings notify={message => dispatch(toastShown(message))} />}
        {page === 'players' && <Players searchQuery={deferredSearchQuery} />}
        {page === 'coaches' && <Coaches searchQuery={deferredSearchQuery} notify={message => dispatch(toastShown(message))} />}
        {page === 'academies' && <Academies searchQuery={deferredSearchQuery} notify={message => dispatch(toastShown(message))} />}
        {page === 'stadiums' && <Stadiums searchQuery={deferredSearchQuery} notify={message => dispatch(toastShown(message))} />}
        {page === 'tournaments' && <Tournaments searchQuery={deferredSearchQuery} notify={message => dispatch(toastShown(message))} />}
        {page === 'messages' && <Communication notify={message => dispatch(toastShown(message))} />}
        {page === 'administration' && <Administration searchQuery={deferredSearchQuery} notify={message => dispatch(toastShown(message))} />}
        {page === 'profile' && <Profile notify={message => dispatch(toastShown(message))} />}
        {createOpen && <CreateBooking open={createOpen} onClose={() => dispatch(bookingDialogClosed())} onCreated={() => { dispatch(bookingDialogClosed()); dispatch(toastShown(t('Réservation créée avec succès'))) }} />}
      </Suspense>
      <Snackbar open={Boolean(toast)} autoHideDuration={3200} onClose={() => dispatch(toastClosed())} message={toast} />
    </AdminShell>
  )
}
