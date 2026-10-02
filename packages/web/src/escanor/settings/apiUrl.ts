const LOCAL_HOSTS = new Set(['localhost', '127.0.0.1', '[::1]', '10.0.2.2']); // this device, and the Android emulator's name for the computer it runs on

export type ApiUrlCheck = { ok: true; url: string } | { ok: false; reason: string };

/**
 * Whether a server address typed into Developer settings is acceptable. The app sends the person's sign-in to whatever is set here,
 * so it must be https (plain http only for this device) and a bare address: no credentials, query or fragment.
 */
export function checkApiUrl(raw: string): ApiUrlCheck {
  const text = raw.trim();
  let u: URL;
  try {
    u = new URL(text);
  } catch {
    return { ok: false, reason: 'That is not a web address. It should look like https://api.example.com' };
  }
  if (u.username || u.password) return { ok: false, reason: 'Do not put a username or password in the address.' };
  if (u.search || u.hash) return { ok: false, reason: 'Leave out anything after the address (no ? or #).' };
  if (!u.hostname) return { ok: false, reason: 'That address has no server name.' };
  if (u.protocol === 'http:' ? !LOCAL_HOSTS.has(u.hostname) : u.protocol !== 'https:') {
    return { ok: false, reason: u.protocol === 'http:' ? 'Use https://. Plain http is only allowed for localhost, because your sign-in is sent to this server.' : 'The address must start with https://.' };
  }
  const path = u.pathname.replace(/\/+$/, '');
  return { ok: true, url: `${u.origin}${path || '/api/v1'}` };
}
