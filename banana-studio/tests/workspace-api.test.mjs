import test from 'node:test';
import assert from 'node:assert/strict';
import { createWorkspaceFetch, initializeWorkspaceApi, workspaceFetch, validateApiBase } from '../src/services/workspaceApi.mjs';

test('explicit Pages configuration starts locally without probing an unavailable API', async () => {
  const originalFetch=globalThis.fetch, originalLocation=globalThis.location;
  let calls=0;
  globalThis.location={origin:'https://www.example.invalid'};
  globalThis.fetch=async url=>{calls++;assert.equal(url.href,'https://www.example.invalid/Banana-edits/workspace.json');return Response.json({mode:'browser',apiBase:'/api/banana-studio'});};
  try {
    assert.equal(await initializeWorkspaceApi(),true);
    assert.equal((await workspaceFetch('/api/banana-studio/gemini-status')).status,200);
    assert.equal(calls,1);
  } finally {globalThis.fetch=originalFetch;if(originalLocation===undefined)delete globalThis.location;else globalThis.location=originalLocation;}
});

test('browser gallery never sends local identity, media or prompts to a server', async () => {
  let calls = 0;
  const send = createWorkspaceFetch({ getMode: () => 'browser', getApiBase: () => 'https://backend.example.invalid/api/banana-studio', getOrigin: () => 'https://www.example.invalid', fetchImpl: async () => { calls++; throw new Error('Unexpected network request.'); } });
  for (const route of ['openai-image-enqueue', 'gemini-generate', 'folder-share', 'youtube', 'fal-status?requestId=example']) {
    const response = await send('/api/banana-studio/' + route, { method: 'POST', headers: { Authorization: 'Bearer synthetic-local-identity' }, body: '{"prompt":"local only"}' });
    assert.equal(response.status, 503);
    assert.equal((await response.json()).code, 'BANANA_SETUP_REQUIRED');
  }
  for (const route of ['gemini-status', 'youtube-status']) {
    const response = await send('/api/banana-studio/' + route);
    assert.deepEqual(await response.json(), { configured: false, providers: {} });
  }
  assert.equal(calls, 0);
});

test('Pages frontend can use an explicit HTTPS API while omitting cross-origin cookies', async () => {
  let called;
  const send = createWorkspaceFetch({ getMode: () => 'cloud', getApiBase: () => 'https://api.example.invalid/api/banana-studio/', getOrigin: () => 'https://www.example.invalid', fetchImpl: async (...args) => { called = args; return new Response('{}'); } });
  await send('/api/banana-studio/fal-status?requestId=safe%20id', { credentials: 'include', headers: { Authorization: 'Bearer synthetic-cloud-token' } });
  assert.equal(called[0], 'https://api.example.invalid/api/banana-studio/fal-status?requestId=safe%20id');
  assert.equal(called[1].credentials, 'omit');
  assert.equal(called[1].redirect, 'error');
  assert.equal(called[1].headers.Authorization, 'Bearer synthetic-cloud-token');
});

test('bootstrap and media downloads retain their own request semantics', async () => {
  const calls = [];
  const send = createWorkspaceFetch({ getMode: () => undefined, getApiBase: () => '/api/banana-studio', getOrigin: () => 'https://www.example.invalid', fetchImpl: async (...args) => { calls.push(args); return new Response('{}'); } });
  await send('/api/banana-studio/workspace-config');
  assert.equal(calls[0][0], 'https://www.example.invalid/api/banana-studio/workspace-config');
  assert.equal(calls[0][1].credentials, 'same-origin');
  await send('blob:https://www.example.invalid/local-file', { cache: 'no-store' });
  assert.equal(calls[1][0], 'blob:https://www.example.invalid/local-file');
  assert.deepEqual(calls[1][1], { cache: 'no-store' });
});

test('API configuration rejects insecure origins, embedded credentials and query secrets', async () => {
  for (const value of ['http://remote.example.invalid/api', 'https://user:password@example.invalid/api', 'https://example.invalid/api?key=synthetic', 'https://example.invalid/api#token', '//example.invalid/api', 'javascript:alert(1)', '']) {
    assert.throws(() => validateApiBase(value, 'https://www.example.invalid'));
  }
  const signal = AbortSignal.abort();
  const send = createWorkspaceFetch({ getMode: () => 'browser', getApiBase: () => '', getOrigin: () => '', fetchImpl: () => { throw new Error('Must not submit'); } });
  await assert.rejects(send('/api/banana-studio/gemini-generate', { signal }), { name: 'AbortError' });
});
