import { THUMBNAIL_SOURCE_BRIEF_HEADER } from '../prompts/promptHistory.js';

/** A production constraint on thumbnail Brainstorm concepts, not a new cast
 * requirement or permission to retouch faces in a later masked edit. */
export const YOUTUBE_CAMERA_GAZE_RULE = `REQUIRED YOUTUBE CAMERA GAZE
Every depicted person looks directly into the camera lens, making clear eye contact with the viewer. Apply this to the host, guests, secondary/background people and EVERY repeated appearance in split scenes or multiple panels. Keep eyes visible and directed toward the viewer, rather than toward a prop, another person or off-screen; avoid closed eyes, hidden faces, back-facing people or full profiles that prevent eye contact.
Keep the requested cast, identities, roles and counts; do not add people to satisfy this rule. Expressions, natural head tilt, body pose, gestures, actions, composition and distinct concept outfits can vary while eye contact stays fixed. Preserve natural facial anatomy and skin texture without beautifying or overprocessing faces.
This is mandatory for this YouTube thumbnail Brainstorm concept and its subsequent enhancement and image variations. It takes precedence over conflicting gaze or face-obscuring pose directions in the creative scene, source brief or reference photos. Keep all other source facts, exact visible copy and exclusions unchanged.
END REQUIRED YOUTUBE CAMERA GAZE`;

export const hasYouTubeCameraGaze = (prompt: string): boolean => prompt.includes(YOUTUBE_CAMERA_GAZE_RULE);

/** Remove only our exact block; never rewrite the user's prose or quoted copy. */
export const stripYouTubeCameraGaze = (prompt: string): string => prompt.replaceAll(YOUTUBE_CAMERA_GAZE_RULE, '').trim();

/** Keep one app-owned rule before the source envelope so Revert and Re-create
 * can still recover its original brief using the existing footer. */
export const applyYouTubeCameraGaze = (prompt: string): string => {
  const clean = stripYouTubeCameraGaze(prompt);
  const sourceStart = clean.indexOf(`\n\n${THUMBNAIL_SOURCE_BRIEF_HEADER}\n`);
  if (sourceStart < 0) return `${clean}\n\n${YOUTUBE_CAMERA_GAZE_RULE}`;
  return `${clean.slice(0, sourceStart).trimEnd()}\n\n${YOUTUBE_CAMERA_GAZE_RULE}${clean.slice(sourceStart)}`;
};

export const preserveYouTubeCameraGaze = (result: string, original: string): string =>
  hasYouTubeCameraGaze(original) ? applyYouTubeCameraGaze(result) : result;
