import type { GenerationConfig } from '../../types.js';

type Dimensions = { width: number; height: number };
type VideoInspector = (url: string) => Promise<Dimensions>;
export const isH3ReferenceDimensionKnown = (value: unknown): value is number => typeof value === 'number' && Number.isFinite(value) && value > 0;

const inspectImage = (url: string): Promise<Dimensions | null> => {
  if (typeof Image === 'undefined') return Promise.resolve(null);
  return new Promise(resolve => {
    const image = new Image();
    let settled = false;
    const finish = (dimensions: Dimensions | null) => {
      if (settled) return;
      settled = true;
      window.clearTimeout(timeout);
      image.onload = null;
      image.onerror = null;
      image.removeAttribute('src');
      resolve(dimensions);
    };
    const loaded = () => finish(isH3ReferenceDimensionKnown(image.naturalWidth) && isH3ReferenceDimensionKnown(image.naturalHeight)
      ? { width: image.naturalWidth, height: image.naturalHeight } : null);
    const timeout = window.setTimeout(() => finish(null), 3000);
    // Dimensions need no canvas/CORS permission and leave the media unchanged.
    image.onload = loaded;
    image.onerror = () => finish(null);
    image.src = url;
    if (image.complete && image.naturalWidth) loaded();
  });
};

const inspectVideo: VideoInspector = url => new Promise((resolve, reject) => {
  const video = document.createElement('video');
  let settled = false;
  const finish = (dimensions?: Dimensions) => {
    if (settled) return;
    settled = true;
    window.clearTimeout(timeout);
    video.onloadedmetadata = null;
    video.onerror = null;
    video.pause();
    video.removeAttribute('src');
    video.load();
    if (dimensions) resolve(dimensions);
    else reject(new Error('Reference video dimensions are unavailable'));
  };
  const timeout = window.setTimeout(() => finish(), 3000);
  video.preload = 'metadata';
  video.onloadedmetadata = () => finish(isH3ReferenceDimensionKnown(video.videoWidth) && isH3ReferenceDimensionKnown(video.videoHeight)
    ? { width: video.videoWidth, height: video.videoHeight } : undefined);
  video.onerror = () => finish();
  video.src = url;
});

/** Browser-only composer/submit metadata. Failed reads retain conservative
 * unknown-shape pricing; FPS stays an explicit assumption. Native submission
 * can reuse its already established metadata inspector. */
export const hydrateH3MaxReferenceDimensions = async (config: GenerationConfig, videoInspector: VideoInspector = inspectVideo): Promise<GenerationConfig> => {
  if (config.videoModel !== 'minimax-h3' || typeof document === 'undefined') return config;
  const [referenceImages, referenceVideos] = await Promise.all([
    Promise.all(config.referenceImages.map(async image => {
      if (isH3ReferenceDimensionKnown(image.width) && isH3ReferenceDimensionKnown(image.height)) return image;
      const metadata = await inspectImage(image.data).catch(() => null);
      if (!metadata) return image;
      return { ...image, width: isH3ReferenceDimensionKnown(image.width) ? image.width : metadata.width, height: isH3ReferenceDimensionKnown(image.height) ? image.height : metadata.height };
    })),
    Promise.all((config.referenceVideos || []).map(async video => {
      if (isH3ReferenceDimensionKnown(video.width) && isH3ReferenceDimensionKnown(video.height)) return video;
      const metadata = await videoInspector(video.url).catch(() => null);
      if (!metadata) return video;
      return { ...video, ...(isH3ReferenceDimensionKnown(video.width) ? {} : isH3ReferenceDimensionKnown(metadata.width) ? { width: metadata.width } : {}),
        ...(isH3ReferenceDimensionKnown(video.height) ? {} : isH3ReferenceDimensionKnown(metadata.height) ? { height: metadata.height } : {}) };
    })),
  ]);
  return { ...config, referenceImages, referenceVideos };
};
