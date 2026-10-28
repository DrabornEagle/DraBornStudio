/** Signing is a read under the caller's existing Storage permissions. */
export class MediaAccessError extends Error {
  readonly status: number;
  readonly missing: boolean;
  readonly temporary: boolean;

  constructor(error?: { statusCode?: string | number; status?: string | number; message?: string }) {
    super('Private media access could not be authorized.');
    this.name = 'MediaAccessError';
    this.status = Number(error?.statusCode) || Number(error?.status) || 0;
    this.missing = this.status === 404 || (this.status === 400 && /object not found|no.?such.?key/i.test(error?.message || ''));
    this.temporary = this.status
      ? this.status === 408 || this.status === 429 || this.status >= 500
      : !/not.?found|denied|forbidden|unauthori[sz]ed/i.test(error?.message || '');
  }
}

/** Retry only access reads, never uploads, job acceptance or paid generation. */
export const signMediaUrl = async (
  storage: any, path: string, ttl: number,
  pause: (ms: number) => Promise<void> = ms => new Promise(resolve => setTimeout(resolve, ms)),
): Promise<string> => {
  for (let attempt = 0; ; attempt++) {
    let failure: MediaAccessError;
    try {
      const { data, error } = await storage.createSignedUrl(path, ttl);
      if (!error && data?.signedUrl) return data.signedUrl;
      failure = new MediaAccessError(error);
    } catch (error) {
      failure = new MediaAccessError(error as ConstructorParameters<typeof MediaAccessError>[0]);
    }
    if (!failure.temporary || attempt >= 2) throw failure;
    await pause(200 * (attempt + 1));
  }
};
