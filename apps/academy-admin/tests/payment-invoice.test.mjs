import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import vm from 'node:vm'
import ts from 'typescript'
const source = ts.transpileModule(readFileSync(new URL('../src/utils/paymentInvoice.ts', import.meta.url), 'utf8'), { compilerOptions: { module: ts.ModuleKind.CommonJS } }).outputText
const exports = {}
vm.runInNewContext(source, { exports })
const invoice = { number: 'CASH-player', issuedAt: '2026-09-22T12:00:00Z', playerName: '<script>alert(1)</script>', issuerName: 'Academy & club', issuerAddress: 'Dubai', customerName: 'Parent', customerEmail: 'p@example.com', customerPhone: '+123', sessionCount: 10, activity: 'tennis', amount: 500, currency: 'AED', paymentMethod: 'cash' }
test('printable invoice escapes profile values and contains payment information', () => {
  const html = exports.invoiceHtml(invoice, value => value, 'fr')
  assert.ok(!html.includes('<script>'))
  for (const value of ['&lt;script&gt;', 'Academy &amp; club', 'CASH-player', '22/09/2026', '500,00 AED', '10 cours', 'p@example.com', '@media print', 'Solde à payer']) assert.ok(html.includes(value), value)
})
test('missing issuer is stated without inventing billing details', () => {
  const html = exports.invoiceHtml({ ...invoice, issuerName: '', customerName: '', playerName: 'Alice' }, value => value, 'en')
  assert.ok(html.includes('Académie non renseignée'))
  assert.ok(html.includes('Alice'))
  assert.ok(html.includes('500.00 AED'))
})

const translationSource = ts.transpileModule(readFileSync(new URL('../src/i18n.tsx', import.meta.url), 'utf8') + '\nexport { translate };', { compilerOptions: { module: ts.ModuleKind.CommonJS, jsx: ts.JsxEmit.ReactJSX } }).outputText
const translations = {}
vm.runInNewContext(translationSource, { exports: translations, require: () => ({ createContext: () => ({}) }) })
const translate = language => value => translations.translate(value, language)
test('invoice labels and activity use real French and English translations without changing customer names', () => {
  const data = { ...invoice, activity: 'padel', customerName: 'Famille Joueur' }
  const fr = exports.invoiceHtml(data, translate('fr'), 'fr')
  const en = exports.invoiceHtml(data, translate('en'), 'en')
  for (const text of ['Facture acquittée', 'Date du paiement', '10 cours', 'Padel', '500,00 AED']) assert.ok(fr.includes(text), text)
  for (const text of ['Paid invoice', 'Payment date', 'Payment confirmed', 'Issuer', 'Customer', 'Player', 'Package', '10 lessons', 'Padel', 'Amount paid', 'Total paid', 'Balance due', '500.00 AED', 'Famille Joueur']) assert.ok(en.includes(text), text)
  for (const text of ['Facture acquittée', 'Date du paiement', 'Montant payé', 'Solde à payer', '10 cours']) assert.ok(!en.includes(text), text)
})
