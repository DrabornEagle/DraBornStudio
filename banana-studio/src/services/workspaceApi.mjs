// Public endpoint configuration only. Provider keys remain on the dedicated server.
const PREFIX = '/api/banana-studio';
export const BROWSER_SETUP_MESSAGE = 'AI araçları ve bulut paylaşımı için özel Banana-edits sunucusu ve sağlayıcı anahtarı kurulmalıdır. Yerel galerin kullanılabilir.';
let apiBase = PREFIX;
let browserOnly = false;

export function validateApiBase(value, pageOrigin) {
  if (typeof value !== 'string' || !value.trim() || value.startsWith('//')) throw new Error('Invalid workspace API address.');
  const url = new URL(value, pageOrigin);
  if ((url.protocol !== 'https:' && url.origin !== pageOrigin) || url.username || url.password || url.search || url.hash) throw new Error('Invalid workspace API address.');
  return url.href.replace(/\/$/, '');
}

export async function initializeWorkspaceApi() {
  const response = await fetch(new URL('/Banana-edits/workspace.json', location.origin), {
    cache: 'no-store', credentials: 'same-origin', signal: AbortSignal.timeout(5000),
  }).catch(() => null);
  if (response?.ok && response.headers.get('content-type')?.includes('application/json')) {
    const config = await response.json();
    apiBase = validateApiBase(config.apiBase, location.origin);
    browserOnly = config.mode === 'browser';
  }
  return browserOnly;
}

/** @returns {typeof fetch} */
export function createWorkspaceFetch({ getMode, getApiBase, getOrigin, fetchImpl }) {
  return async (input, options = {}) => {
    if (typeof input !== 'string' || !input.startsWith(PREFIX + '/')) return fetchImpl(input, options);
    options.signal?.throwIfAborted();
    const route = input.slice(PREFIX.length + 1).split('?')[0];
    if (getMode() === 'browser' && route !== 'workspace-config') {
      const status = ['gemini-status', 'youtube-status'].includes(route) && (!options.method || options.method === 'GET');
      return new Response(JSON.stringify(status ? { configured: false, providers: {} } : { error: BROWSER_SETUP_MESSAGE, code: 'BANANA_SETUP_REQUIRED' }), {
        status: status ? 200 : 503, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
      });
    }
    const target = new URL(validateApiBase(getApiBase(), getOrigin()) + input.slice(PREFIX.length));
    return fetchImpl(target.href, { ...options, redirect: 'error', credentials: target.origin === getOrigin() ? options.credentials || 'same-origin' : 'omit' });
  };
}

export const workspaceFetch = createWorkspaceFetch({
  getMode: () => browserOnly ? 'browser' : window.__BANANA_STUDIO_CONFIG__?.mode,
  getApiBase: () => apiBase,
  getOrigin: () => location.origin,
  fetchImpl: (input, options) => fetch(input, options),
});
