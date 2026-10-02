export interface AuthSession { access_token: string; refresh_token: string; expires_in: number; expires_at?: number; user: { id: string; email?: string } }
export interface Invitation { id: string; token: string; tokenHash: string; type: 'invite' | 'magiclink' }
export function parseInvitationFragment(fragment: string): Invitation;
export function createAuthClient(config: { url: string; anonKey: string; fetcher?: typeof fetch }): {
 signIn(email: string, password: string): Promise<AuthSession>;
 refresh(token: string): Promise<AuthSession>;
 signOut(token: string): Promise<null>;
 requestPasswordReset(email: string, redirect: string): Promise<null>;
 verifyEmailToken(token: string, type: string): Promise<AuthSession>;
 updatePassword(token: string, password: string, nonce?: string): Promise<unknown>;
 acceptInvitation(token: string, invitation: Invitation, name: string, language: string, operation: string): Promise<{ academy_id: string }>;
};
