import { type FormEvent, useState } from 'react'
import { Alert, Avatar, Box, Button, Card, CardContent, CircularProgress, IconButton, InputAdornment, Stack, TextField, Typography } from '@mui/material'
import { ArrowForwardRounded, EmailRounded, LanguageRounded, LockRounded, SportsTennisRounded, VisibilityOffRounded, VisibilityRounded } from '@mui/icons-material'
import { colors } from '../theme'
import { useI18n } from '../i18n'
import { loginSucceeded } from '../store/authSlice'
import { useAppDispatch } from '../store/hooks'
import { loginWithFirebase } from '../services/authService'

export function AdminLogin() {
  const { language, setLanguage, t } = useI18n()
  const dispatch = useAppDispatch()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [loading, setLoading] = useState(false)
  const [showPassword, setShowPassword] = useState(false)
  const [error, setError] = useState('')

  const submit = async (event: FormEvent) => {
    event.preventDefault()
    setLoading(true)
    setError('')
    try {
      const user = await loginWithFirebase(email, password, false)
      dispatch(loginSucceeded({ user, remember: false }))
    } catch (reason) {
      const code = typeof reason === 'object' && reason && 'code' in reason ? String(reason.code) : reason instanceof Error ? reason.message : ''
      setError(t(code === 'auth/not-admin' ? 'Ce compte ne possède pas les droits administrateur.' : 'Adresse e-mail ou mot de passe incorrect.'))
    } finally {
      setLoading(false)
    }
  }

  return <Box sx={{ minHeight: '100vh', display: 'grid', gridTemplateColumns: { xs: '1fr', lg: '1.1fr .9fr' }, bgcolor: 'white' }}>
    <Box sx={{ display: { xs: 'none', lg: 'flex' }, position: 'relative', overflow: 'hidden', bgcolor: colors.ink, color: 'white', p: 7, flexDirection: 'column', justifyContent: 'space-between' }}>
      <Box sx={{ position: 'absolute', width: 500, height: 500, borderRadius: '50%', bgcolor: 'rgba(91,192,235,.10)', right: -180, top: -150 }} />
      <Box sx={{ position: 'absolute', width: 320, height: 320, border: '1px solid rgba(255,255,255,.08)', borderRadius: '50%', left: -120, bottom: -100 }} />
      <Stack direction="row" alignItems="center" gap={1.5} position="relative">
        <Avatar variant="rounded" sx={{ bgcolor: colors.sky, color: colors.ink }}><SportsTennisRounded /></Avatar>
        <Stack direction="row" alignItems="center" gap={1.2}><Box component="img" src="/challengeme-academy-logo.jpg" alt="SportA" sx={{ width: 58, height: 58, objectFit: 'contain', borderRadius: 2, bgcolor: 'white' }} /><Box><Typography fontWeight={900} fontSize={20} letterSpacing={-0.8}>SportA</Typography><Typography variant="caption" sx={{ opacity: .55 }}>{t('ADMINISTRATION')}</Typography></Box></Stack>
      </Stack>
      <Box position="relative" maxWidth={560}>
        <Typography variant="overline" color={colors.sky} fontWeight={900} letterSpacing={1.5}>{t('PILOTEZ VOTRE ACADÉMIE')}</Typography>
        <Typography sx={{ fontSize: 48, lineHeight: 1.08, fontWeight: 900, letterSpacing: -2, mt: 2 }}>{t('Chaque cours. Chaque joueur. Au même endroit.')}</Typography>
        <Typography sx={{ color: 'rgba(255,255,255,.62)', mt: 3, maxWidth: 470, lineHeight: 1.8 }}>{t('Réservations, terrains, coachs et familles : gardez une vision claire de votre club au quotidien.')}</Typography>
      </Box>
      {/* <Typography variant="caption" sx={{ opacity: .4 }} position="relative">© 2026 SportA · Douala, Cameroun</Typography> */}
    </Box>

    <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'center', p: { xs: 2.5, sm: 5 }, bgcolor: colors.cloud }}>
      <Card sx={{ width: '100%', maxWidth: 480, boxShadow: '0 24px 70px rgba(16,35,63,.10)' }}>
        <CardContent sx={{ p: { xs: 3, sm: 5 }, '&:last-child': { pb: { xs: 3, sm: 5 } } }}>
          <Avatar variant="rounded" sx={{ display: { lg: 'none' }, bgcolor: colors.ink, color: colors.sky, mb: 3 }}><SportsTennisRounded /></Avatar>
          <Stack direction="row" justifyContent="space-between" alignItems="center" mb={1}>
            <Typography variant="h4">{t('Bon retour 👋')}</Typography>
            <Button size="small" variant="outlined" startIcon={<LanguageRounded />} onClick={() => setLanguage(language === 'fr' ? 'en' : 'fr')}>{language === 'fr' ? 'EN' : 'FR'}</Button>
          </Stack>
          <Typography color="text.secondary" mt={1} mb={4}>{t('Connectez-vous à l’espace d’administration SportA.')}</Typography>
          <Box component="form" onSubmit={submit} noValidate>
            <Stack gap={2.2}>
              {error && <Alert severity="error" onClose={() => setError('')}>{error}</Alert>}
              <TextField autoFocus fullWidth label={t('Adresse e-mail')} type="email" autoComplete="username" value={email} onChange={event => setEmail(event.target.value)}
                slotProps={{ input: { startAdornment: <InputAdornment position="start"><EmailRounded color="disabled" /></InputAdornment> } }} />
              <TextField fullWidth label={t('Mot de passe')} type={showPassword ? 'text' : 'password'} autoComplete="current-password" value={password} onChange={event => setPassword(event.target.value)}
                slotProps={{ input: { startAdornment: <InputAdornment position="start"><LockRounded color="disabled" /></InputAdornment>, endAdornment: <InputAdornment position="end"><IconButton aria-label={t(showPassword ? 'Masquer le mot de passe' : 'Afficher le mot de passe')} onClick={() => setShowPassword(value => !value)} edge="end">{showPassword ? <VisibilityOffRounded /> : <VisibilityRounded />}</IconButton></InputAdornment> } }} />
              {/* Les options « Se souvenir de moi » et « Mot de passe oublié ? » sont temporairement masquées. */}
              <Button type="submit" variant="contained" size="large" disabled={loading || !email || !password} endIcon={loading ? <CircularProgress size={18} color="inherit" /> : <ArrowForwardRounded />}>{t(loading ? 'Connexion...' : 'Se connecter')}</Button>
            </Stack>
          </Box>
          <Alert severity="info" sx={{ mt: 3 }}>{t('Utilisez votre compte administrateur.')}</Alert>
        </CardContent>
      </Card>
    </Box>
  </Box>
}
