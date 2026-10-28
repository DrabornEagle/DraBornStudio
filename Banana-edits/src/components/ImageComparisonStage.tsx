import React, { useEffect, useRef, useState } from 'react';
import { Columns2 } from 'lucide-react';
import type { GeneratedMedia } from '../types';
import { clampViewport, zoomViewport, type CompareView, type CompareViewport } from './imageComparison';

export type Dimensions = { width: number; height: number; source?: string };
export type ViewportSetter = React.Dispatch<React.SetStateAction<CompareViewport>>;
export type RefreshComparisonSource = (media: GeneratedMedia) => Promise<string>;

export interface OriginalImageProps {
  media: GeneratedMedia; active: boolean; viewport: CompareViewport;
  onDimensions: (id: string, dimensions: Dimensions) => void;
  refreshSource: RefreshComparisonSource;
  clipPath?: string; statusIndex?: number;
}
export const OriginalImage: React.FC<OriginalImageProps> = ({ media, active, viewport, onDimensions, refreshSource, clipPath, statusIndex = 0 }) => {
  const [source, setSource] = useState(media.url);
  const [attempt, setAttempt] = useState(0);
  const [status, setStatus] = useState<'loading' | 'ready' | 'error'>('loading');
  const [previewFailed, setPreviewFailed] = useState(false);
  const [retrying, setRetrying] = useState(false);
  const request = useRef(0);
  // The parent keys by identity + URL. Never reset loading in an effect: a
  // cached/data image can fire onLoad before passive effects run.
  useEffect(() => () => { request.current++; }, []);
  const preview = media.thumbnailUrl && media.thumbnailUrl !== source && !previewFailed;
  const retry = async () => {
    const token = ++request.current;
    setRetrying(true);
    try {
      const url = await refreshSource(media);
      if (token !== request.current) return;
      setSource(url); setStatus('loading'); setAttempt(value => value + 1);
    } catch { if (token === request.current) setStatus('error'); }
    finally { if (token === request.current) setRetrying(false); }
  };
  return <>
    <div className="cmp-layer" data-compare-image={media.id} data-zoom={viewport.zoom} data-pan-x={viewport.x} data-pan-y={viewport.y} style={{ clipPath }}>
    <div className="cmp-transform" style={{ transform: `translate(${viewport.x * 100}%, ${viewport.y * 100}%) scale(${viewport.zoom})` }}>
      {preview && status !== 'ready' && <img src={media.thumbnailUrl} alt="" draggable={false} loading="lazy" onError={() => setPreviewFailed(true)} />}
      {active && <img key={`${source}:${attempt}`} src={source} alt={media.prompt || 'Generated image'} draggable={false}
        style={{ opacity: status === 'ready' ? 1 : 0 }}
        onLoad={event => { setStatus('ready'); onDimensions(media.id, { width: event.currentTarget.naturalWidth, height: event.currentTarget.naturalHeight, source: event.currentTarget.currentSrc }); }}
        onError={() => setStatus('error')} />}
    </div>
    </div>
    {active && status !== 'ready' && <div className="cmp-stage-status" style={{ bottom: 8 + statusIndex * 36 }}><span className="cmp-status" data-error={status === 'error'} role="status">
      {status === 'loading' ? 'Loading original…' : preview ? 'Low-resolution preview · original unavailable' : 'Image unavailable'}
      {status === 'error' && <button type="button" disabled={retrying} onPointerDown={event => event.stopPropagation()} onClick={() => void retry()}>{retrying ? 'Retrying…' : 'Retry'}</button>}
    </span></div>}
  </>;
};

export interface CompareStageProps {
  media: GeneratedMedia[]; ratio: number; viewport: CompareViewport; setViewport: ViewportSetter;
  viewports?: Record<string, CompareViewport>; onActivate?: () => void; canvasLabel?: string; scrollAxis?: 'x' | 'y';
  view?: CompareView; split?: number; setSplit?: (value: number) => void;
  onDimensions: (id: string, dimensions: Dimensions) => void; refreshSource: RefreshComparisonSource;
  revealLabel?: string;
  revealValueText?: (split: number) => string;
}

export function CompareStage({ media, ratio, viewport, setViewport, viewports, onActivate, canvasLabel, scrollAxis = 'y', view = 'gallery', split = 50, setSplit, onDimensions, refreshSource, revealLabel = 'Reveal image B', revealValueText }: CompareStageProps) {
  const container = useRef<HTMLDivElement>(null);
  const stage = useRef<HTMLDivElement>(null);
  const [size, setSize] = useState({ width: 0, height: 0 });
  const [active, setActive] = useState(false);
  const pointers = useRef(new Map<number, { x: number; y: number }>());
  const pinch = useRef<{ distance: number; midpoint: { x: number; y: number } } | null>(null);
  const reveal = useRef<{ pointerId: number; x: number; split: number } | null>(null);
  const mediaKey = media.map(item => item.id).join('\0');
  useEffect(() => {
    const node = stage.current;
    return () => {
      for (const id of pointers.current.keys()) if (node?.hasPointerCapture(id)) node.releasePointerCapture(id);
      pointers.current.clear(); pinch.current = null; reveal.current = null;
    };
  }, [view, mediaKey]);
  useEffect(() => {
    const node = container.current!;
    const measure = () => { const rect = node.getBoundingClientRect(); setSize({ width: rect.width, height: rect.height }); };
    measure();
    const resize = new ResizeObserver(measure); resize.observe(node);
    const observer = new IntersectionObserver(entries => setActive(entries[0].isIntersecting)); observer.observe(node);
    return () => { resize.disconnect(); observer.disconnect(); };
  }, []);
  useEffect(() => {
    const node = stage.current!;
    const wheel = (event: WheelEvent) => {
      // Let horizontal trackpad gestures scroll the filmstrip/gallery normally.
      if (!event.deltaY || Math.abs(event.deltaX) > Math.abs(event.deltaY)) return;
      event.preventDefault();
      onActivate?.();
      const rect = node.getBoundingClientRect();
      const delta = event.deltaY * (event.deltaMode === 1 ? 16 : event.deltaMode === 2 ? rect.height : 1);
      setViewport(value => zoomViewport(value, value.zoom * Math.exp(-delta * 0.002), { x: (event.clientX - rect.left) / rect.width - .5, y: (event.clientY - rect.top) / rect.height - .5 }));
    };
    node.addEventListener('wheel', wheel, { passive: false });
    return () => node.removeEventListener('wheel', wheel);
  }, [setViewport, onActivate]);
  const pinchState = () => {
    const [a, b] = [...pointers.current.values()];
    return a && b ? { distance: Math.hypot(a.x - b.x, a.y - b.y), midpoint: { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 } } : null;
  };
  const endPointer = (event: React.PointerEvent) => {
    pointers.current.delete(event.pointerId); pinch.current = pinchState();
    if (reveal.current?.pointerId === event.pointerId) reveal.current = null;
    if (event.currentTarget.hasPointerCapture(event.pointerId)) event.currentTarget.releasePointerCapture(event.pointerId);
  };
  const width = Math.min(size.width, size.height * ratio);
  return <div className="cmp-stage-space" ref={container}>
    <div className="cmp-stage" ref={stage} tabIndex={0} aria-label={`${canvasLabel || 'Image canvas'}: scroll or pinch to zoom, drag to pan`} onFocus={onActivate}
      data-compare-stage="true" data-zoom={viewport.zoom} data-pan-x={viewport.x} data-pan-y={viewport.y}
      style={{ width, height: width / ratio, touchAction: view === 'gallery' && viewport.zoom === 1 ? `pan-${scrollAxis}` : 'none' }}
      onPointerDown={event => {
        if (event.button !== 0) return;
        const divider = (event.target as HTMLElement)?.closest<HTMLElement>('[data-compare-divider]');
        if (divider) {
          event.preventDefault(); divider.focus({ preventScroll: true });
          if (!pointers.current.size) reveal.current = { pointerId: event.pointerId, x: event.clientX, split };
        } else { onActivate?.(); event.currentTarget.focus({ preventScroll: true }); }
        event.currentTarget.setPointerCapture(event.pointerId);
        pointers.current.set(event.pointerId, { x: event.clientX, y: event.clientY }); pinch.current = pinchState();
        // A second finger always starts a pinch, even when the first is on the handle.
        if (pointers.current.size > 1) reveal.current = null;
      }}
      onPointerMove={event => {
        const previous = pointers.current.get(event.pointerId); if (!previous) return;
        pointers.current.set(event.pointerId, { x: event.clientX, y: event.clientY });
        const rect = event.currentTarget.getBoundingClientRect();
        if (!rect.width || !rect.height) return;
        const nextPinch = pinchState();
        if (nextPinch && pinch.current && pinch.current.distance > 0) {
          const old = pinch.current;
          setViewport(value => {
            const zoomed = zoomViewport(value, value.zoom * nextPinch.distance / old.distance, { x: (old.midpoint.x - rect.left) / rect.width - .5, y: (old.midpoint.y - rect.top) / rect.height - .5 });
            return clampViewport({ ...zoomed, x: zoomed.x + (nextPinch.midpoint.x - old.midpoint.x) / rect.width, y: zoomed.y + (nextPinch.midpoint.y - old.midpoint.y) / rect.height });
          });
        } else if (reveal.current?.pointerId === event.pointerId && view === 'slider') {
          const value = event.clientX <= rect.left ? 0 : event.clientX >= rect.left + rect.width ? 100
            : reveal.current.split + (event.clientX - reveal.current.x) / rect.width * 100;
          setSplit?.(Math.max(0, Math.min(100, value)));
        } else if (pointers.current.size === 1) {
          setViewport(value => clampViewport({ ...value, x: value.x + (event.clientX - previous.x) / rect.width, y: value.y + (event.clientY - previous.y) / rect.height }));
        }
        pinch.current = nextPinch;
      }} onPointerUp={endPointer} onPointerCancel={endPointer} onLostPointerCapture={endPointer}>
      {media.map((item, index) => <OriginalImage key={`${item.id}:${item.url}`} media={item} active={active} viewport={viewports?.[item.id] || viewport}
        statusIndex={view === 'slider' ? index : 0}
        clipPath={view === 'slider' && index === 1 ? `inset(0 ${100 - split}% 0 0)` : undefined}
        onDimensions={onDimensions} refreshSource={refreshSource} />)}
      {view === 'slider' && <div className="cmp-divider" style={{ '--split': `${split}%` } as React.CSSProperties}>
        <div className="cmp-divider-line" style={{ left: `${split}%` }} aria-hidden="true" />
        <div className="cmp-divider-control" data-compare-divider="true" role="slider" tabIndex={0}
          aria-label={revealLabel} aria-orientation="horizontal" aria-valuemin={0} aria-valuemax={100}
          aria-valuenow={Math.round(split)} aria-valuetext={revealValueText ? revealValueText(Math.round(split)) : `${Math.round(split)}% of image B revealed`}
          onKeyDown={event => {
            const delta = { ArrowLeft: -1, ArrowDown: -1, ArrowRight: 1, ArrowUp: 1, PageDown: -10, PageUp: 10 }[event.key];
            if (delta === undefined && event.key !== 'Home' && event.key !== 'End') return;
            event.preventDefault(); event.stopPropagation();
            setSplit?.(event.key === 'Home' ? 0 : event.key === 'End' ? 100 : Math.max(0, Math.min(100, split + delta!)));
          }}>
          <div className="cmp-divider-grip" aria-hidden="true"><Columns2 /></div>
        </div>
      </div>}
    </div>
  </div>;
}

