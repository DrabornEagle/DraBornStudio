import sharp from 'sharp';
export const decodeRaster = (bytes: Buffer) => sharp(bytes, { limitInputPixels: 33_554_432, failOn: 'error' })
  .autoOrient().toColourspace('srgb').ensureAlpha().raw().toBuffer({ resolveWithObject: true });
export const encodeRasterPNG = (pixels: Uint8Array | Uint8ClampedArray, width: number, height: number) =>
  sharp(pixels, { raw: { width, height, channels: 4 } }).png().toBuffer();
