import React, { useCallback, useEffect, useState } from 'react';
import { Maximize, Minus, Plus, SlidersHorizontal } from 'lucide-react';
import type { GeneratedMedia } from '../types';
import { getGalleryAspectRatio } from './galleryPresentation';
import { FIT_VIEWPORT, zoomViewport, type CompareViewport } from './imageComparison';
import { CompareStage, type Dimensions, type RefreshComparisonSource } from './ImageComparisonStage';
import { imageComparisonStageStyles } from './imageCompareStyles';

interface ImageEditComparisonProps {
  source: GeneratedMedia;
  result: GeneratedMedia;
  refreshSource?: RefreshComparisonSource;
  expanded?: boolean;
  fill?: boolean;
  normalResult?: React.ReactNode;
}

const currentSource: RefreshComparisonSource = async media => media.url;
const zoomButton = 'grid h-8 w-8 shrink-0 place-items-center rounded-lg bg-white/[0.06] text-gray-300 transition-colors hover:bg-white/10 hover:text-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-lime-400/50 disabled:opacity-30';

/** Use the gallery's slider stage with a fixed before/after pair, in place. */
export const ImageEditComparison: React.FC<ImageEditComparisonProps> = ({ source, result, refreshSource = currentSource, expanded = false, fill = false, normalResult }) => {
  const [comparing, setComparing] = useState(false);
  const [split, setSplit] = useState(50);
  const [viewport, setViewport] = useState<CompareViewport>(FIT_VIEWPORT);
  const [dimensions, setDimensions] = useState<Record<string, Dimensions>>({});
  useEffect(() => {
    setSplit(50); setViewport(FIT_VIEWPORT);
    setDimensions(previous => Object.fromEntries(Object.entries(previous).filter(([id]) => id === source.id || id === result.id)));
  }, [source.id, result.id]);
  const onDimensions = useCallback((id: string, value: Dimensions) => {
    if (value.width <= 0 || value.height <= 0) return;
    setDimensions(previous => previous[id]?.width === value.width && previous[id]?.height === value.height && previous[id]?.source === value.source
      ? previous : { ...previous, [id]: value });
  }, []);
  const detected = dimensions[source.id];
  const ratio = getGalleryAspectRatio(source, detected ? detected.width / detected.height : undefined);
  const heightClass = expanded ? 'max-h-[calc(100dvh-130px)] md:max-h-[calc(100dvh-150px)]' : 'max-h-[65dvh] md:max-h-[calc(100dvh-170px)]';

  return <div className={`edit-image-comparison w-full min-w-0 ${fill ? 'flex min-h-0 flex-col gap-3 pt-12 md:flex-1 md:self-stretch md:pt-6' : 'space-y-3'}`} data-image-edit-comparison onClick={event => event.stopPropagation()}
    onTouchStart={comparing ? event => event.stopPropagation() : undefined}
    onTouchMove={comparing ? event => event.stopPropagation() : undefined}
    onTouchEnd={comparing ? event => event.stopPropagation() : undefined}>
    <div className="flex shrink-0 flex-wrap items-center justify-end gap-2">
      {comparing && <div role="group" aria-label="Edit comparison zoom" className="mr-auto flex items-center gap-1">
        <button type="button" aria-label="Zoom edit comparison out" className={zoomButton} disabled={viewport.zoom <= 1} onClick={() => setViewport(value => zoomViewport(value, value.zoom / 1.25))}><Minus className="h-3.5 w-3.5" /></button>
        <span className="w-10 text-center text-[11px] tabular-nums text-gray-400">{Math.round(viewport.zoom * 100)}%</span>
        <button type="button" aria-label="Zoom edit comparison in" className={zoomButton} disabled={viewport.zoom >= 8} onClick={() => setViewport(value => zoomViewport(value, value.zoom * 1.25))}><Plus className="h-3.5 w-3.5" /></button>
        <button type="button" aria-label="Fit edit comparison" title="Fit both images" className={zoomButton} onClick={() => setViewport(FIT_VIEWPORT)}><Maximize className="h-3.5 w-3.5" /></button>
      </div>}
      <button type="button" role="switch" aria-label="Compare with source" aria-checked={comparing}
        onClick={() => { setComparing(value => !value); setSplit(50); setViewport(FIT_VIEWPORT); }}
        className={`flex h-9 items-center gap-2 rounded-lg border px-3 text-xs font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-lime-400/50 ${comparing ? 'border-lime-400/25 bg-lime-400/10 text-lime-300' : 'border-white/10 bg-white/[0.04] text-gray-300 hover:bg-white/[0.08] hover:text-white'}`}>
        <SlidersHorizontal className="h-3.5 w-3.5" />Comparison
        <span aria-hidden="true" className={`relative ml-1 h-4 w-7 rounded-full ${comparing ? 'bg-lime-400' : 'bg-gray-700'}`}><span className={`absolute left-0.5 top-0.5 h-3 w-3 rounded-full transition-transform ${comparing ? 'translate-x-3 bg-gray-950' : 'translate-x-0 bg-gray-300'}`} /></span>
      </button>
    </div>
    {comparing ? <>
      <style>{imageComparisonStageStyles + '\n.edit-image-comparison .cmp-stage{border-radius:1rem;}'}</style>
      <div className={`relative w-full shrink-0 ${heightClass} ${fill ? 'min-h-0 md:flex-1 md:shrink' : ''}`} style={{ aspectRatio: ratio }} data-edit-comparison-slider>
        <CompareStage media={[result, source]} ratio={ratio} viewport={viewport} setViewport={setViewport}
          view="slider" split={split} setSplit={setSplit} onDimensions={onDimensions} refreshSource={refreshSource}
          canvasLabel="Source and edited image comparison" revealLabel="Compare source and edited image"
          revealValueText={value => `${Math.round(value)}% source, ${100 - Math.round(value)}% edited image`} />
        <div className="pointer-events-none absolute inset-x-3 top-3 flex justify-between gap-2 text-[10px] font-semibold text-white">
          <span className="rounded-md border border-white/10 bg-black/65 px-2 py-1 backdrop-blur-sm">Source</span>
          <span className="rounded-md border border-lime-400/20 bg-black/65 px-2 py-1 text-lime-300 backdrop-blur-sm">Edited</span>
        </div>
      </div>
      <p className="shrink-0 px-1 text-[11px] text-gray-500">Drag the divider to compare. Scroll or pinch to zoom both images.</p>
    </> : <div className={fill ? 'flex min-h-0 w-full items-center justify-center md:flex-1' : undefined}>{normalResult || <div className="flex items-center justify-center"><img src={result.url} alt={result.prompt || 'Edited image'} className={`h-auto ${heightClass} max-w-full rounded-2xl object-contain`} /></div>}</div>}
  </div>;
};
