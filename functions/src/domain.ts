export const ROLES = ['owner', 'manager', 'coach', 'parent', 'student'] as const;
export function text(value: unknown, field: string, max = 160): string {
  if (typeof value !== 'string' || !value.trim() || value.trim().length > max) throw new Error(`${field} invalide`);
  return value.trim();
}
export function id(value: unknown): string {
  const result = text(value, 'Identifiant', 100);
  if (!/^[a-zA-Z0-9_-]+$/.test(result)) throw new Error('Identifiant invalide');
  return result;
}
export function positiveInteger(value: unknown, field: string): number {
  if (typeof value !== 'number' || !Number.isSafeInteger(value) || value < 1 || value > 1000000) throw new Error(`${field} invalide`);
  return value;
}
export function planInput(data: Record<string, unknown>) {
  return { name: text(data.name, 'Nom'), maxPlayers: positiveInteger(data.maxPlayers, 'Limite joueurs'), maxStaff: positiveInteger(data.maxStaff, 'Limite équipe'), active: data.active !== false };
}
export function subscriptionIsActive(subscription: { status?: string; endsAt?: { toMillis(): number } } | undefined, now: number): boolean {
  return subscription?.status === 'active' && (subscription.endsAt?.toMillis() ?? 0) > now;
}
