import { workspaceFetch } from './workspaceApi.mjs';
import { getSession } from './authService';
import { readFolderShareStatus, type FolderShareStatus } from '../lib/gallery/folderShareResponse';

export type { FolderShareStatus } from '../lib/gallery/folderShareResponse';
export async function manageFolderShare(folderId: string, action: 'status' | 'create' | 'revoke'): Promise<FolderShareStatus> {
  const session = await getSession();
  if (!session?.access_token) throw new Error('Sign in again to manage sharing.');
  const response = await workspaceFetch('/api/banana-edits/folder-share', {
    method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${session.access_token}` },
    body: JSON.stringify({ folderId, action }), cache: 'no-store',
  });
  return readFolderShareStatus(response);
}
