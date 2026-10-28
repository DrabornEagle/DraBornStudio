export type CloudPublicConfig = { mode: 'cloud'; supabaseUrl: string; supabasePublishableKey: string };

/** Provider and service-role credentials are never public configuration. */
export const validateCloudPublicConfig = (value: unknown): CloudPublicConfig => {
  const input = value as Partial<CloudPublicConfig> | null;
  if (!input || input.mode !== 'cloud' || typeof input.supabaseUrl !== 'string' || typeof input.supabasePublishableKey !== 'string') throw new Error('Workspace configuration is incomplete.');
  const url = new URL(input.supabaseUrl);
  const local = ['localhost', '127.0.0.1', '[::1]'].includes(url.hostname);
  if ((url.protocol !== 'https:' && !(local && url.protocol === 'http:')) || url.username || url.password || url.search || url.hash || url.pathname !== '/') throw new Error('Use the HTTPS URL of your own Supabase project.');
  const key = input.supabasePublishableKey;
  let allowed = /^sb_publishable_[A-Za-z0-9_-]+$/.test(key);
  if (!allowed) {
    try { const payload = JSON.parse(atob(key.split('.')[1].replace(/-/g, '+').replace(/_/g, '/'))); allowed = key.split('.').length === 3 && payload.role === 'anon'; }
    catch { /* Never accept a secret or malformed value as public configuration. */ }
  }
  if (!allowed) throw new Error('Configure a Supabase publishable or legacy anon key, never a secret or service-role key.');
  return { mode: 'cloud', supabaseUrl: url.origin, supabasePublishableKey: key };
};
