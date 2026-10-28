/** Retry reads only. Never wrap provider submissions or storage mutations. */
export const isTransientReadError = (error: unknown): boolean => {
  const value = error as { name?: string; message?: string; details?: string; status?: number; code?: string } | null;
  if (!value) return false;
  if ([401, 403].includes(Number(value.status))) return false;
  return ['AbortError', 'TimeoutError', 'NavigatorLockAcquireTimeoutError'].includes(value.name || '')
    || /signal is aborted|aborted without reason|lock.*timed out|failed to fetch|fetch failed|networkerror|network request failed|load failed/i.test(`${value.message || ''} ${value.details || ''}`)
    || [408, 429, 502, 503, 504].includes(Number(value.status));
};

export const retryTransientRead = async <T>(read: () => Promise<T>): Promise<T> => {
  for (let attempt = 0; ; attempt++) {
    try { return await read(); }
    catch (error) {
      if (attempt >= 2 || !isTransientReadError(error)) throw error;
      await new Promise(resolve => setTimeout(resolve, 200 * (attempt + 1)));
    }
  }
};

/** Coalesce concurrent session reads, but never cache an identity afterward. */
export const createSessionReader = <T>(read: () => Promise<T>) => {
  let active: Promise<T> | undefined;
  return () => active ||= retryTransientRead(read).finally(() => { active = undefined; });
};
