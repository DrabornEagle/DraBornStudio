import test from 'node:test';
import assert from 'node:assert/strict';
import {webcrypto} from 'node:crypto';
import {uniqueId} from '../src/services/browserId.mjs';

test('local HTTP previews create persistent record IDs without randomUUID', () => {
  const fallback = {getRandomValues: bytes => webcrypto.getRandomValues(bytes)};
  const ids = new Set(Array.from({length: 100}, () => uniqueId(fallback)));
  assert.equal(ids.size, 100);
  for (const id of ids) assert.match(id, /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
  assert.equal(uniqueId({randomUUID: () => 'native-id'}), 'native-id');
});
