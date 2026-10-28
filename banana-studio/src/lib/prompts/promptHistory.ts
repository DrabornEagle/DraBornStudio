import type { GeneratedMedia } from '../../types.js';

import { prepareEditableImagePrompt } from '../references/dynamicReferences.js';
import { EPISODE_THUMBNAIL_SCOPE } from '../youtube/youtubeEditorial.js';

/** Only unwrap an app-generated provider envelope. Keep the prepared creative
 * brief and its constraints, never substitute the original pre-Brainstorm brief. */
const editableProductionPrompt = (prompt: string): string => {
  const text = prompt.replace(/\r\n/g, '\n');
  if (!/^(?:REFERENCE-BASED GENERATION\n|REFERENCE ROLES(?: \([^\n]*\))?\n|LOCAL IMAGE EDIT\n|YOUTUBE THUMBNAIL DIRECTION\n|CREATIVE BRIEF\n)/.test(text)) return prompt;
  const marker = /(?:^|\n\n)(?:CREATIVE BRIEF|REQUESTED EDIT)\n/g;
  let prepared = text;
  // Older re-creations may have nested the same envelope. Peel every known layer.
  for (let depth = 0; depth < 8; depth++) {
    marker.lastIndex = 0;
    const match = marker.exec(prepared);
    if (!match) break;
    prepared = prepared.slice(match.index + match[0].length);
    if (!/^(?:REFERENCE-BASED GENERATION|REFERENCE ROLES|LOCAL IMAGE EDIT|YOUTUBE THUMBNAIL DIRECTION|CREATIVE BRIEF)\n/.test(prepared)
      && !prepared.startsWith('REFERENCE ROLES (')) break;
  }
  // These sections are regenerated from the current refs on every submission.
  const suffix = /\n\n(?:REQUIRED YOUTUBE PERSON WARDROBE\nApplies to |IDENTITY SEPARATION\n(?:main person|second person|person \d+) \(label )/;
  return prepared.split(suffix)[0].trimEnd();
};

type RecreateMedia = Pick<GeneratedMedia, 'mediaType' | 'prompt' | 'imageGenerationPrompt'> & Partial<Pick<GeneratedMedia, 'referenceImages' | 'originalPrompt' | 'imageGenerationReferenceIds'>>;
export const getRecreatePrompt = (media: RecreateMedia): string => {
  if (media.mediaType === 'video') return media.prompt;
  const saved = media.imageGenerationPrompt?.trim() ? media.imageGenerationPrompt : media.prompt;
  const references = media.referenceImages || [];
  // Provider indices may exclude an archived episode cover. A missing saved
  // photo keeps its slot and becomes an unresolved stable ID, never a new person.
  const inputs = media.imageGenerationPrompt?.trim() && media.imageGenerationReferenceIds
    ? media.imageGenerationReferenceIds.map(id => references.find(ref => ref.id === id) || { id, data: '', mimeType: 'image/png' })
    : references;
  return prepareEditableImagePrompt(editableProductionPrompt(saved), inputs);
};

export const getRecreateOriginalPrompt = (media: RecreateMedia): string | undefined => {
  const original = getOriginalImagePrompt(media.prompt, media.originalPrompt);
  return original == null || media.mediaType === 'video' ? original : prepareEditableImagePrompt(original, media.referenceImages || []);
};

export const THUMBNAIL_SOURCE_BRIEF_HEADER = 'SOURCE BRIEF — REQUIRED CONSTRAINTS';
export const COMPACT_SOURCE_BRIEF_FOOTER = 'Follow these source requirements over conflicting scene details. Preserve exact copy, counts and exclusions.';
export const COMPACT_THUMBNAIL_SOURCE_BRIEF_FOOTER = `${COMPACT_SOURCE_BRIEF_FOOTER} The required new-person-wardrobe rule still takes precedence.`;
const SOURCE_BRIEF_RULES = 'Use the concept above within this source brief. Preserve its explicit person counts, roles, exact text, exclusions and single-scene or repeated-appearance requirements even if the concept omits them. Do not add background people when the brief permits only one person. This brief takes precedence over conflicting creative details; ';
export const SOURCE_BRIEF_FOOTER = `${SOURCE_BRIEF_RULES}include every required scene or experience in the complete concept.`;
export const THUMBNAIL_SOURCE_BRIEF_FOOTER = `${SOURCE_BRIEF_RULES}the required new-person-wardrobe rule still takes precedence over copied clothing instructions.`;
export const EPISODE_SOURCE_BRIEF_FOOTER = `${THUMBNAIL_SOURCE_BRIEF_FOOTER}\n${EPISODE_THUMBNAIL_SCOPE}`;
const LEGACY_SOURCE_BRIEF_FOOTER = `${SOURCE_BRIEF_RULES}the app's selected canvas and required new-person-wardrobe rule still take precedence over copied size or clothing instructions.`;

/** Prefer the saved draft (including an empty one). Older Brainstorm prompts
 * embedded their source instead of saving originalPrompt. Recover only known
 * app wrappers; never infer an original from arbitrary generated prose. */
export const getOriginalImagePrompt = (prompt: string, originalPrompt?: string): string | undefined => {
  if (typeof originalPrompt === 'string') return originalPrompt;
  const text = prompt.replace(/\r\n/g, '\n').trimEnd();
  const header = `\n\n${THUMBNAIL_SOURCE_BRIEF_HEADER}\n`;
  for (const footer of [COMPACT_THUMBNAIL_SOURCE_BRIEF_FOOTER, COMPACT_SOURCE_BRIEF_FOOTER, EPISODE_SOURCE_BRIEF_FOOTER, SOURCE_BRIEF_FOOTER, THUMBNAIL_SOURCE_BRIEF_FOOTER, LEGACY_SOURCE_BRIEF_FOOTER]) {
    const end = `\n\n${footer}`;
    if (!text.endsWith(end)) continue;
    const start = text.lastIndexOf(header, text.length - end.length);
    if (start < 0) continue;
    const brief = text.slice(start + header.length, -end.length);
    return brief.trim() ? brief : undefined;
  }
  const editHeader = '\n\nRequested edit: ';
  const editFooter = '\nDo not change anything else.';
  const editStart = text.lastIndexOf(editHeader);
  if (editStart >= 0 && text.endsWith(editFooter)) {
    const brief = text.slice(editStart + editHeader.length, -editFooter.length);
    return brief.trim() ? brief : undefined;
  }
  return undefined;
};

/** Re-brainstorming a prepared image keeps its selected composition and source
 * constraints, but must not nest application-owned source headers/footers. */
export const flattenPreparedImageBrief = (prompt: string, depth = 0): string => {
  if (depth >= 8) return prompt;
  const text = prompt.replace(/\r\n/g, '\n').trimEnd();
  const header = `\n\n${THUMBNAIL_SOURCE_BRIEF_HEADER}\n`;
  const start = text.indexOf(header);
  if (start < 0) return prompt;
  for (const footer of [COMPACT_THUMBNAIL_SOURCE_BRIEF_FOOTER, COMPACT_SOURCE_BRIEF_FOOTER, EPISODE_SOURCE_BRIEF_FOOTER, SOURCE_BRIEF_FOOTER, THUMBNAIL_SOURCE_BRIEF_FOOTER, LEGACY_SOURCE_BRIEF_FOOTER]) {
    const end = `\n\n${footer}`;
    if (!text.endsWith(end)) continue;
    const scene = flattenPreparedImageBrief(text.slice(0, start), depth + 1);
    const source = flattenPreparedImageBrief(text.slice(start + header.length, -end.length), depth + 1);
    return [...new Set([scene, source].filter(Boolean))].join('\n\n');
  }
  return prompt;
};
