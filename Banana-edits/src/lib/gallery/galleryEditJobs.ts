import type { GeneratedMedia, ReferenceImage } from '../../types';
import { SUNBURST_MODEL } from '../images/openaiImage.ts';

export const getGalleryEditSourceId = (references: ReferenceImage[] = []): string | undefined => {
  const source = references.find(ref => ref.isEditSource && ref.editRegion);
  return source?.id.startsWith('gallery-') ? source.id.slice(8) || undefined : undefined;
};

export const getGalleryEditJobs = (sourceId: string, media: GeneratedMedia[]): GeneratedMedia[] => media
  .filter(item => item.mediaType === 'image' && item.id !== sourceId &&
    (item.imageEditSourceId ?? getGalleryEditSourceId(item.referenceImages) ??
      (item.imageEditProtection?.sourceReferenceId?.startsWith('gallery-') ? item.imageEditProtection.sourceReferenceId.slice(8) : undefined)) === sourceId)
  .sort((a, b) => a.createdAt - b.createdAt || a.id.localeCompare(b.id));

export const getEditJobProgress = (media: GeneratedMedia): { pending: boolean; failed: boolean; percent?: number; estimated: boolean } => {
  const failed = media.status === 'failed';
  const pending = !failed && (!!media.isLoading || media.status === 'pending' || media.status === 'processing');
  const estimated = pending && media.imageModel === SUNBURST_MODEL;
  const raw = media.imageProgress;
  return { pending, failed, estimated, percent: pending ?
    typeof raw === 'number' && Number.isFinite(raw) ? Math.max(0, Math.min(99, Math.round(raw * 100))) : undefined : failed ? undefined : 100 };
};
