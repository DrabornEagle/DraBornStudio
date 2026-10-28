import type { GeneratedMedia } from '../../types';

/** Pagination is a snapshot taken before the composer becomes interactive.
 * Jobs submitted since then must survive late pages, even if they have already
 * completed or the snapshot still contains their older processing row. */
export const mergeLoadedGalleryHistory = (current: GeneratedMedia[], loaded: GeneratedMedia[], startedAt: number): GeneratedMedia[] => {
  const recent = current.filter(item => item.createdAt >= startedAt);
  const ids = new Set(recent.map(item => item.id));
  return [...recent, ...loaded.filter(item => !ids.has(item.id))];
};
