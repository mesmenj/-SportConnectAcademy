export interface PaymentInvoice {
  number: string
  issuedAt: string
  playerName: string
  issuerName: string
  issuerAddress: string
  customerName: string
  customerEmail: string
  customerPhone: string
  sessionCount: number
  activity: string
  amount: number
  currency: string
  paymentMethod: string
}

export const invoiceActivity = (activity: string, t: (key: string) => string) => t(({ tennis: 'Tennis', padel: 'Padel', paddle: 'Padel' } as Record<string, string>)[activity.toLowerCase()] ?? activity)

const escapeHtml = (value: unknown) => String(value ?? '').replace(/[&<>"']/g, character => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[character]!)

export function invoiceHtml(invoice: PaymentInvoice, t: (key: string) => string, language: string) {
  const e = escapeHtml
  const label = (key: string) => e(t(key))
  const date = new Date(invoice.issuedAt).toLocaleDateString(language === 'en' ? 'en-GB' : 'fr-FR')
  const amount = `${invoice.amount.toLocaleString(language === 'en' ? 'en-GB' : 'fr-FR', { minimumFractionDigits: 2, maximumFractionDigits: 2 })} ${invoice.currency}`
  return `<!doctype html><html lang="${language === 'en' ? 'en' : 'fr'}"><head><meta charset="utf-8"><title>${label('Facture')} ${e(invoice.number)}</title><style>
  body{font:15px Arial,sans-serif;color:#182437;margin:0;padding:36px;line-height:1.6}h1{font-size:28px;margin-bottom:4px}h2{font-size:16px;margin-top:28px}p{margin:4px 0;overflow-wrap:anywhere}.paid{color:#167045;font-weight:bold}table{width:100%;border-collapse:collapse;margin-top:28px}th,td{text-align:left;padding:12px 6px;border-bottom:1px solid #dbe1e8}th:last-child,td:last-child{text-align:right}.total{text-align:right;font-size:20px;font-weight:bold;margin-top:24px}.note{font-size:12px;color:#586579;margin-top:36px}@page{size:A4;margin:16mm}@media print{body{padding:0}table{break-inside:avoid}}
  </style></head><body><h1>${label('Facture acquittée')}</h1><p>${label('Référence')} : ${e(invoice.number)}</p><p>${label('Date du paiement')} : ${e(date)}</p><p class="paid">${label('Paiement confirmé — espèces')}</p>
  <h2>${label('Émetteur')}</h2><p>${e(invoice.issuerName || t('Académie non renseignée'))}</p><p>${e(invoice.issuerAddress)}</p>
  <h2>${label('Client')}</h2><p>${e(invoice.customerName || invoice.playerName)}</p><p>${e(invoice.customerEmail)}</p><p>${e(invoice.customerPhone)}</p><p>${label('Joueur')} : ${e(invoice.playerName)}</p>
  <table><thead><tr><th>${label('Description')}</th><th>${label('Montant payé')}</th></tr></thead><tbody><tr><td>${label('Forfait')} · ${e(invoice.sessionCount)} ${label('cours')}${invoice.activity ? ` · ${e(invoiceActivity(invoice.activity, t))}` : ''}</td><td>${e(amount)}</td></tr></tbody></table><p class="total">${label('Total payé')} : ${e(amount)}</p><p>${label('Solde à payer')} : 0 ${e(invoice.currency)}</p><p class="note">${label('Document établi à partir du paiement confirmé. Aucun détail de taxe n’est enregistré pour ce paiement.')}</p></body></html>`
}
