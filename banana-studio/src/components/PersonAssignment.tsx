import React, { useLayoutEffect, useRef } from 'react';
import { Check, Pencil, Plus, User } from 'lucide-react';
import type { PersonGroupDefinition, ReferenceImage } from '../types';
import { getPersonGroups, getPersonId, getPersonLabel } from '../lib/references/personReferences';

const colors = ['#f59e0b', '#06b6d4', '#a78bfa', '#fb7185', '#34d399', '#fb923c'];
export const personColor = (id: number) => colors[(id - 1) % colors.length];

export const PersonAssignment: React.FC<{
  image: ReferenceImage;
  references: ReferenceImage[];
  definitions?: PersonGroupDefinition[];
  disabled?: boolean;
  onAssign: (id?: number) => void;
  onCreate: () => void;
  onEdit: (id: number) => void;
}> = ({ image, references, definitions, disabled, onAssign, onCreate, onEdit }) => {
  const selectedId = getPersonId(image);
  const pendingCreate = useRef<Set<number> | null>(null);
  const groupList = useRef<HTMLDivElement>(null);
  const groups = getPersonGroups(references, definitions);
  const choices = [...new Set([1, 2, ...groups.map(group => group.id)])].sort((a, b) => a - b);
  useLayoutEffect(() => {
    if (!pendingCreate.current) return;
    const added = groups.find(group => !pendingCreate.current!.has(group.id));
    if (!added) return;
    pendingCreate.current = null;
    if (groupList.current) groupList.current.scrollTop = groupList.current.scrollHeight;
  }, [groups]);
  const actionClass = 'flex min-h-8 w-full items-center gap-2 rounded-lg px-2.5 py-1.5 text-[11px] font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-violet-400/50 disabled:cursor-not-allowed disabled:opacity-40';
  return <div className="mb-1.5 space-y-1.5 border-b border-white/10 pb-1.5">
    <div className="px-2.5 pb-1 pt-1.5">
      <p className="text-[11px] font-semibold text-gray-200">Assign person</p>
      <p className="mt-0.5 text-[10px] leading-snug text-gray-500">Choose a person. Edit details in People.</p>
    </div>
    <div ref={groupList} className="max-h-40 space-y-1 overflow-y-auto" aria-label="Person groups">
      {choices.map(id => {
        const group = groups.find(person => person.id === id);
        const active = selectedId === id;
        return <div key={id} className={`flex items-center rounded-lg border ${active ? 'border-white/10 bg-[#1b2330]' : 'border-transparent hover:bg-gray-800/50'}`}>
          <button type="button" disabled={disabled} aria-pressed={active}
          onClick={() => onAssign(id)} title={`Assign this photo to ${group?.label || getPersonLabel(id)}`}
          className="flex min-h-10 min-w-0 flex-1 items-center gap-2.5 rounded-lg px-2.5 py-1.5 text-left transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-violet-400/50 disabled:cursor-not-allowed disabled:opacity-40">
          <span className="flex h-6 w-6 shrink-0 items-center justify-center overflow-hidden rounded-full border" style={{ borderColor: personColor(id), color: personColor(id) }}>
            {group?.images[0] ? <img src={group.images[0].data} alt="" className="h-full w-full object-cover" /> : <User className="h-3.5 w-3.5" />}
          </span>
          <span className="min-w-0 flex-1"><span className="block truncate text-xs font-medium text-gray-200">{group?.label || getPersonLabel(id)}</span>
            <span className="block truncate text-[10px] text-gray-500">{group?.images.length || 0} {group?.images.length === 1 ? 'photo' : 'photos'}{group && group.label !== getPersonLabel(id) ? ` · ${getPersonLabel(id)}` : ''}</span></span>
          {active && <Check className="h-3.5 w-3.5 shrink-0 text-violet-300" />}
          </button>
          {group && <button type="button" disabled={disabled} aria-label={`Edit ${group.label} in People`} title={`Edit ${group.label} in People`} onClick={() => onEdit(id)} className="mr-1 flex h-8 w-7 shrink-0 items-center justify-center rounded-md text-gray-500 hover:bg-white/5 hover:text-violet-300 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-violet-400/50 disabled:opacity-40"><Pencil className="h-3 w-3" /></button>}
        </div>;
      })}
    </div>
    <button type="button" disabled={disabled} onClick={() => { pendingCreate.current = new Set(groups.map(group => group.id)); onCreate(); }} className={`${actionClass} text-gray-300 hover:bg-gray-800/50 hover:text-white`}><Plus className="h-3.5 w-3.5 text-violet-400" />New person</button>
    {disabled && <p className="px-1 text-[10px] text-amber-300">Remove frame roles to assign people.</p>}
  </div>;
};
