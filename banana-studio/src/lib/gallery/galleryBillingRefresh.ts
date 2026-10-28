import type { GeneratedMedia } from '../../types.js';

/** Billing reconciliation updates existing cards without replacing live job
 * state, local-only media, navigation, or the user's creative draft. */
export const mergeReconciledGalleryCosts = (current: GeneratedMedia[], refreshed: GeneratedMedia[]): GeneratedMedia[] => {
  const saved = new Map(refreshed.map(media => [media.id, media]));
  return current.map(media => {
    const updated = saved.get(media.id), cost = updated?.generationCost;
    if (!cost || cost.source !== 'provider_actual' || typeof cost.usd !== 'number' || !Number.isFinite(cost.usd) || cost.usd < 0) return media;
    if (media.taskId && updated?.taskId && media.taskId !== updated.taskId) return media;
    if (media.generationCost?.source === 'provider_actual' && media.generationCost.usd === cost.usd && media.generationCost.credits === cost.credits) return media;
    return { ...media, generationCost: cost };
  });
};
