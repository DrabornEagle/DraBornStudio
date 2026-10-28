import {uniqueId} from './browserId.mjs';
import { WorkspaceQuery } from '../../desktop/shared/query.mjs';

// A separate, explicitly local workspace. This never authenticates a cloud call.
const DB = 'banana-studio-browser-v1';
let connection;
const urls = new Map();
const request = req => new Promise((resolve, reject) => { req.onsuccess = () => resolve(req.result); req.onerror = () => reject(req.error); });
async function database() {
  if (!connection) connection = new Promise((resolve, reject) => {
    const req = indexedDB.open(DB, 1);
    req.onupgradeneeded = () => {
      req.result.createObjectStore('records', { keyPath: 'key' });
      req.result.createObjectStore('settings');
      req.result.createObjectStore('media');
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
  return connection;
}
async function read(store, key) { const db = await database(); return request(db.transaction(store).objectStore(store).get(key)); }
async function write(store, key, value) {
  const db = await database();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(store, 'readwrite');
    const objectStore = tx.objectStore(store);
    if (value === undefined) objectStore.delete(key); else objectStore.put(value, key);
    tx.oncomplete = () => resolve(); tx.onerror = () => reject(tx.error); tx.onabort = () => reject(tx.error);
  });
}
export function browserIdentity() {
  let identity;
  try { identity = JSON.parse(localStorage.getItem(DB + ':identity') || 'null'); } catch { /* A new workspace is safe. */ }
  if (!identity?.userId || !identity?.sessionId) {
    identity = { mode: 'browser', userId: uniqueId(), sessionId: uniqueId() };
    localStorage.setItem(DB + ':identity', JSON.stringify(identity));
  }
  return { ...identity, mode: 'browser' };
}
const field = (row, name) => String(name).split(/->>?/).reduce((value, key) => value?.[key], row);
const pattern = value => new RegExp('^' + String(value).replace(/\\([\\%_])|([%_])|([.*+?^${}()|[\]\\])/g,
  (_, escaped, wild, special) => escaped ? escaped.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') : wild === '%' ? '.*' : wild === '_' ? '.' : '\\' + special) + '$', 'i');
export function matches(row, { column, operator, value }) {
  if (operator.startsWith('not.')) return !matches(row, { column, operator: operator.slice(4), value });
  const current = field(row, column);
  switch (operator) {
    case 'eq': return current === value; case 'neq': return current !== value;
    case 'is': return value === null ? current == null : current === value;
    case 'gt': return current > value; case 'gte': return current >= value;
    case 'lt': return current < value; case 'lte': return current <= value;
    case 'in': return value.includes(current);
    case 'ilike': case 'like': return pattern(value).test(String(current ?? ''));
    case 'contains': return Array.isArray(current) && value.every(item => current.includes(item));
    default: throw new Error('Unsupported browser query.');
  }
}
const tables = new Set(['generations', 'folders', 'templates', 'reference_images', 'saved_people', 'usage_logs', 'profiles', 'authorized_emails']);
export function createBrowserWorkspaceClient(identity) {
  const user = { id: identity.userId, email: 'browser@example.invalid', email_confirmed_at: '2026-01-01T00:00:00Z', is_anonymous: false };
  const session = { user, access_token: 'browser-workspace-no-cloud-credential', token_type: 'local', expires_at: 4102444800 };
  const seeded = table => table === 'profiles' ? [{ ...user, display_name: 'Bu tarayıcıdaki çalışma alanım', role: 'user' }]
    : table === 'authorized_emails' ? [{ id: 'browser', email: user.email, is_active: true }] : null;
  async function rpc(name, args = {}) {
    if (name === 'get_provider_preferences') return await read('settings', 'providers') || {};
    if (name === 'save_provider_preference') {
      await write('settings', 'providers', { ...await read('settings', 'providers'), [args.p_model]: args.p_provider }); return true;
    }
    if (name === 'save_text_model_preferences') await write('settings', 'text', { model: args.p_model, thinkingLevel: args.p_gemini_thinking, reasoningEffort: args.p_openai_reasoning });
    if (name === 'get_text_model_preferences' || name === 'save_text_model_preferences') return {
      ...await read('settings', 'text') || { model: 'anthropic/claude-opus-5.5', thinkingLevel: 'MEDIUM', reasoningEffort: 'medium' },
      source: 'personal', canSaveAll: false, revision: 1,
    };
    if (name === 'get_gallery_search_people') {
      const db = await database(); const records = await request(db.transaction('records').objectStore('records').getAll());
      return records.filter(r => r.table === 'generations').map(r => r.value).filter(r => !args.p_after_id || r.id > args.p_after_id)
        .sort((a, b) => a.id.localeCompare(b.id)).slice(0, args.p_limit || 500).map(r => ({ id: r.id, people: [...new Set((r.reference_images || []).map(ref => ref.personName).filter(Boolean))] }));
    }
    throw new Error('Bu özellik sunucuda yapılandırılmış bir bulut çalışma alanı gerektiriyor.');
  }
  const send = async (plan, signal) => {
    if (signal?.aborted) throw new DOMException('Aborted', 'AbortError');
    try {
      if (plan.rpc) return { data: await rpc(plan.rpc, plan.args), error: null };
      if (!tables.has(plan.table)) throw new Error('Unsupported browser collection.');
      const db = await database();
      return await new Promise((resolve, reject) => {
        const tx = db.transaction('records', plan.operation === 'select' ? 'readonly' : 'readwrite');
        const store = tx.objectStore('records'); let result;
        const query = store.getAll();
        query.onsuccess = () => {
          try {
            const all = seeded(plan.table) || query.result.filter(r => r.table === plan.table).map(r => r.value);
            let rows = all.filter(row => (plan.filters || []).every(filter => matches(row, filter)));
            if (plan.or) {
              const filters = plan.or.split(',').map(part => { const [column, operator, ...raw] = part.split('.'); const value = raw.join('.'); return { column, operator, value: value === 'true' ? true : value === 'false' ? false : value }; });
              rows = rows.filter(row => filters.some(filter => matches(row, filter)));
            }
            const put = row => store.put({ key: `${plan.table}:${row.id}`, table: plan.table, value: row });
            if (seeded(plan.table) && plan.operation !== 'select') throw new Error('Local identity is read-only.');
            if (plan.operation === 'insert' || plan.operation === 'upsert') {
              rows = (Array.isArray(plan.value) ? plan.value : [plan.value]).map(value => {
                const row = { created_at: Date.now(), user_id: user.id, is_favorite: false, status: 'completed', reference_images: [], metadata: {}, ...structuredClone(value) };
                row.id ||= uniqueId(); const previous = all.find(r => r.id === row.id);
                if (previous && plan.operation === 'insert') throw new Error('Duplicate row.');
                const merged = { ...previous, ...row }; put(merged); return merged;
              });
            } else if (plan.operation === 'update' || plan.operation === 'delete') {
              if (!plan.filters.length) throw new Error('A filter is required.');
              if (plan.operation === 'update') rows = rows.map(row => { const updated = { ...row, ...structuredClone(plan.value) }; put(updated); return updated; });
              else rows.forEach(row => store.delete(`${plan.table}:${row.id}`));
            }
            const count = rows.length;
            rows.sort((a, b) => { for (const order of plan.order || []) { const x = field(a, order.column), y = field(b, order.column); if (x !== y) return (x < y ? -1 : 1) * (order.ascending === false ? -1 : 1); } return 0; });
            const from = plan.range?.[0] || 0;
            rows = rows.slice(from, plan.range ? plan.range[1] + 1 : from + (plan.limit ?? 10000));
            if (plan.columns && plan.columns !== '*') rows = rows.map(row => Object.fromEntries(plan.columns.split(',').map(column => { const [alias, source = alias] = column.trim().split(':'); return [alias, field(row, source)]; })));
            if (plan.single && (rows.length > 1 || (plan.single === true && !rows.length))) result = { data: null, error: { code: 'PGRST116', message: 'Row not found.' } };
            else result = { data: plan.head ? null : plan.single ? rows[0] ?? null : rows, error: null, ...(plan.count ? { count } : {}) };
          } catch (error) { result = { data: null, error: { message: error?.message || 'Browser storage failed.' } }; tx.abort(); }
        };
        tx.oncomplete = () => resolve(result);
        tx.onerror = () => result ? resolve(result) : reject(tx.error || new Error('Browser transaction failed.'));
        tx.onabort = () => result ? resolve(result) : reject(tx.error || new Error('Browser transaction aborted.'));
      });
    } catch (error) { return { data: null, error: { message: error?.message || 'Browser storage failed.' } }; }
  };
  async function mediaUrl(path) {
    if (urls.has(path)) return urls.get(path);
    const blob = await read('media', path); if (!blob) return '';
    const url = URL.createObjectURL(blob); urls.set(path, url); return url;
  }
  const storage = {
    upload: async (path, value, options = {}) => { try { if (!options.upsert && await read('media', path)) throw new Error('File exists.'); await write('media', path, value instanceof Blob ? value : new Blob([value])); if (urls.has(path)) URL.revokeObjectURL(urls.get(path)); urls.delete(path); return { data: { path }, error: null }; } catch (error) { return { data: null, error: { message: error?.message || 'Browser storage failed.' } }; } },
    download: async path => ({ data: await read('media', path), error: null }),
    createSignedUrl: async path => { const signedUrl = await mediaUrl(path); return { data: signedUrl ? { signedUrl } : null, error: signedUrl ? null : { message: 'File not found.' } }; },
    createSignedUrls: async paths => ({ data: await Promise.all(paths.map(async path => ({ path, signedUrl: await mediaUrl(path) }))), error: null }),
    getPublicUrl: path => ({ data: { publicUrl: `${location.origin}/storage/v1/object/authenticated/media/${path}` } }),
    remove: async paths => { for (const path of paths) { await write('media', path, undefined); if (urls.has(path)) URL.revokeObjectURL(urls.get(path)); urls.delete(path); } return { data: paths, error: null }; },
  };
  return {
    auth: { getSession: async () => ({ data: { session }, error: null }), refreshSession: async () => ({ data: { session }, error: null }), getUser: async () => ({ data: { user }, error: null }), onAuthStateChange: () => ({ data: { subscription: { unsubscribe() {} } } }), stopAutoRefresh() {}, signOut: async () => { globalThis.location?.assign?.('/'); return { error: null }; } },
    from: table => new WorkspaceQuery(send, table), rpc: (name, args = {}) => new WorkspaceQuery(send, undefined, name, args), storage: { from: bucket => { if (bucket !== 'media') throw new Error('Unknown bucket.'); return storage; } },
  };
}
