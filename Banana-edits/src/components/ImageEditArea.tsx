import React, { useEffect, useId, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import { Check, X } from 'lucide-react';
import type { ReferenceImage } from '../types';
import { isValidEditRegion, type ImageEditRegion } from '../lib/images/imageEditRegion';
import { ImageEditCanvas } from './ImageEditCanvas';

export const ImageEditArea: React.FC<{ source: ReferenceImage; onSave: (region: ImageEditRegion, canvas: { width: number; height: number }) => void; onClose: () => void }> = ({ source, onSave, onClose }) => {
  const [region, setRegion] = useState<ImageEditRegion | undefined>(source.editRegion);
  const [canvas, setCanvas] = useState({ width: 0, height: 0 });
  const panel = useRef<HTMLDivElement>(null);
  const close = useRef<HTMLButtonElement>(null);
  const titleId = useId();
  useEffect(() => {
    const previous = document.activeElement as HTMLElement | null;
    close.current?.focus();
    return () => previous?.focus();
  }, []);
  return createPortal(
    <div className="fixed inset-0 z-[300] flex items-center justify-center bg-black/75 p-3 backdrop-blur-sm sm:p-5" onClick={event => { if (event.target === event.currentTarget) onClose(); }} onKeyDown={event => {
      if ((event.ctrlKey || event.metaKey) && event.key === 'Enter') { event.preventDefault(); event.stopPropagation(); return; }
      if (event.key === 'Escape') { event.stopPropagation(); onClose(); }
      if (event.key === 'Tab') {
        const controls = panel.current?.querySelectorAll<HTMLElement>('button:not(:disabled), [tabindex="0"]');
        if (!controls?.length) return;
        const first = controls[0], last = controls[controls.length - 1];
        if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
        else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
      }
    }}>
      <div ref={panel} role="dialog" aria-modal="true" aria-labelledby={titleId} className="max-h-[calc(100dvh-2rem)] w-full max-w-4xl overflow-y-auto rounded-[1.6rem] border border-white/[0.1] bg-[#121821]/95 text-white shadow-[0_24px_80px_rgba(0,0,0,0.5)]">
        <div className="flex items-center justify-between gap-4 px-4 pb-3 pt-4 sm:px-5">
          <div><h2 id={titleId} className="text-sm font-semibold">Edit area</h2><p className="mt-0.5 text-xs text-gray-500">Select what you want to change.</p></div>
          <button ref={close} type="button" aria-label="Close edit area" onClick={onClose} className="grid h-8 w-8 place-items-center rounded-lg text-gray-500 transition-colors hover:bg-white/5 hover:text-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-lime-400/50"><X className="h-4 w-4" /></button>
        </div>
        <div className="px-3 sm:px-5"><ImageEditCanvas source={source} region={region} onChange={setRegion} onCanvasLoad={setCanvas} maxHeight="min(58vh, 620px)" /></div>
        <div className="flex items-center justify-end gap-2 border-t border-white/[0.06] px-4 py-3 sm:px-5">
          <button type="button" className="h-10 rounded-xl px-4 text-xs font-medium text-gray-400 transition-colors hover:bg-white/5 hover:text-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-lime-400/50" onClick={onClose}>Cancel</button>
          <button type="button" disabled={!canvas.width || !isValidEditRegion(region)} className="flex h-10 items-center gap-1.5 rounded-xl bg-lime-400 px-4 text-xs font-semibold text-black transition-colors hover:bg-lime-300 disabled:cursor-not-allowed disabled:opacity-35 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-lime-300 focus-visible:ring-offset-2 focus-visible:ring-offset-[#121821]" onClick={() => { if (isValidEditRegion(region)) onSave(region, canvas); }}><Check className="h-3.5 w-3.5" />Use selection</button>
        </div>
      </div>
    </div>, document.body,
  );
};
