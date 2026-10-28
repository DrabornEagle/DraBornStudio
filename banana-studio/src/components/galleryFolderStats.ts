export interface GalleryFolderStats {
  directMediaCount: number;
  directChildFolderCount: number;
  /** The existing badge counts direct media and direct subfolders. */
  itemCount: number;
  /** Direct media costs plus every descendant folder's media costs. */
  totalCost: number;
}

type FolderEntry = { id: string; parentId?: string | null };

/** Index once per loaded gallery, rather than filtering all media for every card.
 * Pricing remains the caller's responsibility, including unknown video costs.
 * Parent cycles are collapsed, so malformed trees neither recurse forever nor
 * charge the same media twice. Iterative traversal also handles deep folders. */
export function buildGalleryFolderStats<Media extends { folderId?: string | null }>(
  folders: readonly FolderEntry[],
  media: readonly Media[],
  costPerMedia: (item: Media) => number,
): Map<string, GalleryFolderStats> {
  const byId = new Map(folders.map(folder => [folder.id, folder]));
  const stats = new Map<string, GalleryFolderStats>();
  for (const id of byId.keys()) stats.set(id, {
    directMediaCount: 0, directChildFolderCount: 0, itemCount: 0, totalCost: 0,
  });
  for (const folder of byId.values()) {
    const parent = folder.parentId ? stats.get(folder.parentId) : undefined;
    if (parent) { parent.directChildFolderCount++; parent.itemCount++; }
  }
  for (const item of media) {
    const target = item.folderId ? stats.get(item.folderId) : undefined;
    if (!target) continue;
    target.directMediaCount++; target.itemCount++;
    target.totalCost += costPerMedia(item);
  }

  // A folder has at most one parent. A parent-pointer walk therefore finds
  // every cycle in linear time, without a recursive graph algorithm.
  const componentOf = new Map<string, string>();
  for (const start of byId.keys()) {
    if (componentOf.has(start)) continue;
    const path: string[] = [], positions = new Map<string, number>();
    let current: string | null | undefined = start;
    while (current && byId.has(current) && !componentOf.has(current)) {
      const cycleStart = positions.get(current);
      if (cycleStart !== undefined) {
        for (let index = cycleStart; index < path.length; index++) componentOf.set(path[index], current);
        break;
      }
      positions.set(current, path.length); path.push(current);
      current = byId.get(current)!.parentId;
    }
    for (const id of path) if (!componentOf.has(id)) componentOf.set(id, id);
  }

  const ownCosts = new Map<string, number>();
  const children = new Map<string, string[]>();
  for (const [id, folder] of byId) {
    const component = componentOf.get(id)!;
    ownCosts.set(component, (ownCosts.get(component) ?? 0) + stats.get(id)!.totalCost);
    const parent = folder.parentId ? componentOf.get(folder.parentId) : undefined;
    if (parent && parent !== component) {
      const list = children.get(parent) || [];
      list.push(component); children.set(parent, list);
    }
  }
  const totals = new Map<string, number>();
  type Frame = { id: string; nextChild: number; total: number };
  for (const component of ownCosts.keys()) {
    if (totals.has(component)) continue;
    const stack: Frame[] = [{ id: component, nextChild: 0, total: ownCosts.get(component)! }];
    while (stack.length) {
      const frame = stack[stack.length - 1];
      const descendants = children.get(frame.id) || [];
      if (frame.nextChild < descendants.length) {
        const child = descendants[frame.nextChild++];
        if (totals.has(child)) frame.total += totals.get(child)!;
        else stack.push({ id: child, nextChild: 0, total: ownCosts.get(child)! });
      } else {
        totals.set(frame.id, frame.total); stack.pop();
        if (stack.length) stack[stack.length - 1].total += frame.total;
      }
    }
  }
  for (const [id, value] of stats) value.totalCost = totals.get(componentOf.get(id)!)!;
  return stats;
}
