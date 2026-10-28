export interface FolderShareStatus { active: boolean; expiresAt?: string; token?: string }
export interface SharedFolderImage { id: string; url: string }
export interface SharedFolderPage { name: string; images: SharedFolderImage[]; nextOffset: number | null }

const unavailable = 'Folder sharing is temporarily unavailable. Please try again shortly.';
const isObject = (value: unknown): value is Record<string, unknown> => !!value && typeof value === 'object' && !Array.isArray(value);

/** Proxies and removed deployments can return text/HTML instead of our JSON API. */
async function readResponse(response: Response): Promise<Record<string, unknown>> {
  const data: unknown = await response.json().catch(() => null);
  if (!response.ok) {
    if (isObject(data) && typeof data.error === 'string' && data.error.length <= 300) throw new Error(data.error);
    if (response.status === 404) throw new Error('Folder sharing is unavailable on this version. Refresh the page and try again.');
    throw new Error(unavailable);
  }
  if (!isObject(data)) throw new Error(unavailable);
  return data;
}

export async function readFolderShareStatus(response: Response): Promise<FolderShareStatus> {
  const data = await readResponse(response);
  if (typeof data.active !== 'boolean'
    || (data.token !== undefined && (typeof data.token !== 'string' || !/^[A-Za-z0-9_-]{43}$/.test(data.token)))
    || (data.expiresAt !== undefined && (typeof data.expiresAt !== 'string' || !Number.isFinite(Date.parse(data.expiresAt))))) {
    throw new Error(unavailable);
  }
  return data as unknown as FolderShareStatus;
}

export async function readSharedFolderPage(response: Response): Promise<SharedFolderPage> {
  const data = await readResponse(response);
  if (typeof data.name !== 'string' || !Array.isArray(data.images)
    || data.images.some(image => !isObject(image) || typeof image.id !== 'string' || typeof image.url !== 'string')
    || (data.nextOffset !== null && (!Number.isSafeInteger(data.nextOffset) || (data.nextOffset as number) < 0))) {
    throw new Error(unavailable);
  }
  return data as unknown as SharedFolderPage;
}
