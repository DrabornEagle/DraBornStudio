import type { Folder, GeneratedMedia } from '../types';

export type FolderPreviewSource = { kind: 'image' | 'video'; src: string };
export const folderPreviewSourceKey = (source: FolderPreviewSource) => `${source.kind}:${source.src}`;

export const getFolderPreviewSources = (media: GeneratedMedia): FolderPreviewSource[] => {
  const sources: FolderPreviewSource[] = [];
  if (media.thumbnailUrl?.trim()) sources.push({ kind: 'image', src: media.thumbnailUrl });
  if (media.url?.trim()) sources.push({ kind: media.mediaType === 'video' ? 'video' : 'image', src: media.url });
  return sources.filter((source, index) => sources.findIndex(other => other.kind === source.kind && other.src === source.src) === index);
};

// Direct media comes first, then the newest descendants. Keep candidates beyond
// the three visible tiles so failed files can be replaced without a data reload.
export const buildFolderPreviewIndex = (folders: Folder[], images: GeneratedMedia[]) => {
  const parents = new Map(folders.map(folder => [folder.id, folder.parentId]));
  const direct = new Map<string, GeneratedMedia[]>();
  const descendants = new Map<string, GeneratedMedia[]>();
  const seenMedia = new Set<string>();
  for (const media of [...images].sort((a, b) => b.createdAt - a.createdAt)) {
    if (seenMedia.has(media.id) || media.isLoading || media.error ||
      (media.status && media.status !== 'completed') || !(media.url?.trim() || media.thumbnailUrl?.trim())) continue;
    seenMedia.add(media.id);
    const visited = new Set<string>();
    let folderId = media.folderId;
    while (folderId && parents.has(folderId) && !visited.has(folderId)) {
      const target = visited.size === 0 ? direct : descendants;
      const items = target.get(folderId) || [];
      items.push(media);
      target.set(folderId, items);
      visited.add(folderId);
      folderId = parents.get(folderId);
    }
  }
  return new Map(folders.map(folder => [folder.id, [...(direct.get(folder.id) || []), ...(descendants.get(folder.id) || [])]]));
};

export const selectFolderPreviewTiles = (media: GeneratedMedia[], failedSources: ReadonlySet<string>) => {
  const tiles: Array<{ id: string; source: FolderPreviewSource }> = [];
  for (const item of media) {
    const source = getFolderPreviewSources(item).find(value => !failedSources.has(folderPreviewSourceKey(value)));
    if (source) tiles.push({ id: item.id, source });
    if (tiles.length === 3) break;
  }
  return tiles;
};
