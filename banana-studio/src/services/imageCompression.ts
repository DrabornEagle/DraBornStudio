/**
 * Reference images sent to /api/banana-studio/gemini-generate must fit within Vercel's
 * 4.5 MB serverless function body limit (combined across the whole request).
 * Brainstorm and image-generation flows can attach 5–10 references at once,
 * so each one is resized and re-encoded as JPEG before upload.
 *
 * The 1568 px cap matches the maximum side length the Gemini image models
 * actually use internally — anything larger gets downscaled by Google before
 * inference, so this transformation is lossless from the model's perspective.
 */

const MAX_DIMENSION = 1568;
const JPEG_QUALITY = 0.85;

const loadImage = (dataUrl: string): Promise<HTMLImageElement> =>
  new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => resolve(img);
    img.onerror = () => reject(new Error('Failed to decode image for compression'));
    img.src = dataUrl;
  });

/**
 * Take a base64 string (without the `data:…;base64,` prefix), decode it,
 * downscale to fit MAX_DIMENSION on the longer side, and re-encode as JPEG.
 *
 * Always returns base64 + 'image/jpeg'. Falls back to the input data on any
 * canvas / decoding error so the upload doesn't fail outright.
 */
export const compressBase64Image = async (
  rawBase64: string,
  inputMimeType: string,
  options?: { maxDimension?: number; quality?: number },
): Promise<{ data: string; mimeType: string }> => {
  if (!rawBase64) return { data: '', mimeType: inputMimeType || 'image/jpeg' };

  const maxDimension = options?.maxDimension ?? MAX_DIMENSION;
  const quality = options?.quality ?? JPEG_QUALITY;

  const dataUrl = rawBase64.startsWith('data:')
    ? rawBase64
    : `data:${inputMimeType || 'image/jpeg'};base64,${rawBase64}`;

  try {
    const img = await loadImage(dataUrl);
    const longest = Math.max(img.naturalWidth, img.naturalHeight);
    const scale = longest > maxDimension ? maxDimension / longest : 1;
    const targetW = Math.max(1, Math.round(img.naturalWidth * scale));
    const targetH = Math.max(1, Math.round(img.naturalHeight * scale));

    const canvas = document.createElement('canvas');
    canvas.width = targetW;
    canvas.height = targetH;
    const ctx = canvas.getContext('2d');
    if (!ctx) throw new Error('2D canvas context unavailable');

    // White backdrop so transparent PNGs flatten cleanly into JPEG.
    ctx.fillStyle = '#ffffff';
    ctx.fillRect(0, 0, targetW, targetH);
    ctx.drawImage(img, 0, 0, targetW, targetH);

    const dataOut = canvas.toDataURL('image/jpeg', quality);
    const base64 = dataOut.includes('base64,') ? dataOut.split('base64,')[1] : dataOut;
    return { data: base64, mimeType: 'image/jpeg' };
  } catch (err) {
    console.warn('Image compression failed, sending original payload', err);
    const cleaned = rawBase64.includes('base64,') ? rawBase64.split('base64,')[1] : rawBase64;
    return { data: cleaned, mimeType: inputMimeType || 'image/jpeg' };
  }
};
