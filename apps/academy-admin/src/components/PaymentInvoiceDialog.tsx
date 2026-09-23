import { useRef, useState } from 'react'
import { Alert, Button, Dialog, DialogActions, DialogContent, DialogTitle } from '@mui/material'
import { useI18n } from '../i18n'
import { invoiceHtml, type PaymentInvoice } from '../utils/paymentInvoice'
import { createInvoicePdf, downloadInvoiceFile, shareInvoiceFile } from '../utils/invoicePdf'

export function PaymentInvoiceDialog({ invoice, onClose }: { invoice: PaymentInvoice | null; onClose: () => void }) {
  const { t, language } = useI18n()
  const frame = useRef<HTMLIFrameElement>(null)
  const [sharing, setSharing] = useState(false)
  const [notice, setNotice] = useState('')
  const [error, setError] = useState('')
  const close = () => { setNotice(''); setError(''); onClose() }
  const download = () => {
    if (!invoice) return
    setError(''); setNotice('')
    try { downloadInvoiceFile(createInvoicePdf(invoice, t, language)) }
    catch { setError('Impossible de créer le PDF. Vous pouvez utiliser l’impression.') }
  }
  const share = async () => {
    if (!invoice || sharing) return
    setSharing(true); setError(''); setNotice('')
    try {
      const result = await shareInvoiceFile(createInvoicePdf(invoice, t, language))
      if (result === 'downloaded') setNotice('Le partage direct n’est pas disponible. Le PDF a été téléchargé : joignez-le à votre message au client.')
    } catch { setError('Le partage a échoué. Téléchargez le PDF pour le joindre à votre message.') }
    finally { setSharing(false) }
  }
  return <Dialog open={Boolean(invoice)} onClose={sharing ? undefined : close} fullWidth maxWidth="md">
    <DialogTitle>{t('Facture acquittée')}</DialogTitle>
    <DialogContent>
      <Alert severity="info" sx={{ mb: 2 }}>{t('La facture est imprimée, téléchargée et partagée dans la langue actuelle de l’administration.')}</Alert>
      {notice && <Alert severity="info" sx={{ mb: 2 }}>{t(notice)}</Alert>}
      {error && <Alert severity="error" sx={{ mb: 2 }}>{t(error)}</Alert>}
      {invoice && <iframe ref={frame} title={t('Facture')} srcDoc={invoiceHtml(invoice, t, language)} style={{ width: '100%', height: '60vh', border: '1px solid #dbe1e8', background: 'white' }} />}
    </DialogContent>
    <DialogActions sx={{ flexWrap: 'wrap', gap: 1 }}>
      <Button disabled={sharing} onClick={close}>{t('Fermer')}</Button>
      <Button onClick={() => { frame.current?.contentWindow?.focus(); frame.current?.contentWindow?.print() }}>{t('Imprimer')}</Button>
      <Button onClick={download}>{t('Télécharger le PDF')}</Button>
      <Button variant="contained" disabled={sharing || !invoice} onClick={() => void share()}>{t(sharing ? 'Ouverture du partage…' : 'Partager la facture')}</Button>
    </DialogActions>
  </Dialog>
}
