// Framework-neutral Auth transport for phase 4 clients. Tokens stay in caller-owned
// memory; this module never stores credentials, uses service keys, or accepts roles.
export function createAuthClient({ url, anonKey, fetcher = fetch }) {
  const send = async (path, body, accessToken, method = 'POST') => {
    const result = await fetcher(`${url}/auth/v1${path}`, { method,
      headers: { apikey: anonKey, 'Content-Type': 'application/json', ...(accessToken ? { Authorization: `Bearer ${accessToken}` } : {}) },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }), signal: AbortSignal.timeout(15000),
    });
    if (!result.ok) throw new Error(`AUTH_${result.status}`);
    if (result.status === 204 || result.headers.get('content-length') === '0') return null;
    const text = await result.text(); return text ? JSON.parse(text) : null;
  };
  return {
    signIn: (email, password) => send('/token?grant_type=password', { email, password }),
    refresh: refreshToken => send('/token?grant_type=refresh_token', { refresh_token: refreshToken }),
    signOut: accessToken => send('/logout', undefined, accessToken),
    requestPasswordReset: (email, redirectTo) => send(`/recover?redirect_to=${encodeURIComponent(redirectTo)}`, { email }),
    verifyEmailToken: (tokenHash, type) => {
      if (!['invite', 'magiclink', 'recovery'].includes(type)) throw new Error('INVALID_AUTH_ACTION');
      return send('/verify', { token_hash: tokenHash, type });
    },
    updatePassword: (accessToken, password, nonce) => send('/user', { password, ...(nonce ? { nonce } : {}) }, accessToken, 'PUT'),
    acceptInvitation: async (accessToken, invitation, displayName, language, operationKey) => {
      const res = await fetcher(`${url}/rest/v1/rpc/accept_invitation`, { method: 'POST',
        headers: { apikey: anonKey, Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ p_invitation: invitation.id, p_token: invitation.token, p_display_name: displayName,
          p_language: language, p_operation_key: operationKey }), signal: AbortSignal.timeout(15000),
      });
      if (!res.ok) throw new Error('INVITATION_REJECTED'); return res.json();
    },
  };
}
// Call immediately on callback entry, then remove the fragment with history.replaceState.
// No server access log receives these secrets. Never render them into the page.
export function parseInvitationFragment(fragment) {
  const p = new URLSearchParams(fragment.replace(/^#/, ''));
  const id = p.get('invitation'), token = p.get('token'), tokenHash = p.get('token_hash'), type = p.get('type');
  if (!/^[0-9a-f-]{36}$/i.test(id ?? '') || !/^[0-9a-f]{64}$/.test(token ?? '') || !tokenHash || !['invite', 'magiclink'].includes(type)) throw new Error('INVALID_INVITATION');
  return { id, token, tokenHash, type };
}
