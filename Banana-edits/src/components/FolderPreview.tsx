import React, { useEffect, useRef, useState } from 'react';
import type { GeneratedMedia } from '../types';
import { folderPreviewSourceKey, selectFolderPreviewTiles, type FolderPreviewSource } from './folderPreviews';

export const FolderPreview: React.FC<{ media: GeneratedMedia[] }> = ({ media }) => {
  const [failedSources, setFailedSources] = useState<Set<string>>(() => new Set());
  const tiles = selectFolderPreviewTiles(media, failedSources);
  if (!tiles.length) return null;

  return <div aria-hidden="true" className="pointer-events-none absolute inset-y-0 right-0 w-[46%] overflow-hidden opacity-50 transition-opacity group-hover:opacity-70">
    <div className={`grid h-full min-h-0 gap-px ${tiles.length === 1 ? 'grid-cols-1' : 'grid-cols-2'} ${tiles.length === 3 ? 'grid-rows-2' : 'grid-rows-1'}`}>
      {tiles.map((tile, index) => <PreviewTile
        key={JSON.stringify([tile.id, folderPreviewSourceKey(tile.source)])}
        source={tile.source}
        className={tiles.length === 3 && index === 0 ? 'row-span-2' : ''}
        onError={() => setFailedSources(previous => new Set(previous).add(folderPreviewSourceKey(tile.source)))}
      />)}
    </div>
    <div className="absolute inset-0 bg-gradient-to-r from-[#121923] via-[#121923]/35 to-transparent" />
    <div className="absolute inset-0 bg-gradient-to-t from-[#121923]/80 via-transparent to-[#121923]/20" />
  </div>;
};

const PreviewTile: React.FC<{
  source: FolderPreviewSource; className: string; onError: () => void;
}> = ({ source, className, onError }) => {
  const container = useRef<HTMLDivElement>(null);
  const [visible, setVisible] = useState(false);
  const [loaded, setLoaded] = useState(false);
  useEffect(() => {
    if (!container.current) return;
    const observer = new IntersectionObserver(entries => {
      if (entries.some(entry => entry.isIntersecting)) {
        setVisible(true);
        observer.disconnect();
      }
    }, { rootMargin: '350px' });
    observer.observe(container.current);
    return () => observer.disconnect();
  }, []);

  const assetClass = `absolute inset-0 h-full w-full object-cover transition-opacity ${loaded ? 'opacity-100' : 'opacity-0'}`;
  // Unloaded tiles stay invisible until their asset fades in. The skeleton keeps
  // every slot visible so all folder strips share identical geometry on mobile,
  // where video frames load well after the grid appears.
  return <div ref={container} className={`relative min-h-0 min-w-0 overflow-hidden bg-white/[0.04] ${className}`}>
    {!loaded && <div aria-hidden="true" className="absolute inset-0 animate-pulse bg-gray-800/70" />}
    {visible && (source.kind === 'image'
      ? <img src={source.src} alt="" draggable={false} decoding="async" className={assetClass} onLoad={() => setLoaded(true)} onError={onError} />
      : <video src={`${source.src.split('#')[0]}#t=0.1`} muted playsInline preload="auto" draggable={false} className={assetClass}
        onLoadedMetadata={event => {
          const video = event.currentTarget;
          if (Number.isFinite(video.duration) && video.duration > 0.2) video.currentTime = Math.min(1, video.duration * 0.1);
        }}
        onLoadedData={() => setLoaded(true)} onSeeked={() => setLoaded(true)} onError={onError} />)}
  </div>;
};
