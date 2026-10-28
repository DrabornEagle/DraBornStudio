// Synthetic metadata-only benchmark; no user media, accounts or provider calls.
// Run with Node 24+: node scripts/benchmark-gallery-folder-stats.mjs
import assert from 'node:assert/strict';
import { performance } from 'node:perf_hooks';
import { buildGalleryFolderStats } from '../src/components/galleryFolderStats.ts';

const cost = item => item.cost;

// The previous Gallery derivation: visible-card counts plus the memoized
// recursive folder-cost pass. Synthetic data contains no private records.
function previousGalleryStats(folders, media, visibleIds) {
  const children = new Map(), direct = new Map(), totals = new Map();
  for (const folder of folders) {
    if (!folder.parentId) continue;
    const list = children.get(folder.parentId) || [];
    list.push(folder); children.set(folder.parentId, list);
  }
  for (const item of media) {
    if (!item.folderId) continue;
    const list = direct.get(item.folderId) || [];
    list.push(item); direct.set(item.folderId, list);
  }
  const compute = id => {
    if (totals.has(id)) return totals.get(id);
    let total = 0;
    (direct.get(id) || []).forEach(item => { total += cost(item); });
    (children.get(id) || []).forEach(child => { total += compute(child.id); });
    totals.set(id, total); return total;
  };
  folders.forEach(folder => compute(folder.id));
  const badges = new Map(folders.filter(folder => visibleIds.has(folder.id)).map(folder => {
    const directMediaCount = media.filter(item => item.folderId === folder.id).length;
    const directChildFolderCount = folders.filter(child => child.parentId === folder.id).length;
    return [folder.id, { directMediaCount, directChildFolderCount, itemCount: directMediaCount + directChildFolderCount }];
  }));
  return { costs: totals, badges };
}

function sample(label, folderCount, mediaCount, deep) {
  const folders = Array.from({ length: folderCount }, (_, index) => ({
    id: `folder-${index}`,
    parentId: deep && index ? `folder-${index - 1}` : null,
  }));
  const media = Array.from({ length: mediaCount }, (_, index) => ({
    folderId: `folder-${(index * 37) % folderCount}`, cost: (index % 7) * 0.0123,
  }));
  const visibleIds = new Set(folders.filter(folder => !folder.parentId).map(folder => folder.id));
  const before = () => previousGalleryStats(folders, media, visibleIds);
  const after = () => {
    const stats = buildGalleryFolderStats(folders, media, cost);
    return {
      costs: new Map([...stats].map(([id, value]) => [id, value.totalCost])),
      badges: new Map([...stats].filter(([id]) => visibleIds.has(id)).map(([id, { totalCost, ...badge }]) => [id, badge])),
    };
  };
  assert.deepEqual(after(), before(), `${label}: result parity`);
  for (let i = 0; i < 5; i++) { before(); after(); }
  const times = fn => {
    const samples = [];
    for (let i = 0; i < 11; i++) { const start = performance.now(); fn(); samples.push(performance.now() - start); }
    return samples.sort((a, b) => a - b)[Math.floor(samples.length / 2)];
  };
  const previousMs = times(before), indexedMs = times(after);
  return { label, folderCount, mediaCount, visibleBadgeCount: visibleIds.size, warmupRuns: 5, measuredRuns: 11, resultParity: true,
    previousMedianMs: +previousMs.toFixed(3), indexedMedianMs: +indexedMs.toFixed(3), speedup: +(previousMs / indexedMs).toFixed(2) };
}

console.log(JSON.stringify({ synthetic: true, node: process.version, cases: [
  sample('300 root folders', 300, 20_000, false),
  sample('1000-folder deep chain', 1000, 20_000, true),
] }, null, 2));
