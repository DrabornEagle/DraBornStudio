import type { GenerationConfig } from '../../types';
import type { YouTubeVideoInfo } from '../../services/youtubeService';
import type { YouTubeVideoAnalysis } from '../../services/youtubeBriefService';
import { getPersonGroups, getPersonId } from '../references/personReferences';
import { SUNBURST_MODEL } from '../images/openaiImage';

export interface YouTubeBrainstormPreparation {
  video: YouTubeVideoInfo;
  analysis: YouTubeVideoAnalysis;
  selectedPersonIds: number[];
  expectedDraftKey: string;
}

/** Output settings may change during analysis; draft edits and cast changes may not. */
export const getYouTubeDraftKey = (config: GenerationConfig): string => JSON.stringify({
  mode: config.mode, prompt: config.prompt, originalPrompt: config.originalPrompt,
  references: config.referenceImages.map(ref => [ref.id, getPersonId(ref), ref.personName, !!ref.isDraftImage, !!ref.isVideoContext, !!ref.isThumbnailStyle]),
  people: config.personGroups, youtubeSource: config.youtubeSource,
});

export const prepareYouTubeBrainstormDraft = (current: GenerationConfig, prepared: YouTubeBrainstormPreparation): GenerationConfig => {
  if (current.mode !== 'image' || getYouTubeDraftKey(current) !== prepared.expectedDraftKey) {
    throw new Error('Your prompt or people changed during analysis. Prepare Brainstorm again to use the current draft.');
  }
  if (prepared.analysis.source !== 'video' || !prepared.analysis.brief.trim() || !prepared.analysis.premise?.trim()) {
    throw new Error('A verified video brief and primary thumbnail promise are required. Analyze the video again.');
  }
  const groups = getPersonGroups(current.referenceImages.filter(ref => !ref.isVideoContext), current.personGroups).filter(group => group.images.length);
  const selected = new Set(prepared.selectedPersonIds);
  if ([...selected].some(id => !groups.some(group => group.id === id))) throw new Error('A selected person no longer has reference photos. Check the people and try again.');
  // Episode covers are never automatic generation inputs. Explicit style
  // examples and identity photos stay in their existing relative order.
  const refs = current.referenceImages.filter(ref => !ref.isVideoContext);
  const limit = current.imageModel === SUNBURST_MODEL ? 16 : 14;
  if (refs.length > limit) throw new Error(`Remove a reference first (limit ${limit}).`);
  const cast = groups.filter(group => selected.has(group.id));
  const prompt = [
    `EPISODE SUMMARY\n${JSON.stringify(prepared.video.title)}\nCreate new YouTube thumbnails for this episode.\nPRIMARY THUMBNAIL PROMISE: ${prepared.analysis.premise.trim()}`,
    `SELECTED PEOPLE — ${cast.length} ${cast.length === 1 ? 'person' : 'people'}\n${cast.length
      ? `${cast.map(group => `${group.tag} = ${JSON.stringify(group.label)} (identity photos of the SAME single person).`).join('\n')}\nInclude all selected people; do not use other attached identities. Show each once unless a supported episode comparison needs repeated appearances of the SAME person.`
      : 'No identity-reference people were selected. Do not use attached person-reference photos.'}`,
  ].join('\n\n');
  return { ...current, prompt, originalPrompt: undefined, promptPreparation: undefined, imagePromptCategory: 'youtube_thumbnail', referenceImages: refs,
    youtubeSource: { videoId: prepared.video.id, title: prepared.video.title, analysisSource: prepared.analysis.source,
      brief: prepared.analysis.brief, premise: prepared.analysis.premise, warning: prepared.analysis.warning,
      evidence: prepared.analysis.evidence, analysisModel: prepared.analysis.analysisModel, reasoningEffort: prepared.analysis.reasoningEffort },
    enhancedForMode: undefined, enhancedForImageModel: undefined, enhancedForImageContextKey: undefined,
    enhancedForVideoModel: undefined, enhancedForVideoOperation: undefined, enhancedForVideoReferenceKey: undefined };
};
