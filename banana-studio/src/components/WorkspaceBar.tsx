import React, { useEffect, useRef, useState } from 'react';
import { KeyRound, Settings, X } from 'lucide-react';
import { TextModelSettings } from './TextModelSettings';
import { ProviderRoutingSettings } from './ProviderRoutingSettings';
import { isBrowserWorkspace, isLocalWorkspace } from '../lib/config/runtimeConfig';
import type { UserProfile } from '../types';
import { importBrowserMedia } from '../services/browserImport';
import { postNativeAction } from '../../desktop/shared/nativeBridge';

export function WorkspaceBar({ profile, onOpenAdmin, onSignOut }: { profile: UserProfile | null; onOpenAdmin: () => void; onSignOut: () => Promise<void> }) {
  const local = isLocalWorkspace();
  const browser = isBrowserWorkspace();
  const [setupOpen, setSetupOpen] = useState(false);
  const [importing, setImporting] = useState(false);
  const [importError, setImportError] = useState('');
  const [settingsOpen, setSettingsOpen] = useState(false);
  const dialog = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const element = dialog.current;
    if (settingsOpen && element && !element.open) element.showModal();
    if (!settingsOpen && element?.open) element.close();
  }, [settingsOpen]);
  return <>
    <header className="flex shrink-0 items-center justify-between gap-4 border-b border-white/[0.07] bg-[#0d1117] px-5 py-2.5 text-xs">
      <div><span className="font-semibold text-white">Banana-edits</span><span className="ml-3 text-gray-500">{browser ? 'Web · Bu tarayıcı' : local ? 'Local workspace · This computer' : profile?.display_name || 'Your workspace'}</span></div>
      <div className="flex items-center gap-2">
        <button type="button" onClick={() => setSettingsOpen(true)} className="flex items-center gap-2 rounded-lg px-3 py-2 text-gray-300 hover:bg-white/5"><Settings size={14} />AI settings</button>
        {!local && profile?.role === 'admin' && <button type="button" onClick={onOpenAdmin} className="rounded-lg px-3 py-2 text-violet-300 hover:bg-white/5">Workspace admin</button>}
        {!local && <button type="button" onClick={() => void onSignOut()} className="rounded-lg px-3 py-2 text-gray-400 hover:bg-white/5">Sign out</button>}
        {browser && <label className="browser-import">{importing ? 'İçe aktarılıyor…' : 'Medya ekle'}<input type="file" multiple accept="image/png,image/jpeg,image/webp,image/gif,video/mp4,video/webm,video/quicktime" disabled={importing} onChange={async event => { const files = Array.from(event.target.files || []) as File[]; event.target.value = ''; setImporting(true); setImportError(''); try { await importBrowserMedia(files); window.dispatchEvent(new Event('banana-media-imported')); } catch (error: any) { setImportError(error.message); } finally { setImporting(false); } }} /></label>}
        {local && <button type="button" onClick={() => browser ? setSetupOpen(true) : postNativeAction('keys')} className="flex items-center gap-2 rounded-lg border border-violet-400/20 bg-violet-500/10 px-3 py-2 text-violet-300 hover:bg-violet-500/20"><KeyRound size={14} />{browser ? 'Bağlantı bilgisi' : 'Provider keys'}</button>}
      </div>
    </header>
    {browser && <div className="browser-banner">Galeri bu tarayıcıda saklanır. AI üretimi, Enhance, Brainstorm ve video oluşturma için sunucu ve sağlayıcı anahtarı kurulmalıdır. {importError && <span role="alert">{importError}</span>}</div>}
    {setupOpen && <div role="dialog" aria-modal="true" aria-label="Banana-edits bağlantısı" className="fixed inset-0 z-[200] flex items-center justify-center bg-black/80 p-5"><section className="max-w-lg rounded-2xl border border-white/20 bg-[#161b22] p-6 text-sm text-gray-300"><button className="float-right" onClick={() => setSetupOpen(false)} aria-label="Bağlantı bilgisini kapat">✕</button><h2 className="mb-4 text-xl text-white">Banana-edits Web</h2><p className="mb-3">Görsellerini ve videolarını ekleyebilir, klasörleyebilir, favorilere alabilir, karşılaştırabilir ve indirebilirsin. İçerikler bu tarayıcıda tutulur; cihazlar arasında eşitlenmez.</p><p className="mb-4">AI araçlarının çalışması için site sahibi özel veritabanını, kimlik doğrulamayı ve AI sağlayıcı anahtarlarını sunucuda kurmalıdır. Anahtarlar tarayıcıda saklanmaz. Üretim, sağlayıcının API ücretine tabidir.</p><a className="text-lime-300" href="WEB_SETUP.md" target="_blank" rel="noreferrer">Kurulum ve özellik durumu ↗</a></section></div>}
    <dialog ref={dialog} onCancel={event => { event.preventDefault(); setSettingsOpen(false); }} onClick={event => { if (event.target === event.currentTarget) setSettingsOpen(false); }} aria-labelledby="local-ai-settings" className="max-h-[85vh] w-[calc(100%-3rem)] max-w-xl overflow-y-auto rounded-2xl border border-white/10 bg-[#161b22] p-0 text-white backdrop:bg-black/75">
      <section className="p-6">
        <div className="mb-6 flex items-center justify-between"><h2 id="local-ai-settings" className="text-lg font-semibold">AI settings</h2><button autoFocus type="button" aria-label="Close AI settings" onClick={() => setSettingsOpen(false)}><X size={20} /></button></div>
        {settingsOpen && <><TextModelSettings /><ProviderRoutingSettings /></>}
      </section>
    </dialog>
  </>;
}
