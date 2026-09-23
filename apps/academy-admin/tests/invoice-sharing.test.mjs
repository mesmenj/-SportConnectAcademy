import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import { File } from 'node:buffer'
import test from 'node:test'
import vm from 'node:vm'
import ts from 'typescript'
const require = createRequire(import.meta.url)
const compile = file => ts.transpileModule(readFileSync(new URL(file, import.meta.url), 'utf8'), { compilerOptions: { module: ts.ModuleKind.CommonJS } }).outputText
const content = {}
vm.runInNewContext(compile('../src/utils/paymentInvoice.ts'), { exports: content })
const translation = {}
vm.runInNewContext(ts.transpileModule(readFileSync(new URL('../src/i18n.tsx', import.meta.url), 'utf8') + '\nexport { translate };', { compilerOptions: { module: ts.ModuleKind.CommonJS, jsx: ts.JsxEmit.ReactJSX } }).outputText, { exports: translation, require: () => ({ createContext: () => ({}) }) })
const source = compile('../src/utils/invoicePdf.ts')
const invoice = { number: 'CASH-123', issuedAt: '2026-09-22T12:00:00Z', playerName: 'Alice', issuerName: 'Académie', issuerAddress: 'Dubai', customerName: 'Parent', customerEmail: 'a@example.com', customerPhone: '+123', sessionCount: 10, activity: 'tennis', amount: 1500, currency: 'AED' }
function fixture(navigator = {}) {
  const exports = {}; let downloads = 0; const revoked = []
  vm.runInNewContext(source, { exports, File, Error, require: name => name === './paymentInvoice' ? content : require(name), navigator, URL: { createObjectURL: () => 'blob:invoice', revokeObjectURL: url => revoked.push(url) }, document: { body: { appendChild() {} }, createElement: () => ({ click() { downloads++ }, remove() {} }) }, window: { setTimeout: fn => fn() } })
  return { ...exports, get downloads() { return downloads }, revoked }
}
test('generates actual PDF files in French and English with localized labels and totals', async () => {
  const f = fixture()
  for (const language of ['fr', 'en']) {
    const file = f.createInvoicePdf(invoice, value => translation.translate(value, language), language)
    assert.equal(file.type, 'application/pdf')
    assert.ok(file.name.endsWith(`-${language}.pdf`))
    const pdf = Buffer.from(await file.arrayBuffer()).toString('latin1')
    assert.ok(pdf.startsWith('%PDF-'))
    for (const value of ['CASH-123', 'Alice', 'a@example.com', language === 'fr' ? 'Facture acquittée' : 'Paid invoice', language === 'fr' ? '1 500,00 AED' : '1,500.00 AED']) assert.ok(pdf.includes(value), value)
  }
})
test('native sharing receives the actual PDF attachment', async () => {
  let shared
  const f = fixture({ canShare: data => data.files[0].type === 'application/pdf', share: async data => { shared = data } })
  const file = new File(['pdf'], 'invoice.pdf', { type: 'application/pdf' })
  assert.equal(await f.shareInvoiceFile(file), 'shared')
  assert.equal(shared.files[0], file)
  assert.equal(f.downloads, 0)
})
test('unsupported sharing downloads the invoice and cleans up its object URL', async () => {
  for (const navigator of [{}, { share() { assert.fail() }, canShare: () => false }]) {
    const f = fixture(navigator)
    assert.equal(await f.shareInvoiceFile(new File(['pdf'], 'invoice.pdf')), 'downloaded')
    assert.equal(f.downloads, 1)
    assert.deepEqual(f.revoked, ['blob:invoice'])
  }
})
test('cancelling sharing does not download or report success; actual errors propagate', async () => {
  for (const name of ['AbortError', 'NotAllowedError']) {
    const error = Object.assign(new Error('share'), { name })
    const f = fixture({ canShare: () => true, share: async () => { throw error } })
    const result = f.shareInvoiceFile(new File(['pdf'], 'invoice.pdf'))
    if (name === 'AbortError') assert.equal(await result, 'cancelled')
    else await assert.rejects(result, { name })
    assert.equal(f.downloads, 0)
  }
})
