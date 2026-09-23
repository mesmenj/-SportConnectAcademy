import { jsPDF } from 'jspdf'
import { invoiceActivity, type PaymentInvoice } from './paymentInvoice'

export function createInvoicePdf(invoice: PaymentInvoice, t: (key: string) => string, language: string): File {
  const pdf = new jsPDF()
  const locale = language === 'en' ? 'en-GB' : 'fr-FR'
  let y = 22
  const line = (value: string, size = 11, bold = false) => {
    pdf.setFont('helvetica', bold ? 'bold' : 'normal')
    pdf.setFontSize(size)
    const lines: string[] = pdf.splitTextToSize(value.replace(/[\u202f\u00a0]/g, ' '), 170)
    for (const text of lines) {
      if (y > 275) { pdf.addPage(); y = 22 }
      pdf.text(text, 20, y)
      y += size * .48 + 2
    }
  }
  const section = (title: string) => { y += 7; line(t(title), 13, true) }
  pdf.setProperties({ title: `${t('Facture')} ${invoice.number}`, subject: t('Facture acquittée') })
  line(t('Facture acquittée'), 22, true)
  line(`${t('Référence')} : ${invoice.number}`)
  line(`${t('Date du paiement')} : ${new Date(invoice.issuedAt).toLocaleDateString(locale)}`)
  line(t('Paiement confirmé — espèces'))
  section('Émetteur')
  line(invoice.issuerName || t('Académie non renseignée'))
  if (invoice.issuerAddress) line(invoice.issuerAddress)
  section('Client')
  line(invoice.customerName || invoice.playerName)
  if (invoice.customerEmail) line(invoice.customerEmail)
  if (invoice.customerPhone) line(invoice.customerPhone)
  line(`${t('Joueur')} : ${invoice.playerName}`)
  section('Description')
  line(`${t('Forfait')} · ${invoice.sessionCount} ${t('cours')}${invoice.activity ? ` · ${invoiceActivity(invoice.activity, t)}` : ''}`)
  const amount = `${invoice.amount.toLocaleString(locale, { minimumFractionDigits: 2, maximumFractionDigits: 2 })} ${invoice.currency}`
  line(`${t('Montant payé')} : ${amount}`)
  y += 7
  line(`${t('Total payé')} : ${amount}`, 15, true)
  line(`${t('Solde à payer')} : 0 ${invoice.currency}`)
  y += 10
  line(t('Document établi à partir du paiement confirmé. Aucun détail de taxe n’est enregistré pour ce paiement.'), 9)
  const filename = `${t('Facture')}-${invoice.number}-${language}`.replace(/[^a-zA-Z0-9_-]/g, '_')
  return new File([pdf.output('blob')], `${filename}.pdf`, { type: 'application/pdf' })
}

export function downloadInvoiceFile(file: File) {
  const url = URL.createObjectURL(file)
  const anchor = document.createElement('a')
  anchor.href = url
  anchor.download = file.name
  document.body.appendChild(anchor)
  anchor.click()
  anchor.remove()
  window.setTimeout(() => URL.revokeObjectURL(url), 60_000)
}

export async function shareInvoiceFile(file: File): Promise<'shared' | 'downloaded' | 'cancelled'> {
  if (!navigator.share || !navigator.canShare?.({ files: [file] })) {
    downloadInvoiceFile(file)
    return 'downloaded'
  }
  try {
    await navigator.share({ files: [file], title: file.name.replace(/\.pdf$/, '') })
    return 'shared'
  } catch (error) {
    if (error instanceof Error && error.name === 'AbortError') return 'cancelled'
    throw error
  }
}
