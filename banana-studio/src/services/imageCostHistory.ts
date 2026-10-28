import { supabase, getCurrentUserId } from './authService';
import { SUNBURST_MODEL } from '../lib/images/openaiImage';
import type { ImageCostSample } from '../lib/images/imageCostPreview';

/** Read only this user's recent Sunburst usage. No estimates are written to billing. */
export const getImageCostHistory = async (): Promise<ImageCostSample[]> => {
  if (!supabase) return [];
  const userId = await getCurrentUserId();
  if (!userId) return [];
  const { data, error } = await supabase.from('generations')
    .select('id, image_model, metadata, reference_images')
    .eq('user_id', userId).eq('image_model', SUNBURST_MODEL)
    .order('created_at', { ascending: false }).limit(100);
  if (error) return []; // Keep the explicitly labelled output-only preview.
  return (data || []).map(row => ({
    id: row.id, imageModel: row.image_model,
    openaiImageOptions: row.metadata?.openaiImageOptions,
    imageRequestedSize: row.metadata?.imageRequestedSize,
    imageOutputSize: row.metadata?.imageOutputSize,
    referenceImages: row.reference_images,
    openaiUsage: row.metadata?.openaiUsage,
  }));
};
