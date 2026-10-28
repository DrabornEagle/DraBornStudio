/** Read-only request-level billing; no generation request is ever retried here.
 * https://fal.ai/docs/platform-apis/v1/models/billing-events
 */
const BILLING_EVENTS_URL = 'https://api.fal.ai/v1/models/billing-events';
const nonnegativeNumber = (value: unknown): number | undefined => {
  if (typeof value !== 'number' && (typeof value !== 'string' || !value.trim())) return undefined;
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : undefined;
};
export const parseFalBillingCost = (event: unknown): number | undefined => {
  if (!event || typeof event !== 'object' || Array.isArray(event)) return undefined;
  const row = event as Record<string, unknown>;
  const total = nonnegativeNumber(row.cost_total);
  if (total !== undefined) return total;
  const nanoUsd = nonnegativeNumber(row.cost_estimate_nano_usd);
  return nanoUsd !== undefined ? nanoUsd / 1_000_000_000 : undefined;
};
export interface FalBillingCostOptions {
  timeoutMs?: number;
  start?: string;
  end?: string;
  endpointIds?: readonly string[];
}
/** An empty map means no matching billing event has appeared yet, never zero cost.
 * Any incomplete/failed page rejects the whole read, so callers cannot persist a
 * partial sum as an actual charge. Multiple charge components are pooled per ID.
 */
export const fetchFalRequestCosts = async (
  requestIds: readonly string[], key: string, options: FalBillingCostOptions = {},
): Promise<Map<string, number>> => {
  const ids = [...new Set(requestIds)];
  if (!ids.length) return new Map();
  if (ids.length > 50 || ids.some(id => typeof id !== 'string' || !id || id.length > 200 || id.includes(','))) throw new Error('Invalid fal billing request IDs');
  const billingKey = key.trim().replace(/^Key\s+/i, '').trim();
  if (!billingKey) throw new Error('fal billing key is unavailable');
  const now = Date.now();
  const end = options.end || new Date(now).toISOString();
  const start = options.start || new Date(Date.parse(end) - 90 * 24 * 60 * 60 * 1000).toISOString();
  const period = Date.parse(end) - Date.parse(start);
  if (!Number.isFinite(period) || period <= 0 || period > 90 * 24 * 60 * 60 * 1000) throw new Error('Invalid fal billing reporting period');
  const budget = options.timeoutMs ?? 5000;
  if (!Number.isFinite(budget) || budget <= 0) throw new Error('Invalid fal billing timeout');
  const params = new URLSearchParams({ request_id: ids.join(','), start, end, limit: '1000' });
  const endpoints = options.endpointIds ? new Set(options.endpointIds) : undefined;
  if (endpoints) {
    if (!endpoints.size || endpoints.size > 50 || [...endpoints].some(endpoint => !endpoint || endpoint.includes(','))) throw new Error('Invalid fal billing endpoint filter');
    params.set('endpoint_id', [...endpoints].join(','));
  }
  const wanted = new Set(ids); const costs = new Map<string, number>(); const cursors = new Set<string>();
  const deadline = now + budget;
  for (let page = 0; ; page++) {
    const remaining = deadline - Date.now();
    if (page >= 100 || remaining <= 0) throw new Error('fal billing could not be read completely before its deadline');
    const response = await fetch(`${BILLING_EVENTS_URL}?${params}`, {
      headers: { Authorization: `Key ${billingKey}` }, cache: 'no-store', signal: AbortSignal.timeout(Math.max(1, Math.ceil(remaining))),
    });
    if (!response.ok) throw new Error(`fal billing lookup failed (${response.status})`);
    const data = await response.json().catch(() => null);
    if (!Array.isArray(data?.billing_events) || typeof data.has_more !== 'boolean'
      || !(data.next_cursor === null || typeof data.next_cursor === 'string' && data.next_cursor.length > 0)
      || data.has_more !== (data.next_cursor !== null)) throw new Error('fal billing returned incomplete pagination');
    for (const event of data.billing_events) {
      if (!event || typeof event.request_id !== 'string') throw new Error('fal billing returned an invalid event');
      if (!wanted.has(event.request_id)) continue;
      if (endpoints && !endpoints.has(event.endpoint_id)) continue;
      const cost = parseFalBillingCost(event);
      if (cost === undefined) throw new Error('fal billing returned an unknown request cost');
      const sum = (costs.get(event.request_id) ?? 0) + cost;
      if (!Number.isFinite(sum)) throw new Error('fal billing returned an invalid cost total');
      costs.set(event.request_id, sum);
    }
    if (!data.has_more) return costs;
    if (cursors.has(data.next_cursor)) throw new Error('fal billing repeated a pagination cursor');
    cursors.add(data.next_cursor); params.set('cursor', data.next_cursor);
  }
};
