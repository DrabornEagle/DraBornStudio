import { createHash, createHmac, timingSafeEqual } from 'node:crypto';
import type { GenerationConfig } from '../../src/types.js';
import { H3_MAX_ENDPOINTS, normalizeH3MaxMode, type H3MaxMode } from '../../src/lib/video/h3Max.js';
import { estimateH3MaxCost } from '../../src/lib/video/h3MaxPricing.js';
import { fetchFalRequestCosts } from './falBillingCosts.js';

const DAY = 86_400_000;
const MODES = new Map(Object.entries(H3_MAX_ENDPOINTS).map(([mode, endpoint]) => [endpoint, mode as H3MaxMode]));
const metadataObject = (value: any): Record<string, any> => value && typeof value === 'object' && !Array.isArray(value) ? value : {};
const nonnegative = (value: unknown): number | undefined => {
  if (typeof value !== 'number' && (typeof value !== 'string' || !value.trim())) return;
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : undefined;
};

/** Existing UUID primary key gives each accepted provider request one usage
 * record, without a schema migration or a browser acknowledgement dependency. */
export const h3UsageLogId = (userId: string, taskId: string): string => {
  const bytes = createHash('sha256').update(`banana:fal:h3-usage:v1:${userId}:${taskId}`).digest().subarray(0, 16);
  bytes[6] = (bytes[6] & 0x0f) | 0x50;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = bytes.toString('hex');
  return `${hex.slice(0,8)}-${hex.slice(8,12)}-${hex.slice(12,16)}-${hex.slice(16,20)}-${hex.slice(20)}`;
};

const usageModel = (mode: H3MaxMode) => `minimax-h3-${mode.replace(/_/g, '-')}`;
const modeFor = (row: any): H3MaxMode | undefined => normalizeH3MaxMode(row.metadata?.h3MaxMode) || MODES.get(row.metadata?.falEndpoint);
const admissionSignature = (row: { id: string; user_id: string }, taskId: string, mode: H3MaxMode): string | undefined => {
  const secret = process.env.CRON_SECRET || process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!secret) return;
  return createHmac('sha256', secret).update(JSON.stringify(['banana:h3-usage:v1', row.id, row.user_id, taskId, mode])).digest('hex');
};
const canRepairUsage = (row: any, id: string, mode: H3MaxMode): boolean => {
  // Gallery metadata is owner-editable. Only a server-signed admission can
  // authorize creating a missing usage row; a historical marker is insufficient.
  if (row.metadata?.h3UsageVersion !== 1 || row.metadata?.videoUsageLogId !== id) return false;
  const expected = admissionSignature(row, row.task_id, mode), supplied = row.metadata?.h3UsageSignature;
  return typeof expected === 'string' && typeof supplied === 'string' && /^[a-f0-9]{64}$/i.test(supplied)
    && timingSafeEqual(Buffer.from(supplied), Buffer.from(expected));
};

const estimateFor = (row: any, mode: H3MaxMode): number | undefined => {
  const metadata = metadataObject(row.metadata);
  const stored = nonnegative(metadata.generationCost?.usd);
  if (stored !== undefined) return stored;
  try {
    const estimate = estimateH3MaxCost({
      h3MaxMode: mode, h3MaxOptions: metadata.h3MaxOptions,
      videoQuality: metadata.videoQuality || row.resolution || '768p', videoDuration: metadata.videoDuration || 5,
      referenceImages: row.reference_images || [], referenceVideos: metadata.referenceVideos || [], referenceAudios: metadata.referenceAudios || [],
    } as GenerationConfig);
    return nonnegative(estimate.usd);
  } catch { return undefined; }
};

/** A metadata compare-and-swap preserves unrelated prompt, gallery and save
 * updates. A concurrent edit is retried against its current saved contents. */
const mergeGenerationMetadata = async (db: any, row: any, patch: Record<string, unknown>): Promise<boolean> => {
  let current = row;
  for (let attempt = 0; attempt < 3; attempt++) {
    const snapshot = current.metadata;
    let update = db.from('generations').update({ metadata: { ...metadataObject(snapshot), ...patch } })
      .eq('id', row.id).eq('user_id', row.user_id).eq('type', 'video');
    if (current.task_id) update = update.eq('task_id', current.task_id);
    update = snapshot == null ? update.is('metadata', null) : update.eq('metadata', JSON.stringify(snapshot));
    const result = await update.select('id').maybeSingle();
    if (result.error) throw new Error('Saved H3 billing details could not be updated.');
    if (result.data) return true;
    const fresh = await db.from('generations').select('id,user_id,type,task_id,metadata').eq('id', row.id).eq('user_id', row.user_id).maybeSingle();
    if (fresh.error) throw new Error('Saved H3 billing details could not be read.');
    if (!fresh.data || fresh.data.type !== 'video' || (row.task_id && fresh.data.task_id !== row.task_id)) return false;
    current = fresh.data;
  }
  return false;
};

export interface H3UsageAdmission {
  taskId: string; userId: string; mode: H3MaxMode; prompt: string;
  generationId?: string; estimatedCostUsd?: number;
}

export const recordH3Usage = async (db: any, input: H3UsageAdmission): Promise<{ usageLogId: string; recorded: boolean }> => {
  const usageLogId = h3UsageLogId(input.userId, input.taskId);
  try {
    const task = await db.from('provider_tasks').select('user_id,created_at').eq('provider', 'fal').eq('task_id', input.taskId).eq('user_id', input.userId).maybeSingle();
    if (task.error || !task.data || task.data.user_id !== input.userId) return { usageLogId, recorded: false };
    let row: any;
    if (input.generationId) {
      const saved = await db.from('generations').select('id,user_id,type,task_id,metadata,prompt,resolution,reference_images,created_at')
        .eq('id', input.generationId).eq('user_id', input.userId).eq('type', 'video').maybeSingle();
      if (saved.error) throw new Error('Saved H3 generation could not be read.');
      if (saved.data && (!saved.data.task_id || saved.data.task_id === input.taskId)) row = saved.data;
    }
    // Persist the exact association even if a transient usage insert fails.
    // A later admin refresh can then repair only this new server-owned record.
    if (row) await mergeGenerationMetadata(db, row, {
      videoUsageLogId: usageLogId, h3UsageVersion: 1, h3UsageSignature: admissionSignature(row, input.taskId, input.mode),
    });
    const cost = nonnegative(input.estimatedCostUsd) ?? (row ? estimateFor(row, input.mode) : undefined);
    const result = await db.from('usage_logs').upsert({
      id: usageLogId, user_id: input.userId, action: 'video_generate', model: usageModel(input.mode),
      prompt: String(input.prompt || '').slice(0, 500), image_count: 1, estimated_cost: cost ?? null,
      ...(task.data.created_at ? { created_at: task.data.created_at } : {}),
    }, { onConflict: 'id', ignoreDuplicates: true });
    return { usageLogId, recorded: !result.error };
  } catch {
    // The provider has already accepted the task. A billing-write outage must
    // not masquerade as a failed generation or trigger another paid request.
    console.warn('Accepted H3 task billing will need reconciliation', input.taskId);
    return { usageLogId, recorded: false };
  }
};

export interface H3BillingReconciliation {
  checked: number; reconciled: number; usageUpdated: number; unlinked: number; remaining: boolean; warnings: string[];
}

export const reconcileH3Usage = async (db: any, key: string, maxJobs = 200): Promise<H3BillingReconciliation> => {
  const summary: H3BillingReconciliation = { checked: 0, reconciled: 0, usageUpdated: 0, unlinked: 0, remaining: false, warnings: [] };
  const startedAt = Date.now();
  try {
    const candidates = await db.from('generations').select('id,user_id,type,status,task_id,metadata,prompt,resolution,reference_images,created_at')
      .eq('type', 'video').eq('image_model', 'minimax-h3').in('status', ['completed', 'failed']).not('task_id', 'is', null)
      .in('metadata->>falEndpoint', Object.values(H3_MAX_ENDPOINTS))
      .is('metadata->h3BillingReconciliation', null).gte('created_at', Date.now() - 90 * DAY)
      .order('created_at', { ascending: false }).limit(maxJobs + 1);
    if (candidates.error) throw new Error('Saved H3 jobs could not be read for billing reconciliation.');
    const jobs = (candidates.data || []).filter((row: any) => modeFor(row) && typeof row.task_id === 'string' && row.task_id.trim());
    summary.remaining = jobs.length > maxJobs;
    const pending = jobs.slice(0, maxJobs), costs = new Map<string, number>(), deadline = Date.now() + 20_000;
    for (let offset = 0; offset < pending.length; offset += 50) {
      const batch = pending.slice(offset, offset + 50);
      for (const [id, cost] of await fetchFalRequestCosts([...new Set<string>(batch.map((row: any) => String(row.task_id)))], key, {
        timeoutMs: Math.min(5000, deadline - Date.now()), endpointIds: Object.values(H3_MAX_ENDPOINTS),
      })) costs.set(id, cost);
    }
    // Task ownership comes from the server-owned registry, not mutable gallery
    // metadata. A caller cannot use another user's provider request as a bill.
    const ownership = pending.length ? await db.from('provider_tasks').select('task_id,user_id,created_at').eq('provider', 'fal')
      .in('task_id', pending.map((row: any) => row.task_id)) : { data: [] };
    if (ownership.error) throw new Error('H3 task ownership could not be verified for reconciliation.');
    const owners = new Map((ownership.data || []).map((task: any) => [task.task_id, task]));
    for (const row of pending) {
      if (Date.now() - startedAt >= 40_000) { summary.remaining = true; break; }
      summary.checked++;
      const actual = costs.get(row.task_id), task: any = owners.get(row.task_id), mode = modeFor(row)!;
      if (actual === undefined || task?.user_id !== row.user_id) continue;
      const id = h3UsageLogId(row.user_id, row.task_id);
      const usage = await db.from('usage_logs').select('id,user_id,model,action').eq('id', id).eq('user_id', row.user_id).maybeSingle();
      if (usage.error) throw new Error('H3 usage records could not be read.');
      const linked = usage.data?.action === 'video_generate' && usage.data.model === usageModel(mode);
      let usageUpdated = false;
      if (linked || canRepairUsage(row, id, mode)) {
        const updated = linked
          ? await db.from('usage_logs').update({ estimated_cost: actual }).eq('id', id).eq('user_id', row.user_id).eq('action', 'video_generate').eq('model', usageModel(mode))
          : await db.from('usage_logs').upsert({ id, user_id: row.user_id, action: 'video_generate', model: usageModel(mode),
            prompt: String(row.prompt || '').slice(0,500), image_count: 1, estimated_cost: actual,
            ...(task.created_at ? { created_at: task.created_at } : {}),
          }, { onConflict: 'id', ignoreDuplicates: false });
        if (updated.error) throw new Error('H3 actual usage cost could not be saved.');
        usageUpdated = true;
      }
      const saved = await mergeGenerationMetadata(db, row, {
        generationCost: { usd: actual, source: 'provider_actual' },
        h3BillingReconciliation: { version: 1, checkedAt: new Date().toISOString(), usage: usageUpdated ? 'updated' : 'unlinked' },
        ...(usageUpdated ? { videoUsageLogId: id } : {}),
      });
      if (saved) {
        summary.reconciled++; if (usageUpdated) summary.usageUpdated++; else summary.unlinked++;
      } else summary.remaining = true;
    }
  } catch (error) {
    // No upstream body, key or user prompt is exposed in admin diagnostics.
    const message = error instanceof Error && /^H3 |^Saved H3 /.test(error.message) ? error.message : 'H3 request billing could not be reconciled. Retry refresh.';
    summary.warnings.push(message);
  }
  if (summary.unlinked) summary.warnings.push(`${summary.unlinked} historical H3 job(s) have an actual Gallery cost but no exact usage-log link; existing user totals were preserved.`);
  if (summary.remaining) summary.warnings.push('H3 billing has more saved requests to reconcile. Refresh again to continue.');
  return summary;
};
