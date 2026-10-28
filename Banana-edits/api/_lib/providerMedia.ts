/** Cloud routes forward validated HTTPS references. The native build replaces
 * this module with a local-file reader so providers never receive loopback URLs. */
export const isReferenceUrl = (value: unknown): value is string => {
  if (typeof value !== 'string') return false;
  try { const url = new URL(value); return url.protocol === 'https:' && !url.username && !url.password; } catch { return false; }
};
export const isSecureReferenceUrl = (url: URL): boolean => url.protocol === 'https:';
export const providerImageUrl = async (_db: unknown, value: string): Promise<string> => value;

/** Gemini needs bytes. Download only an authorized workspace object, never an
 * arbitrary client URL from the server's private network. */
export const providerImageData = async (db: any, value: string): Promise<string> => {
  if (/^data:image\/(?:png|jpeg|webp);base64,[a-zA-Z0-9+/=]+$/.test(value)) return value;
  const url = new URL(value), origin = new URL(process.env.SUPABASE_URL || '').origin;
  const match = url.pathname.match(/^\/storage\/v1\/object\/(?:authenticated|sign|public)\/media\/(.+)$/);
  if (url.origin !== origin || !match) throw new Error('Upload this reference to the workspace before generating.');
  const path = decodeURIComponent(match[1]);
  if (path.split('/').some(part => !part || part === '.' || part === '..')) throw new Error('Invalid reference path.');
  const { data, error } = await db.storage.from('media').download(path);
  if (error || !data || data.size > 20 * 1024 * 1024) throw new Error('The reference could not be read.');
  const mime = data.type || 'image/png';
  if (!['image/png','image/jpeg','image/webp'].includes(mime)) throw new Error('Unsupported image format.');
  return `data:${mime};base64,${Buffer.from(await data.arrayBuffer()).toString('base64')}`;
};
