export function normalizeSearch(value: unknown): string {
  return String(value ?? '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLocaleLowerCase()
    .trim()
}

export function matchesSearch(query: string, ...values: unknown[]): boolean {
  const normalizedQuery = normalizeSearch(query)
  if (!normalizedQuery) return true
  return normalizeSearch(values.flat(Infinity).join(' ')).includes(normalizedQuery)
}
