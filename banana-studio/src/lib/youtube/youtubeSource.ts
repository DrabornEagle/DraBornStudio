import type { TextModelId, YouTubeEpisodeSource } from '../../types.js';

export const normalizeYouTubeSource = (value: unknown): YouTubeEpisodeSource | undefined => {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return undefined;
  const source = value as Record<string, unknown>;
  if (typeof source.videoId !== 'string' || !/^[a-zA-Z0-9_-]{11}$/.test(source.videoId)
    || typeof source.title !== 'string' || !source.title.trim()
    || (source.analysisSource !== 'video' && source.analysisSource !== 'metadata')) return undefined;
  const text = (key: string, limit: number) => typeof source[key] === 'string' ? source[key].trim().slice(0, limit) || undefined : undefined;
  const evidence = Array.isArray(source.evidence) ? source.evidence.filter(item => item && typeof item.timestamp === 'string' && typeof item.fact === 'string')
    .slice(0, 6).map(item => ({ timestamp: item.timestamp.slice(0, 12), fact: item.fact.slice(0, 800),
      ...(item.relevance === 'premise' || item.relevance === 'context' ? { relevance: item.relevance as 'premise' | 'context' } : {}) })) : undefined;
  return { videoId: source.videoId, title: source.title.trim().slice(0, 500), analysisSource: source.analysisSource,
    brief: text('brief', 12000), premise: text('premise', 1500), warning: text('warning', 2000), evidence,
    analysisModel: typeof source.analysisModel === 'string' ? source.analysisModel.slice(0, 128) as TextModelId : undefined,
    reasoningEffort: ['low', 'medium', 'high', 'xhigh', 'max'].includes(String(source.reasoningEffort))
      ? source.reasoningEffort as YouTubeEpisodeSource['reasoningEffort'] : undefined };
};
