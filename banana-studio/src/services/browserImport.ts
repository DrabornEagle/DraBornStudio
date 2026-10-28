import {uniqueId} from './browserId.mjs';
import { supabase, getCurrentUserId } from './authService';
import { isBrowserWorkspace } from '../lib/config/runtimeConfig';

export async function importBrowserMedia(files: File[]) {
  if (!isBrowserWorkspace()) throw new Error('Browser workspace required.');
  const userId = await getCurrentUserId();
  if (!userId) throw new Error('Çalışma alanı açılamadı.');
  if (files.some(file => !/^(image\/(png|jpeg|webp|gif)|video\/(mp4|webm|quicktime))$/.test(file.type))) throw new Error('PNG, JPG, WebP, GIF, MP4, WebM veya MOV seç.');
  if (files.some(file => file.size > 128 * 1024 * 1024)) throw new Error('Dosya başına sınır 128 MB.');
  for (const file of files) {
    const id = uniqueId();
    const ext = file.name.split('.').pop()?.replace(/[^a-z0-9]/gi, '') || 'bin';
    const path = `${userId}/import-${id}.${ext}`;
    const { error: uploadError } = await supabase.storage.from('media').upload(path, file, { contentType: file.type });
    if (uploadError) throw new Error('Dosya kaydedilemedi. Tarayıcı depolama alanını kontrol et.');
    const { error } = await supabase.from('generations').insert({
      id, user_id: userId, prompt: file.name, url: `${location.origin}/storage/v1/object/authenticated/media/${path}`,
      storage_path: path, thumbnail_path: file.type.startsWith('image/') ? path : null,
      type: file.type.startsWith('video/') ? 'video' : 'image', created_at: Date.now(), status: 'completed',
      is_favorite: false, aspect_ratio: '16:9', resolution: '1K', folder_id: null, reference_images: [],
      metadata: { imported: true, originalFilename: file.name, mimeType: file.type, generationCost: 0 },
    });
    if (error) { await supabase.storage.from('media').remove([path]); throw new Error('Medya kaydı oluşturulamadı.'); }
  }
}
