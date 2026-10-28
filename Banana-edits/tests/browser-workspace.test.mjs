import 'fake-indexeddb/auto';
import test from 'node:test';
import assert from 'node:assert/strict';
import { createBrowserWorkspaceClient, matches } from '../src/services/browserWorkspace.mjs';

test('browser media, folders, preferences and file bytes survive reopening', async () => {
  const identity = { userId: '090dd6c2-0a35-46e9-b647-ed758c28824e', sessionId: 'cf11efeb-c4fb-4cea-8621-71485eb6cd90' };
  const client = createBrowserWorkspaceClient(identity);
  assert.equal((await client.from('profiles').select('*').single()).data.id, identity.userId);
  assert.equal((await client.from('authorized_emails').select('email').eq('is_active', true).ilike('email', 'browser@example.invalid').maybeSingle()).data.email, 'browser@example.invalid');
  assert.equal((await client.from('folders').insert({id:'folder-1',name:'Work',user_id:identity.userId})).error, null);
  assert.equal((await client.from('generations').insert({id:'image-1',prompt:'A pear',folder_id:'folder-1',metadata:{imported:true},reference_images:[{personName:'Test person'}]})).error, null);
  const file = new Blob(['test-file-bytes'], { type: 'image/png' });
  assert.equal((await client.storage.from('media').upload('sample.png', file)).error, null);
  await client.from('generations').update({ is_favorite: true }).eq('id', 'image-1');
  await client.rpc('save_provider_preference', {p_model:'gpt-image-2.5-sunburst',p_provider:'auto'});
  await client.rpc('save_text_model_preferences', {p_model:'gpt-6.1-sol',p_openai_reasoning:'high'});
  const reopened = createBrowserWorkspaceClient(identity);
  const result = await reopened.from('generations').select('id,is_favorite,metadata').eq('folder_id','folder-1').single();
  assert.equal(result.error, null); assert.equal(result.data.is_favorite, true); assert.deepEqual(result.data.metadata,{imported:true});
  assert.equal(await (await reopened.storage.from('media').download('sample.png')).data.text(), 'test-file-bytes');
  assert.deepEqual((await reopened.rpc('get_provider_preferences')).data, {'gpt-image-2.5-sunburst':'auto'});
  assert.equal((await reopened.rpc('get_text_model_preferences')).data.reasoningEffort,'high');
  assert.deepEqual((await reopened.rpc('get_gallery_search_people')).data[0].people, ['Test person']);
  assert.equal((await reopened.from('generations').delete().eq('id','image-1')).error, null);
  assert.equal((await reopened.from('generations').select('*').maybeSingle()).data, null);
});

test('browser queries roll back duplicates and retain explicit mutation filters', async () => {
  const client = createBrowserWorkspaceClient({userId:'local-user'});
  await client.from('templates').insert({id:'one',name:'First'});
  const duplicate = await client.from('templates').insert([{id:'two',name:'Second'},{id:'one',name:'Duplicate'}]);
  assert.ok(duplicate.error);
  assert.equal((await client.from('templates').select('*').eq('id','two').maybeSingle()).data,null);
  assert.ok((await client.from('templates').delete()).error);
  assert.equal((await client.from('templates').select('*').eq('id','one').single()).data.name,'First');
  assert.equal(matches({email:'name_one@example.invalid'}, {column:'email',operator:'ilike',value:'name\\_one@example.invalid'}),true);
  assert.equal(matches({email:'nameXone@example.invalid'}, {column:'email',operator:'ilike',value:'name\\_one@example.invalid'}),false);
});
