import type { GeneratedMedia } from '../types';

export type CompareView = 'gallery' | 'slider';
export interface CompareViewport { zoom: number; x: number; y: number }
export const FIT_VIEWPORT: CompareViewport = { zoom: 1, x: 0, y: 0 };

export const isComparableImage = (media: GeneratedMedia): boolean =>
  media.mediaType !== 'video' && !!media.url?.trim() && !media.isLoading &&
  !['pending', 'processing', 'failed'].includes(media.status || '');

/** The Set's insertion order is the user's selection order, across folders/pages. */
export function getComparisonSelection(ids: Iterable<string>, images: GeneratedMedia[]) {
  const byId = new Map(images.map(media => [media.id, media]));
  return [...new Set(ids)].flatMap(id => {
    const media = byId.get(id);
    return media && isComparableImage(media) ? [media] : [];
  });
}

export function resolveComparePair(ids: string[], a: string, b: string): [string, string] {
  const reference = ids.includes(a) ? a : ids[0] || '';
  return [reference, b !== reference && ids.includes(b) ? b : ids.find(id => id !== reference) || ''];
}

export function clampViewport(viewport: CompareViewport): CompareViewport {
  const zoom = Math.min(8, Math.max(1, viewport.zoom));
  if (zoom === 1) return { ...FIT_VIEWPORT };
  const edge = (zoom - 1) / 2;
  return { zoom, x: Math.min(edge, Math.max(-edge, viewport.x)), y: Math.min(edge, Math.max(-edge, viewport.y)) };
}

/** Anchors and translations are fractions of the unzoomed shared canvas. */
export function zoomViewport(viewport: CompareViewport, zoom: number, anchor = { x: 0, y: 0 }): CompareViewport {
  const nextZoom = Math.min(8, Math.max(1, zoom));
  const scale = nextZoom / viewport.zoom;
  return clampViewport({ zoom: nextZoom, x: anchor.x - (anchor.x - viewport.x) * scale, y: anchor.y - (anchor.y - viewport.y) * scale });
}
