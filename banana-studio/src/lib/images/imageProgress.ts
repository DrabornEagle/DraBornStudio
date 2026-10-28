// The Images API supplies no completion percentage. This is only UI pacing,
// explicitly labelled Estimated in Gallery, never provider-reported progress.
export const estimateImageProgress = (startedAt: number, now = Date.now()): number => {
  const elapsed = Math.max(0, now - startedAt);
  return Math.min(0.95, 0.04 + 0.91 * (1 - Math.exp(-elapsed / 60_000)));
};

export const withEstimatedImageProgress = async <T>(
  startedAt: number, onProgress: ((progress: number) => void) | undefined, work: () => Promise<T>,
): Promise<T> => {
  if (!onProgress) return work();
  const update = () => onProgress(estimateImageProgress(startedAt));
  update();
  const timer = setInterval(update, 1000);
  try {
    const result = await work();
    onProgress(1);
    return result;
  } finally { clearInterval(timer); }
};
