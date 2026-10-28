import { getPersonGroups } from '../references/personReferences.js';
import { mapUnquotedPrompt } from '../references/referenceTokens.js';
import type { ReferenceImage } from '../../types.js';

// Compare garment designs, not colors or prose: five paraphrases of the same
// jacket + polo must not pass the check before the paid image batch starts.
const GARMENTS = {
  't-shirt': /\b(?:t[ -]?shirt|tisort)\b/i,
  shirt: /\b(?:shirt|gomlek)\b/i,
  polo: /\bpolo\b/i,
  sweater: /\b(?:sweater|jumper|pullover|kazak)\b/i,
  cardigan: /\b(?:cardigan|hirka)\b/i,
  hoodie: /\b(?:hoodie|hooded sweatshirt|kapusonlu (?:sweatshirt|ust))\b/i,
  sweatshirt: /\bsweatshirt\b/i,
  jacket: /\b(?:jacket|ceket)\b/i,
  coat: /\b(?:coat|kaban|palto)\b/i,
  blazer: /\bblazer\b/i,
  vest: /\b(?:vest|waistcoat|yelek)\b/i,
  jersey: /\b(?:jersey|forma)\b/i,
  coveralls: /\b(?:coveralls|overalls|jumpsuit|tulum)\b/i,
  dress: /\b(?:dress|elbise)\b/i,
  tunic: /\b(?:tunic|tunik)\b/i,
} as const;
type Garment = keyof typeof GARMENTS;
const latin = (value: string) => value.toLowerCase().replace(/ı/g, 'i').normalize('NFD').replace(/[\u0300-\u036f]/g, '');
const normalized = (value: string) => latin(value).replace(/[^a-z0-9]+/g, ' ').trim();
const hasClothingInstruction = (value: string): boolean => /\b(?:wears|wearing|dressed in|clad in|giyer|giyen|giysin|giymis|giyiyor|giydir|uzerinde)\b/.test(latin(value));
const describedGarments = (outfit: string): Garment[] => {
  // A polo shirt and a T-shirt are each one design, not an extra "shirt" layer.
  let remaining = latin(outfit).replace(/\bpolo(?:[ -](?:shirt|gomlek))?\b/gi, 'polo')
    .replace(/\bdress[ -]shirt\b/gi, 'shirt')
    .replace(/\bshirt[ -]jacket\b/gi, 'jacket')
    .replace(/\bsweater[ -]vest\b/gi, 'vest');
  return (Object.keys(GARMENTS) as Garment[]).filter(garment => {
    const pattern = GARMENTS[garment];
    if (!pattern.test(remaining)) return false;
    remaining = remaining.replace(new RegExp(pattern.source, 'gi'), ' ');
    return true;
  });
};

const PLAN_HEADER = 'CONCEPT WARDROBE — KEEP THIS PLAN';
const PLAN_END = 'END CONCEPT WARDROBE';
const LEGACY_END = "Preserve each person's face, hair and identity. Use this outfit for every appearance of that person in this concept; do not copy clothing from identity photos or other concepts.";
const planPattern = () => new RegExp(`${PLAN_HEADER}\\n[\\s\\S]*?\\n${PLAN_END}`, 'g');
const legacyPlan = (prompt: string): string => prompt.match(/When depicted, @(?:MAIN_PERSON|SECOND_PERSON|PERSON_\d+) wears [^\n]+/g)
  ?.find(line => line.endsWith(LEGACY_END)) || '';
const outfitEntries = (plan: string): [string, string][] => [...plan.matchAll(/When depicted, (@(?:MAIN_PERSON|SECOND_PERSON|PERSON_\d+)) wears ([\s\S]*?)(?=\s*(?:When depicted, @|Preserve each person's face, hair and identity\.|END CONCEPT WARDROBE)|$)/g)]
  .map(match => [match[1].toUpperCase(), match[2].trim()]);

// The same garment can still be changed by the text model. Compare recognizable
// garment attributes as well, before conflicting scene prose reaches generation.
const OUTFIT_DETAILS: Record<string, RegExp> = {
  blue: /\b(?:blue|mavi)\b/, navy: /\b(?:navy|lacivert)\b/,
  red: /\b(?:red|kirmizi)\b/, burgundy: /\b(?:burgundy|maroon|bordo)\b/,
  black: /\b(?:black|siyah)\b/, white: /\b(?:white|beyaz)\b/,
  gray: /\b(?:gray|grey|gri)\b/, charcoal: /\b(?:charcoal|antrasit)\b/,
  green: /\b(?:green|yesil)\b/, olive: /\b(?:olive|haki)\b/,
  yellow: /\b(?:yellow|sari)\b/, orange: /\b(?:orange|turuncu)\b/,
  purple: /\b(?:purple|mor)\b/, pink: /\b(?:pink|pembe)\b/,
  brown: /\b(?:brown|kahverengi)\b/, beige: /\b(?:beige|bej)\b/,
  sand: /\b(?:sand|kum)\b/, rust: /\b(?:rust|pas)\b/,
  cotton: /\b(?:cotton|pamuk(?:lu)?)\b/, linen: /\b(?:linen|keten)\b/,
  silk: /\b(?:silk|ipek)\b/, wool: /\b(?:wool|woolen|woollen|yun)\b/,
  canvas: /\b(?:canvas|kanvas)\b/, denim: /\b(?:denim|kot)\b/,
  leather: /\b(?:leather|deri)\b/, satin: /\b(?:satin|saten)\b/,
  velvet: /\b(?:velvet|kadife)\b/, fleece: /\b(?:fleece|polar)\b/,
  polyester: /\bpolyester\b/,
};
const outfitDetails = (outfit: string): string[] => Object.entries(OUTFIT_DETAILS).filter(([, pattern]) => pattern.test(latin(outfit))).map(([detail]) => detail);
const wornDescription = (value: string): string => {
  const english = /\b(?:wears|wearing|dressed in|clad in)\b|(?:üzerinde|uzerinde)/iu.exec(value);
  const description = english ? value.slice(english.index + english[0].length) : value;
  // "wears a blue shirt while holding a red phone" must not classify the
  // phone's red color as a wardrobe change. Keep garment layers and trim scene actions.
  return description.split(/\b(?:while|beside|behind|against|near|next to|in front of|at|holding|holds|carrying|carries|standing|stands|seated|sitting|sits|looking|looks|points|pointing|compares|comparing|telefonu|telefonla)\b/i)[0];
};

/** The app-owned plan is kept in the editable prompt and therefore survives
 * storage, Re-create and either text provider without adding a provider call. */
export const getConceptWardrobe = (prompt: string): string => {
  const block = prompt.replace(/\r\n/g, '\n').match(planPattern())?.[0];
  if (block) return block;
  // Read already generated concepts from the first wardrobe release as well.
  const legacy = legacyPlan(prompt);
  if (!legacy) return '';
  const normalizedEntries = outfitEntries(legacy).map(([tag, outfit]) => `When depicted, ${tag} wears ${outfit}`).join('\n');
  return `${PLAN_HEADER}\n${normalizedEntries}\n${LEGACY_END}\n${PLAN_END}`;
};

export const buildConceptWardrobeGuidance = (prompt: string): string => {
  const plan = getConceptWardrobe(prompt);
  return plan ? `LOCKED CONCEPT WARDROBE\nThe following app-validated outfit belongs to this one concept. Keep every person's assigned garments, colors, cut and materials unchanged while enhancing or creating image variations. It already satisfies the new-clothing requirement; never replace it with a default outfit or clothing copied from identity photos. Keep it only for people the scene requests, without adding people. Return the scene with this same plan, with no conflicting clothing descriptions.\n${plan}` : '';
};

/** Restore an omitted plan after enhancement. If the response changes a locked
 * outfit, retain the approved concept instead of failing the user's request. */
export const preserveConceptWardrobe = (result: string, original: string): string => {
  const plan = getConceptWardrobe(original);
  if (!plan) return result;
  const cleaned = result.replace(planPattern(), '').replace(legacyPlan(result), '').trimEnd();
  const planned = new Set(describedGarments(plan));
  const allDetails = new Set(outfitDetails(outfitEntries(plan).map(([, outfit]) => outfit).join(' ')));
  const assigned = new Map(outfitEntries(plan).map(([tag, outfit]) => [tag, {
    garments: new Set(describedGarments(outfit)), details: new Set(outfitDetails(outfit)),
  }]));
  const clothingClauses = cleaned.split(/[.\n]/).filter(clause => hasClothingInstruction(clause)
    || /@(?:MAIN_PERSON|SECOND_PERSON|PERSON_\d+)\b/i.test(clause) && describedGarments(clause).length > 0);
  if (clothingClauses.some(clause => {
    const wearing = wornDescription(clause);
    if (describedGarments(wearing).some(garment => !planned.has(garment))
      || outfitDetails(wearing).some(detail => !allDetails.has(detail))) return true;
    // A guest must not silently inherit the host's outfit just because both
    // garment types occur somewhere in the combined plan.
    return [...clause.matchAll(/(@(?:MAIN_PERSON|SECOND_PERSON|PERSON_\d+))([^@]*)/gi)].some(match => {
      const personPlan = assigned.get(match[1].toUpperCase());
      const description = wornDescription(match[2]);
      return personPlan && describedGarments(description).length > 0 && (describedGarments(description).some(garment => !personPlan.garments.has(garment))
        || outfitDetails(description).some(detail => !personPlan.details.has(detail)));
    });
  })) {
    return original;
  }
  return `${cleaned}\n\n${plan}`;
};

/** Deliberately fixed uniforms/costumes must not be varied against the brief. */
export const requestsFixedWardrobeAcrossIdeas = (brief: string): boolean => {
  const text = normalized(brief);
  return /\b(?:all|every|each) (?:ideas?|concepts?|thumbnails?|images?).{0,80}\b(?:same|identical|unchanged) (?:\w+ ){0,3}(?:outfit|clothes|clothing|uniform|costume)\b/.test(text)
    || /\b(?:same|identical|unchanged) (?:\w+ ){0,3}(?:outfit|clothes|clothing|uniform|costume).{0,80}\b(?:all|every|each) (?:ideas?|concepts?|thumbnails?|images?)\b/.test(text)
    || /\b(?:tum|butun|her) (?:fikir(?:de|lerde)?|konsept(?:te|lerde)?|gorsel(?:de|lerde)?|kapak(?:ta|larda)?).{0,80}\b(?:ayni|degismeyen) (?:kiyafet|kombin|uniforma|kostum)\b/.test(text);
};

export const buildBrainstormWardrobeGuidance = (guidance: string, references: ReferenceImage[], count: number): string => {
  const people = getPersonGroups(references);
  // Replace the string-array return format, keeping the rest of the existing
  // brief/reference/identity contract and its single text-provider call.
  const sceneGuidance = guidance.replace(/Return\s+only a valid JSON array[^\n]*\./gi, '').replace(/^Format: \["Detailed narrative prompt[^\n]*$/gm, '');
  return `${sceneGuidance}\n\nBRAINSTORM WARDROBE DIVERSITY\nPlan a visibly different scene-appropriate outfit for each identity in EACH of the ${count} ideas. Change the garment design/combination, not just its color, wording or accessories. Never reuse a jacket + polo combination for the same person across different ideas. Keep the same concept's outfit consistent in its image variations and repeated appearances. Preserve face, hair and identity; never copy, recolor or swap identity-reference outfits. Preserve explicitly requested new garments, colors, materials and uniforms from the user brief; vary the remaining permitted layers/designs rather than replacing an intentional clothing instruction. An earlier concept's generated wardrobe is not the default for these new ideas.\nProvide an outfit for each supplied identity group, applied ONLY if that person is depicted; this must never add otherwise unrequested people. Keep clothing descriptions only in wardrobe, not in prompt, so the app can attach one unambiguous outfit to the scene.\nIdentity groups: ${people.map(person => `${person.id} = ${person.tag}`).join(', ')}.\nUse English garment names and descriptions in outfit. garments lists ALL major upper-body clothing layers, using only these canonical design names: ${Object.keys(GARMENTS).join(', ')}. Include each garment once; omit colors, accessories and trousers from garments. outfit describes those same garments with specific colors, cut and material. Do not assign arbitrary different garment names to identical clothes. Before returning, compare each person's sorted garments across ALL ideas and replace every repeated combination.\nRETURN FORMAT\nReturn only a valid JSON array of exactly ${count} objects, each with prompt (one nonempty scene string) and wardrobe (one entry per supplied identity group). Each wardrobe entry has personId (the supplied integer), garments (a nonempty array of the canonical names above), and outfit (a nonempty outfit description). Example shape: {"prompt":"@MAIN_PERSON holds the phone beside the requested text.","wardrobe":[{"personId":1,"garments":["jacket","polo"],"outfit":"a navy canvas field jacket over a sand-colored knitted polo"}]}. The example outfit is not a default. No commentary or extra model calls.`;
};

// Only used when the text model omits or repeats its own selection. Twenty
// distinct garment combinations cover the maximum batch without another call.
const FALLBACK_OUTFITS = [
  'a rust ribbed wool sweater', 'a pale blue relaxed linen shirt', 'a charcoal cotton hoodie',
  'an off-white heavyweight cotton T-shirt', 'a forest green knitted cardigan over a cream cotton T-shirt',
  'a navy canvas jacket over a white cotton T-shirt', 'a sand-colored knitted polo', 'a slate gray cotton sweatshirt',
  'an olive structured blazer over a cream cotton T-shirt', 'a navy quilted vest over a beige cotton shirt',
  'a burgundy knitted cardigan over a pale blue linen shirt', 'a blue denim jacket over a gray wool sweater',
  'a tan wool coat over a cream ribbed sweater', 'a gray V-neck sweater over a white cotton shirt',
  'a light canvas jacket over a charcoal hoodie', 'a slate cotton sweatshirt over a pale blue collared shirt',
  'an olive quilted vest over a gray cotton hoodie', 'a navy blazer over a white linen shirt',
  'a brown canvas jacket over a cream cotton sweatshirt', 'a light gray coat over a navy cotton T-shirt',
];
const outfitSignature = (outfit: string) => describedGarments(outfit).sort().join('|');
const cleanOutfit = (outfit: string) => outfit.trim().replace(/[.\s]+$/, '').replace(/\s+(?:and|ve|var|giyer|giyiyor|giysin|giymiş|giymis)$/iu, '').trim();

const sceneOutfits = (prompt: string, people: ReturnType<typeof getPersonGroups>): Map<number, string> => {
  let unquoted = '';
  mapUnquotedPrompt(prompt.replace(planPattern(), '').replace(legacyPlan(prompt), ''), text => { unquoted += text + '\n'; return text; });
  const outfits = new Map<number, string>();
  for (const person of people) {
    const tagged = [...unquoted.matchAll(/(@(?:MAIN_PERSON|SECOND_PERSON|PERSON_\d+))([^@\n]*)/gi)]
      .filter(match => match[1].toUpperCase() === person.tag).map(match => match[2]);
    // An untagged single-person description is unambiguous; never apply an
    // untagged guest outfit to every identity in a multi-person scene.
    const clauses = tagged.length ? tagged : people.length === 1 ? unquoted.split(/[.\n]/) : [];
    const clause = clauses.find(text => hasClothingInstruction(text) && describedGarments(wornDescription(text)).length);
    if (clause) outfits.set(person.id, cleanOutfit(wornDescription(clause)));
  }
  return outfits;
};

/** Make the plan the single clothing instruction while preserving scene actions
 * and literal visible copy. The model can put wardrobe in prose or metadata. */
const usePlannedClothing = (scene: string): string => mapUnquotedPrompt(scene, text => text.replace(
  /((?:\b(?:wears|wearing|dressed in|clad in)|üzerinde|uzerinde)\s+)([^.\n@]*?)(?=\b(?:while|beside|behind|against|near|next to|in front of|at|holding|holds|carrying|carries|standing|stands|seated|sitting|sits|looking|looks|points|pointing|compares|comparing|telefonu|telefonla|tutuyor|tutarken)\b|[.\n@]|$)/giu,
  (match, verb, description) => describedGarments(description).length ? `${verb}the assigned concept outfit ` : match,
)).trim();

/** Missing, partial, noncanonical and repeated wardrobe output is recoverable.
 * Only missing scenes/counts still fail: never silently bill a different batch. */
export const parseBrainstormWardrobe = (value: unknown, references: ReferenceImage[], count: number, brief = ''): string[] => {
  if (!Array.isArray(value) || value.length !== count) throw new Error('The model did not return all requested ideas. No image generation was started.');
  const people = getPersonGroups(references);
  const explicit = sceneOutfits(brief, people);
  const combinations = new Map<number, Set<string>>();
  return value.map((idea, index) => {
    const scene = typeof idea === 'string' ? idea : idea?.prompt;
    if (typeof scene !== 'string' || !scene.trim()) throw new Error('Brainstorm returned an empty scene. No image generation was started.');
    const inferred = sceneOutfits(scene, people);
    const entries = people.map((person, personIndex) => {
      const candidates = Array.isArray(idea?.wardrobe) ? idea.wardrobe : [];
      const supplied = candidates.find((entry: any) => entry?.personId === person.id && typeof entry.outfit === 'string' && outfitSignature(entry.outfit));
      // Derive the design from the actual description, not an unreliable
      // garments enum. The user's current clothing instruction takes priority.
      let outfit = explicit.get(person.id) || inferred.get(person.id) || supplied?.outfit;
      const used = combinations.get(person.id) || new Set<string>();
      if (!outfit || (!explicit.has(person.id) && used.has(outfitSignature(outfit)))) {
        const start = (index + personIndex) % FALLBACK_OUTFITS.length;
        outfit = Array.from({ length: FALLBACK_OUTFITS.length }, (_, offset) => FALLBACK_OUTFITS[(start + offset) % FALLBACK_OUTFITS.length])
          .find(candidate => !used.has(outfitSignature(candidate))) || FALLBACK_OUTFITS[start];
      }
      used.add(outfitSignature(outfit)); combinations.set(person.id, used);
      return `When depicted, ${person.tag} wears ${cleanOutfit(outfit)}.`;
    });
    const cleanedScene = usePlannedClothing(scene.replace(planPattern(), '').replace(legacyPlan(scene), ''));
    return `${cleanedScene}\n\n${PLAN_HEADER}\n${entries.join('\n')}\n${LEGACY_END}\nThis plan replaces other clothing descriptions in the scene; the user's explicit costume or uniform takes priority.\n${PLAN_END}`;
  });
};

/** New-thumbnail Enhance also needs a concrete selection if the model omits it.
 * Local edits and other image categories are excluded by the caller. */
export const completeConceptWardrobe = (result: string, original: string, references: ReferenceImage[]): string => {
  if (getConceptWardrobe(original)) return preserveConceptWardrobe(result, original);
  const people = getPersonGroups(references);
  if (!people.length) return result;
  const plan = getConceptWardrobe(result);
  const wardrobe = outfitEntries(plan).flatMap(([tag, outfit]) => {
    const person = people.find(person => person.tag === tag);
    return person ? [{ personId: person.id, outfit }] : [];
  });
  return parseBrainstormWardrobe([{ prompt: result, wardrobe }], references, 1, original)[0];
};
