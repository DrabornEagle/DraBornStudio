import './styles/index.css';
import { initializeWorkspaceApi, workspaceFetch } from './services/workspaceApi.mjs';
import './styles/web.css';
import { browserIdentity } from './services/browserWorkspace.mjs';
import React from 'react';
import ReactDOM from 'react-dom/client';
import { validateWorkspaceConfig } from './lib/config/runtimeConfig';

const rootElement = document.getElementById('root');
if (!rootElement) {
  throw new Error("Could not find root element to mount to");
}

const root = ReactDOM.createRoot(rootElement);
root.render(<div role="status" style={{ color: '#d1d5db', padding: 48 }}>Opening Banana-edits…</div>);
const start = async () => {
  try {
    const browserOnly = await initializeWorkspaceApi();
    const response = browserOnly ? null : await workspaceFetch('/api/banana-edits/workspace-config', { cache: 'no-store', credentials: 'same-origin', signal: AbortSignal.timeout(8000) }).catch(() => null);
    const config = response?.ok && response.headers.get('content-type')?.includes('application/json') ? await response.json() : { mode: 'browser' };
    window.__BANANA_STUDIO_CONFIG__ = Object.freeze(validateWorkspaceConfig(config.mode === 'browser' ? browserIdentity() : config));
    const { default: App } = await import('./App');
    root.render(<React.StrictMode><App /></React.StrictMode>);
  } catch {
    root.render(<main style={{ maxWidth: 560, margin: '12vh auto', padding: 32, color: '#e5e7eb', fontFamily: 'system-ui' }}>
      <h1>Welcome to Banana-edits</h1>
      <p>This deployment needs its own workspace configuration. Follow the self-hosting guide to connect your Supabase project and server API keys.</p>
      <p>Provider keys belong on your server. Never paste them into a browser console or a public configuration field.</p>
      <a href="https://github.com/DrabornEagle/DraBornStudio/blob/main/Banana-edits/WEB_DEPLOYMENT.md" style={{ color: '#b5e92a' }}>Open the setup guide</a>
    </main>);
  }
};
void start();
