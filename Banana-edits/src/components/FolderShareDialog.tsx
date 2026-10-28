import React, { useEffect, useRef, useState } from 'react';
import { Check, Copy, ExternalLink, Link, Loader2, X } from 'lucide-react';
import type { Folder } from '../types';
import { manageFolderShare, type FolderShareStatus } from '../services/folderShareService';

export const FolderShareDialog: React.FC<{ folder: Folder; onClose: () => void }> = ({ folder, onClose }) => {
  const dialog = useRef<HTMLDialogElement>(null);
  const [status, setStatus] = useState<FolderShareStatus | null>(null);
  const [busy, setBusy] = useState(true);
  const [error, setError] = useState('');
  const [copied, setCopied] = useState(false);
  const url = status?.active && status.token ? `${window.location.origin}/DraBornStudio/Banana-edits/share.html#${status.token}` : '';
  useEffect(() => {
    dialog.current?.showModal();
    let cancelled = false;
    manageFolderShare(folder.id, 'status').then(value => { if (!cancelled) setStatus(value); })
      .catch(error => { if (!cancelled) setError(error.message); })
      .finally(() => { if (!cancelled) setBusy(false); });
    return () => { cancelled = true; };
  }, [folder.id]);
  const update = async (action: 'status' | 'create' | 'revoke') => {
    setBusy(true); setError(''); setCopied(false);
    try { setStatus(await manageFolderShare(folder.id, action)); }
    catch (error) { setError(error instanceof Error ? error.message : 'Sharing could not be updated.'); }
    finally { setBusy(false); }
  };
  const copy = async () => {
    try { await navigator.clipboard.writeText(url); setCopied(true); }
    catch { setError('Copy was blocked. Select the link below and copy it manually.'); }
  };
  return <dialog ref={dialog} onCancel={event => { event.preventDefault(); if (!busy) onClose(); }}
    aria-labelledby="folder-share-title" className="m-auto w-[calc(100%-2rem)] max-w-lg rounded-2xl border border-white/10 bg-[#161b22] p-6 text-gray-200 shadow-2xl backdrop:bg-black/75">
    <div className="flex items-start justify-between gap-4">
      <div className="min-w-0"><h2 id="folder-share-title" className="flex items-center gap-2 text-lg font-semibold"><Link className="h-5 w-5 text-violet-400" /> Share folder</h2>
        <p className="mt-1 break-words text-sm text-gray-400">{folder.name}</p></div>
      <button aria-label="Close sharing" onClick={onClose} disabled={busy} className="rounded-lg p-2 hover:bg-white/5 disabled:opacity-40"><X className="h-5 w-5" /></button>
    </div>
    <p className="mt-5 text-sm leading-relaxed text-gray-300">Anyone with the link can view and download this folder’s images without signing in. New images added here will also be shared.</p>
    <p className="mt-2 text-xs leading-relaxed text-gray-400">Subfolders, videos, prompts and reference photos are excluded. Links expire after 30 days.</p>
    {status && <p className="mt-5 text-sm font-medium">{status.active ? 'Link sharing is on' : 'Link sharing is off'}{status.active && status.expiresAt && <span className="mt-1 block text-xs font-normal text-gray-400">Expires {new Date(status.expiresAt).toLocaleDateString()}</span>}</p>}
    {url && <div className="mt-3 flex gap-2"><input aria-label="Folder share URL" readOnly value={url} onFocus={event => event.target.select()} className="min-w-0 flex-1 rounded-lg border border-white/10 bg-black/20 px-3 py-2 text-sm" />
      <button onClick={copy} aria-live="polite" className="flex shrink-0 items-center gap-2 rounded-lg bg-violet-600 px-3 py-2 text-sm hover:bg-violet-500">{copied ? <Check className="h-4 w-4" /> : <Copy className="h-4 w-4" />}{copied ? 'Copied' : 'Copy'}</button>
      <a href={url} target="_blank" rel="noopener noreferrer" aria-label="Open shared folder" title="Open shared folder" className="flex shrink-0 items-center rounded-lg border border-white/10 px-3 py-2 hover:bg-white/5"><ExternalLink className="h-4 w-4" /></a></div>}
    {status?.active && !url && <button disabled={busy} onClick={() => void update('status')} className="mt-3 text-sm text-violet-300 hover:text-violet-200 disabled:opacity-50">Load share link</button>}
    {error && <p role="alert" className="mt-4 text-sm text-red-300">{error}</p>}
    <div className="mt-5 flex flex-wrap gap-2">
      {!status && !busy && <button onClick={() => void update('status')} className="rounded-lg bg-violet-600 px-4 py-2 text-sm">Retry</button>}
      {status && <button disabled={busy} onClick={() => void update('create')} className="flex items-center gap-2 rounded-lg bg-violet-600 px-4 py-2 text-sm font-semibold hover:bg-violet-500 disabled:opacity-50">{busy && <Loader2 className="h-4 w-4 animate-spin" />}{status.active ? 'Create new link' : 'Create share link'}</button>}
      {status?.active && <button disabled={busy} onClick={() => void update('revoke')} className="rounded-lg border border-red-400/30 px-4 py-2 text-sm text-red-300 hover:bg-red-500/10 disabled:opacity-50">Turn off sharing</button>}
      {!status && busy && <p role="status" className="text-sm text-gray-400">Checking sharing…</p>}
    </div>
    {status?.active && <p className="mt-4 text-xs leading-relaxed text-gray-500">Turning sharing off blocks new access. Already issued image URLs may work for up to one minute. Downloaded copies cannot be recalled.</p>}
  </dialog>;
};
