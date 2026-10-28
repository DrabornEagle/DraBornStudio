import React from 'react';
import { createRoot } from 'react-dom/client';
import '../../src/styles/index.css';

// Synthetic and self-contained. No account, files, provider keys or paid calls.
window.__BANANA_STUDIO_CONFIG__ = { mode: 'local', userId: '00000000-0000-0000-0000-000000000001', sessionId: '00000000-0000-0000-0000-000000000002' };
const { DetailImage } = await import('../../src/components/GalleryDetailImage');
const src = 'data:image/svg+xml,' + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="800"><rect width="1200" height="800" fill="#182131"/><rect x="20" y="20" width="1160" height="760" rx="24" fill="none" stroke="#a78bfa" stroke-width="10"/><circle cx="600" cy="400" r="180" fill="#84cc16"/><text x="600" y="405" font-size="32" font-family="sans-serif" text-anchor="middle" fill="#0d1117">Synthetic image · 1200 × 800</text><path d="M0 400H1200M600 0V800" stroke="#fff" stroke-opacity=".2" stroke-width="2"/></svg>');
createRoot(document.getElementById('root')!).render(<main className="flex h-screen flex-col gap-3 bg-[#0d1117] p-4 text-white">
  <h1 className="text-lg font-semibold">Gallery image inspection</h1>
  <label className="text-sm text-gray-300">Typing here keeps + and 0 as text<input aria-label="Typing test" className="ml-3 rounded border border-white/20 bg-gray-900 p-2" /></label>
  <div className="min-h-0 flex-1"><DetailImage src={src} alt="Synthetic framing test" className="h-auto w-auto max-h-full max-w-full object-contain" /></div>
</main>);
