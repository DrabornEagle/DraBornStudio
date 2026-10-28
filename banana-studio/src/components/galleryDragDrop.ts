export const GALLERY_DRAG_TYPE = 'application/nanogen-type';
export const GALLERY_DRAG_ID = 'application/nanogen-id';
export const GALLERY_DRAG_MEDIA_IDS = 'application/nanogen-image-ids';

export type GalleryDragPayload =
  | { type: 'image'; ids: string[] }
  | { type: 'folder'; id: string };

interface GalleryMediaLocation {
  id: string;
  folderId?: string | null;
  isLoading?: boolean;
}

interface GalleryFolderLocation {
  id: string;
  parentId?: string | null;
}

/** A selected card drags the selection; an unselected card drags only itself. */
export const getDraggedMediaIds = (
  draggedId: string,
  isSelectionMode: boolean,
  selectedIds: ReadonlySet<string>,
  media: readonly GalleryMediaLocation[],
): string[] => {
  const movableIds = new Set(media.filter(item => !item.isLoading).map(item => item.id));
  if (!movableIds.has(draggedId)) return [];
  const candidates = isSelectionMode && selectedIds.has(draggedId)
    ? Array.from(selectedIds)
    : [draggedId];
  return candidates.filter(id => movableIds.has(id));
};

/** Retain legacy single-item payloads, but never partially accept a broken batch. */
export const readGalleryDragPayload = (
  transfer: Pick<DataTransfer, 'getData'>,
): GalleryDragPayload | null => {
  const type = transfer.getData(GALLERY_DRAG_TYPE);
  const id = transfer.getData(GALLERY_DRAG_ID);
  if (type === 'folder') return id ? { type, id } : null;
  if (type !== 'image') return null;

  const serializedIds = transfer.getData(GALLERY_DRAG_MEDIA_IDS);
  if (serializedIds) {
    try {
      const ids: unknown = JSON.parse(serializedIds);
      if (!Array.isArray(ids) || ids.length === 0 || ids.some(value => typeof value !== 'string' || !value.trim())) {
        return null;
      }
      return { type, ids: Array.from(new Set(ids)) };
    } catch {
      return null;
    }
  }
  return id ? { type, ids: [id] } : null;
};

export const getMediaIdsForMove = (
  ids: readonly string[],
  targetFolderId: string | null,
  media: readonly GalleryMediaLocation[],
): string[] => {
  const movableIds = new Set(media
    .filter(item => !item.isLoading && (item.folderId || null) !== targetFolderId)
    .map(item => item.id));
  return Array.from(new Set(ids)).filter(id => movableIds.has(id));
};

/** Reject self/descendant drops before an optimistic folder update can form a cycle. */
export const canMoveGalleryFolder = (
  folderId: string,
  targetParentId: string | null,
  folders: readonly GalleryFolderLocation[],
): boolean => {
  const folder = folders.find(item => item.id === folderId);
  if (!folder || (folder.parentId || null) === targetParentId) return false;
  const visited = new Set<string>();
  let ancestorId = targetParentId;
  while (ancestorId) {
    if (ancestorId === folderId || visited.has(ancestorId)) return false;
    visited.add(ancestorId);
    const ancestor = folders.find(item => item.id === ancestorId);
    if (!ancestor) return false;
    ancestorId = ancestor.parentId || null;
  }
  return true;
};
