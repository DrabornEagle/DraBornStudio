/** Official fal contracts and pricing verified 2026-10-19.
 * https://fal.ai/models/google/nano-banana-2.1/edit
 * Queue results expose images, not token usage or a final billed amount.
 */
export const NANO_BANANA_21_MODEL = 'gemini-nano-banana-2.1';
export const NANO_BANANA_21_ENDPOINT = 'google/nano-banana-2.1';
export const NANO_BANANA_2_LEGACY_MODEL = 'gemini-3.1-flash-image-preview';
export const NANO_BANANA_21_TOKEN_PRICING = { input: 1.764, textOutput: 8.823, imageOutput: 35.294 };
const ASPECT_RATIOS = ['auto','21:9','16:9','3:2','4:3','5:4','1:1','4:5','3:4','2:3','9:16','4:1','1:4','8:1','1:8'];
export const getNanoBanana21InputError = (input: Record<string, unknown>, edit: boolean): string | null => {
  if (typeof input.prompt !== 'string' || !input.prompt.trim() || input.prompt.length > 50_000) return 'Nano Banana 2.1 requires a prompt of 1–50,000 characters.';
  for (const [key, allowed] of [['resolution',['1K','2K','4K']], ['thinking_level',['minimal','medium','high']], ['aspect_ratio',ASPECT_RATIOS], ['output_format',['jpeg','png','webp']]] as const) {
    if (input[key] !== undefined && !(allowed as readonly string[]).includes(input[key] as string)) return `Invalid Nano Banana 2.1 ${key}.`;
  }
  if (input.num_images !== undefined && (!Number.isInteger(input.num_images) || Number(input.num_images) < 1 || Number(input.num_images) > 4)) return 'Nano Banana 2.1 supports 1–4 images per request.';
  const images = input.image_urls;
  if (edit && (!Array.isArray(images) || !images.length)) return 'image_urls is required for image-reference generation or editing.';
  if (images !== undefined && (!Array.isArray(images) || images.length > 14 || images.some(url => {
    if (typeof url !== 'string') return true;
    try { return !['https:','http:','data:'].includes(new URL(url).protocol); } catch { return true; }
  }))) return 'Nano Banana 2.1 supports up to 14 valid image URLs.';
  return null;
};
const OUTPUT_TOKENS = { '1K': 1120, '2K': 1680, '4K': 3780 };
/** Representative output-image tokens only; prompt, references and High
 * thinking are additional usage, never a flat $0.002 surcharge in 2.1. */
export const estimateNanoBanana21OutputCost = (resolution: keyof typeof OUTPUT_TOKENS, count: number): number | null => {
  if (!Object.hasOwn(OUTPUT_TOKENS, resolution) || !Number.isInteger(count) || count < 0) return null;
  return OUTPUT_TOKENS[resolution] * NANO_BANANA_21_TOKEN_PRICING.imageOutput / 1_000_000 * count;
};
