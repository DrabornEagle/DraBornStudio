import type { AdminModelUsageSummary, AdminUserSummary } from '../../types';

interface UsageProfile {
  id: string;
  email: string;
  display_name: string;
  avatar_url: string | null;
  role: string;
}

interface SummaryLog {
  user_id: string;
  model?: unknown;
  action: string;
  image_count?: unknown;
  estimated_cost?: unknown;
}

const nonnegativeNumber = (value: unknown): number | null => {
  if (typeof value !== 'number' && (typeof value !== 'string' || !value.trim())) return null;
  const number = Number(value);
  return Number.isFinite(number) && number >= 0 ? number : null;
};

/** Profiles have already passed the active authorization-list filter. Only
 * their logs contribute; each model retains unknown costs instead of zero fees. */
export const buildAdminUsageSummary = (profiles: readonly UsageProfile[], logs: readonly SummaryLog[]): AdminUserSummary[] => {
  const users = new Map(profiles.map(profile => [profile.id, {
    user_id: profile.id, email: profile.email, display_name: profile.display_name,
    avatar_url: profile.avatar_url, role: profile.role,
    total_generations: 0, total_images: 0, total_videos: 0, total_enhances: 0,
    total_cost: 0, image_cost: 0, video_cost: 0, enhance_cost: 0,
    unknown_cost_requests: 0, models: new Map<string, AdminModelUsageSummary>(),
  }]));

  for (const log of logs) {
    const user = users.get(log.user_id);
    if (!user) continue;
    const model = typeof log.model === 'string' && log.model.trim() ? log.model.trim() : 'unknown';
    let usage = user.models.get(model);
    if (!usage) {
      usage = { model, requests: 0, images: 0, videos: 0, text_requests: 0,
        enhance_requests: 0, brainstorm_requests: 0, variation_requests: 0,
        total_cost: 0, unknown_cost_requests: 0 };
      user.models.set(model, usage);
    }
    const cost = nonnegativeNumber(log.estimated_cost);
    const count = Math.floor(nonnegativeNumber(log.image_count) ?? 0);
    usage.requests++;
    if (cost === null) {
      usage.unknown_cost_requests++;
      user.unknown_cost_requests++;
    } else {
      usage.total_cost += cost;
      user.total_cost += cost;
    }
    if (log.action === 'generate') {
      usage.images += count;
      user.total_images += count;
      user.total_generations++;
      user.image_cost += cost ?? 0;
    } else if (log.action === 'video_generate') {
      usage.videos += count;
      user.total_videos += count;
      user.total_generations++;
      user.video_cost += cost ?? 0;
    } else if (['enhance', 'video_enhance', 'brainstorm', 'variation', 'edit_plan'].includes(log.action)) {
      usage.text_requests++;
      if (log.action === 'brainstorm') usage.brainstorm_requests++;
      else if (log.action === 'variation') usage.variation_requests++;
      else if (log.action !== 'edit_plan') usage.enhance_requests++;
      user.total_enhances++;
      user.enhance_cost += cost ?? 0;
    }
  }
  return [...users.values()].map(({ models, ...user }) => ({
    ...user,
    model_usage: [...models.values()].sort((a, b) => b.total_cost - a.total_cost || a.model.localeCompare(b.model)),
  }));
};
