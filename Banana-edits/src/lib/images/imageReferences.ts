import { getPersonId } from '../references/personReferences';
import type { ReferenceImage } from '../../types';

/** Photo counts are distinct from identity counts; face photos are never style references. */
export const summarizeImageReferences = (references: ReferenceImage[]) => ({
  mainPersonPhotos: references.filter(ref => getPersonId(ref) === 1).length,
  secondPersonPhotos: references.filter(ref => getPersonId(ref) === 2).length,
  otherReferences: references.filter(ref => getPersonId(ref) == null).length,
  total: references.length,
});
