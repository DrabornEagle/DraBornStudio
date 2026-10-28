import assert from 'node:assert/strict';
import test from 'node:test';
import { buildGalleryFolderStats } from '../src/components/galleryFolderStats.ts';

// Same pricing policy as Gallery: actual cost wins; unknown videos are not
// estimated; an image estimate may be unavailable. The index knows no prices.
const cost = item => typeof item.generationCost?.usd === 'number' ? item.generationCost.usd
  : item.mediaType === 'video' ? 0 : item.imageEstimate ?? 0;

test('folder badges count direct media and subfolders while costs include descendants', () => {
  const folders = [
    { id: 'root' }, { id: 'child', parentId: 'root' }, { id: 'grandchild', parentId: 'child' },
    { id: 'empty', parentId: 'root' }, { id: 'orphan', parentId: 'missing' },
  ];
  const media = [
    { folderId: 'root', generationCost: { usd: 1 } },
    { folderId: 'child', generationCost: { usd: 2 } },
    { folderId: 'child', mediaType: 'video' },
    { folderId: 'grandchild', imageEstimate: 0.25 },
    { folderId: 'orphan', imageEstimate: 0.5 },
    { folderId: 'missing', generationCost: { usd: 100 } },
    { folderId: null, generationCost: { usd: 200 } },
  ];
  const actual = buildGalleryFolderStats(folders, media, cost);
  assert.deepEqual(actual.get('root'), { directMediaCount: 1, directChildFolderCount: 2, itemCount: 3, totalCost: 3.25 });
  assert.deepEqual(actual.get('child'), { directMediaCount: 2, directChildFolderCount: 1, itemCount: 3, totalCost: 2.25 });
  assert.deepEqual(actual.get('empty'), { directMediaCount: 0, directChildFolderCount: 0, itemCount: 0, totalCost: 0 });
  assert.equal(actual.get('orphan').totalCost, 0.5);
  assert.equal(actual.has('missing'), false);
});

test('cost callback runs once per known-folder media and controls actual, estimated and unknown costs', () => {
  const media = [
    { folderId: 'a', mediaType: 'video', generationCost: { usd: 0 } },
    { folderId: 'a', mediaType: 'video', generationCost: { usd: 1.25 } },
    { folderId: 'a', mediaType: 'video', imageEstimate: 50 },
    { folderId: 'a', imageEstimate: 0.5 }, { folderId: 'a' },
    { folderId: 'missing', imageEstimate: 100 }, { imageEstimate: 100 },
  ];
  const calls = [];
  const result = buildGalleryFolderStats([{ id: 'a' }], media, item => { calls.push(item); return cost(item); });
  assert.equal(result.get('a').totalCost, 1.75);
  assert.equal(result.get('a').directMediaCount, 5);
  assert.deepEqual(calls, media.slice(0, 5));
});

test('cycles sum each reachable media once and do not prevent unrelated folders from loading', () => {
  const folders = [
    { id: 'a', parentId: 'b' }, { id: 'b', parentId: 'a' }, { id: 'c', parentId: 'a' },
    { id: 'self', parentId: 'self' }, { id: 'separate' },
  ];
  const media = ['a', 'b', 'c', 'self', 'separate'].map((folderId, index) => ({ folderId, generationCost: { usd: index + 1 } }));
  const result = buildGalleryFolderStats(folders, media, cost);
  assert.equal(result.get('a').totalCost, 6);
  assert.equal(result.get('b').totalCost, 6);
  assert.equal(result.get('c').totalCost, 3);
  assert.equal(result.get('self').totalCost, 4);
  assert.equal(result.get('self').itemCount, 2);
  assert.equal(result.get('separate').totalCost, 5);
});

test('iterative traversal tolerates 20,000 nested folders without stack overflow', () => {
  const folders = Array.from({ length: 20_000 }, (_, i) => ({ id: String(i), parentId: i ? String(i - 1) : null }));
  const result = buildGalleryFolderStats(folders, [{ folderId: '19999', generationCost: { usd: 0.25 } }], cost);
  assert.equal(result.get('0').totalCost, 0.25);
  assert.equal(result.get('0').itemCount, 1);
  assert.equal(result.get('19999').totalCost, 0.25);
});

test('aggregation retains legacy ordered floating-point sums and never mutates input rows', () => {
  const folders = Object.freeze([{ id: 'a' }, { id: 'b', parentId: 'a' }, { id: 'c', parentId: 'a' }].map(Object.freeze));
  const media = Object.freeze([
    { folderId: 'a', generationCost: { usd: 0.1 } },
    { folderId: 'b', generationCost: { usd: 0.2 } },
    { folderId: 'c', generationCost: { usd: 0.3 } },
  ].map(Object.freeze));
  const first = buildGalleryFolderStats(folders, media, cost);
  assert.equal(first.get('a').totalCost, (0.1 + 0.2) + 0.3);
  assert.deepEqual(buildGalleryFolderStats(folders, media, cost), first);
  assert.equal(media[0].generationCost.usd, 0.1);
  assert.deepEqual(buildGalleryFolderStats([], media, cost), new Map());
});
