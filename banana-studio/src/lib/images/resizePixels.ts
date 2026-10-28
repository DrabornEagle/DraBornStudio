/** Bilinear resize for tier-based providers. Runs before selected pixels are
 * composited; source pixels outside the selection are never resampled. */
export function resizePixels(data: Uint8Array, width: number, height: number, targetWidth: number, targetHeight: number): Uint8Array {
  const output = new Uint8Array(targetWidth * targetHeight * 4);
  for (let y = 0; y < targetHeight; y++) {
    const sy = Math.max(0, Math.min(height - 1, (y + .5) * height / targetHeight - .5)), y0 = Math.floor(sy), y1 = Math.min(height - 1, y0 + 1), fy = sy - y0;
    for (let x = 0; x < targetWidth; x++) {
      const sx = Math.max(0, Math.min(width - 1, (x + .5) * width / targetWidth - .5)), x0 = Math.floor(sx), x1 = Math.min(width - 1, x0 + 1), fx = sx - x0;
      for (let c = 0; c < 4; c++) output[(y * targetWidth + x) * 4 + c] = Math.round(
        (data[(y0 * width + x0) * 4 + c] * (1 - fx) + data[(y0 * width + x1) * 4 + c] * fx) * (1 - fy)
        + (data[(y1 * width + x0) * 4 + c] * (1 - fx) + data[(y1 * width + x1) * 4 + c] * fx) * fy);
    }
  }
  return output;
}
