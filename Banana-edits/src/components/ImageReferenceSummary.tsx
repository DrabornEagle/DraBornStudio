import { getPersonGroups } from '../lib/references/personReferences';
import React from 'react';
import { Check } from 'lucide-react';
import type { ReferenceImage } from '../types';
import { summarizeImageReferences } from '../lib/images/imageReferences';

export const ImageReferenceSummary: React.FC<{ references: ReferenceImage[] }> = ({ references }) => {
  const { otherReferences } = summarizeImageReferences(references);
  return <div className="space-y-2" aria-label="Image reference roles">
    {[
      ...getPersonGroups(references).map(group => ({ label: group.label, count: group.images.length, face: true })),
      { label: 'Other references', count: otherReferences, face: false },
    ].filter(row => !row.face || row.count > 0).map(row => <div key={row.label} className={`flex items-center gap-2 text-xs ${row.count ? 'text-green-400' : 'text-gray-500'}`}>
      <div className={`w-4 h-4 rounded-full flex items-center justify-center shrink-0 ${row.count ? 'bg-green-500/20' : 'bg-gray-800'}`}>
        {row.count > 0 && <Check className="w-2.5 h-2.5" />}
      </div>
      <span>{row.label} ({row.count}{row.face ? ` photo${row.count === 1 ? '' : 's'} · same person` : ' added'}){!row.face && <span className="text-gray-600"> (optional)</span>}</span>
    </div>)}
  </div>;
};
