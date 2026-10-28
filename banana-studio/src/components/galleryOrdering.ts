interface GalleryItem {
  id: string;
  mediaType?: string;
}

const BRAINSTORM_ID = /^(brainstorm-[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12})-(0|[1-9]\d*)$/i;

/** Keep each Brainstorm batch at its first visible position, with its original
 * numeric card order. Call after filtering and before pagination so hidden
 * siblings stay hidden and a page boundary cannot interleave a batch.
 * Ordinary cards retain their relative order; input objects are unchanged. */
export const groupBrainstormImages = <T extends GalleryItem>(images: readonly T[]): T[] => {
  const batches = new Map<string, Array<{ image: T; index: number }>>();
  const positions: Array<{ image: T } | { batchId: string }> = [];

  for (const image of images) {
    const match = image.mediaType == null || image.mediaType === 'image'
      ? image.id.match(BRAINSTORM_ID)
      : null;
    const index = match ? Number(match[2]) : NaN;
    if (!match || !Number.isSafeInteger(index)) {
      positions.push({ image });
      continue;
    }

    const batchId = match[1].toLowerCase();
    let batch = batches.get(batchId);
    if (!batch) {
      batch = [];
      batches.set(batchId, batch);
      positions.push({ batchId });
    }
    batch.push({ image, index });
  }

  for (const batch of batches.values()) batch.sort((a, b) => a.index - b.index);
  return positions.flatMap(position => 'image' in position
    ? [position.image]
    : batches.get(position.batchId)!.map(item => item.image));
};
