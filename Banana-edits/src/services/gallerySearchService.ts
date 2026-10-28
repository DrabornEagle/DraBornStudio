import { supabase, getCurrentUserId } from './authService';
import type { SearchPeople } from '../components/gallerySearch';

/** Read names only. Fetching reference_images would download embedded photos. */
export const getGallerySearchPeople = async (ownerId?: string | null, signal?: AbortSignal): Promise<SearchPeople> => {
  if (!supabase) throw new Error('Search people could not be loaded.');
  const sessionUser = await getCurrentUserId();
  if (!sessionUser) throw new Error('Sign in to search your gallery.');
  const people: SearchPeople = {};
  let cursor: string | null = null;
  while (true) {
    signal?.throwIfAborted();
    let request = supabase.rpc('get_gallery_search_people', { p_owner_id: ownerId || sessionUser, p_after_id: cursor, p_limit: 500 });
    if (signal) request = request.abortSignal(signal);
    const { data, error } = await request;
    signal?.throwIfAborted();
    if (await getCurrentUserId() !== sessionUser) throw new Error('The gallery account changed. Reopen search.');
    if (error) throw new Error('Person filters could not be loaded. Try again.');
    const rows = (data || []) as { id: string; people: string[] }[];
    if (!rows.length) return people;
    for (const row of rows) people[row.id] = Array.isArray(row.people) ? row.people.filter(name => typeof name === 'string' && name.trim()) : [];
    const nextCursor = rows[rows.length - 1].id;
    if (!nextCursor || nextCursor === cursor) throw new Error('Person filters could not be fully loaded. Try again.');
    cursor = nextCursor;
    // Read until an empty page: Data API row limits may be lower than p_limit.
  }
};
