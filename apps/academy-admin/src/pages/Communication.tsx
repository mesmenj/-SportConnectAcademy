import { useState } from 'react'
import { Avatar, Badge, Box, Button, Card, CardContent, Divider, InputAdornment, List, ListItemButton, ListItemText, Stack, TextField, Typography } from '@mui/material'
import { SearchRounded } from '@mui/icons-material'
import { colors } from '../theme'
import { useI18n } from '../i18n'

const conversations = [
  ['DK', 'Coach David', 'Lucas a fait une très belle séance aujourd’hui.', '10:42', 2, colors.blue],
  ['EN', 'Mme Ngono', 'Merci pour les photos !', '09:18', 1, colors.lilac],
  ['U10', 'Parents · Groupe U10', 'Sophie : Je peux apporter les boissons.', 'Hier', 5, colors.orange],
  ['EM', 'Coach Émilie', 'Le compte-rendu est disponible.', 'Hier', 0, colors.green],
] as const
export function Communication({ notify }: { notify: (message: string) => void }) {
  const { t } = useI18n()
  const [message, setMessage] = useState('')
  return <Box sx={{ display: 'grid', gridTemplateColumns: { xs: '1fr', lg: '380px 1fr' }, gap: 2 }}>
    <Card><CardContent><TextField fullWidth placeholder={t('Rechercher...')} InputProps={{ startAdornment: <InputAdornment position="start"><SearchRounded /></InputAdornment> }} />
      <List>{conversations.map(chat => <ListItemButton key={chat[1]} sx={{ borderRadius: 3, py: 1.4 }}><Badge badgeContent={chat[4]} color="primary"><Avatar sx={{ bgcolor: chat[5] }}>{chat[0]}</Avatar></Badge><ListItemText sx={{ ml: 1.5 }} primary={t(chat[1])} secondary={t(chat[2])} primaryTypographyProps={{ fontWeight: 800, fontSize: 13 }} secondaryTypographyProps={{ noWrap: true, fontSize: 11 }} /><Typography variant="caption">{t(chat[3])}</Typography></ListItemButton>)}</List>
    </CardContent></Card>
    <Card><CardContent sx={{ height: 530, display: 'flex', flexDirection: 'column' }}>
      <Stack direction="row" alignItems="center" gap={1.5}><Avatar sx={{ bgcolor: colors.blue }}>DK</Avatar><Box><Typography fontWeight={800}>Coach David</Typography><Typography variant="caption" color="success.main">● {t('En ligne')}</Typography></Box></Stack><Divider sx={{ my: 2 }} />
      <Stack flex={1} justifyContent="flex-end" gap={1.2}>{['Bonjour Sophie, Lucas a été très concentré aujourd’hui.', 'Son coup droit progresse vraiment bien 🎾', 'Merci David ! Il était très fier de sa séance.'].map((text, index) => <Box key={text} alignSelf={index === 2 ? 'flex-end' : 'flex-start'} maxWidth="75%" p={1.5} borderRadius={3} bgcolor={index === 2 ? colors.ink : colors.cloud} color={index === 2 ? 'white' : 'inherit'}><Typography variant="body2">{t(text)}</Typography></Box>)}</Stack>
      <Stack direction="row" gap={1} mt={2}><TextField fullWidth value={message} onChange={e => setMessage(e.target.value)} placeholder={t('Écrire un message...')} /><Button variant="contained" onClick={() => { if (message.trim()) { notify(t('Message envoyé')); setMessage('') } }}>{t('Envoyer')}</Button></Stack>
    </CardContent></Card>
  </Box>
}
