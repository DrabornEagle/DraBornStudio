/** Bound work even when a dependency does not honor AbortSignal (auth, image decoding). */
export const waitForTask = <T>(work: PromiseLike<T>, signal: AbortSignal): Promise<T> => {
  const pending = Promise.resolve(work);
  return new Promise<T>((resolve, reject) => {
    const abort = () => reject(signal.reason || new DOMException('Stopped waiting', 'AbortError'));
    if (signal.aborted) abort();
    else signal.addEventListener('abort', abort, { once: true });
    pending.then(value => {
      signal.removeEventListener('abort', abort);
      if (signal.aborted) abort(); else resolve(value);
    }, error => {
      signal.removeEventListener('abort', abort);
      reject(error);
    });
  });
};

export const createTaskDeadline = (milliseconds: number, parent?: AbortSignal, message = 'Request timed out.') => {
  const controller = new AbortController();
  const deadline = Date.now() + milliseconds;
  const expire = () => controller.abort(new DOMException(message, 'TimeoutError'));
  const forward = () => controller.abort(parent?.reason);
  if (parent?.aborted) forward();
  else parent?.addEventListener('abort', forward, { once: true });
  const timer = setTimeout(expire, milliseconds);
  return {
    signal: controller.signal,
    abort: (reason?: unknown) => controller.abort(reason),
    // Mobile browsers suspend timers while backgrounded. Check wall time on return.
    check: () => { if (Date.now() >= deadline) expire(); },
    dispose: () => { clearTimeout(timer); parent?.removeEventListener('abort', forward); },
  };
};
