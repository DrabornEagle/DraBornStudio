import React from 'react';

export const SavedVisibilityControl: React.FC<{ isShared: boolean; disabled?: boolean; onChange: (shared: boolean) => void }> = ({ isShared, disabled, onChange }) => <label className="block text-[11px] text-gray-400">Visibility
  <select aria-label="Saved reference visibility" value={isShared ? 'shared' : 'private'} disabled={disabled} onChange={event => onChange(event.target.value === 'shared')} className="mt-1 h-9 w-full rounded-lg border border-white/10 bg-[#121821] px-2 text-xs text-gray-100 outline-none focus:border-violet-400/60">
    <option value="private">Only this account</option><option value="shared">All users</option>
  </select>
  <span className="mt-1 block text-[10px] leading-4 text-gray-500">{isShared ? 'All users can use this reference. Only you can edit it.' : 'Visible only in this account.'}</span>
</label>;
