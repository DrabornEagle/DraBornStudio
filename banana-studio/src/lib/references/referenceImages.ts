/** Old gallery/template JSON can still contain the retired mask field.
 * Drop it at read/write and request boundaries without changing image order. */
export const withoutLegacyMask = <T extends object>(ref: T): T => {
  const { mask: _legacyMask, ...image } = ref as T & { mask?: unknown };
  return image as T;
};
