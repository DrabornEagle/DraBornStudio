export function mountCoconutShell({importFiles, openLibrary, setGroup, input}) {
  const all = selector => [...document.querySelectorAll(selector)];
  const one = selector => document.querySelector(selector);
  const motion = () => window.matchMedia?.('(prefers-reduced-motion: reduce)').matches ? 'instant' : 'smooth';
  const scrollWorkspace = () => one('#workspace').scrollIntoView({behavior: motion(), block: 'start'});
  for (const button of all('[data-upload]')) button.onclick = () => input.click();
  for (const button of all('[data-library]')) button.onclick = openLibrary;
  for (const button of all('[data-coconut-group]')) button.onclick = () => {
    setGroup(button.dataset.coconutGroup); closeMenu(); scrollWorkspace();
  };
  const zone = one('#coconut-dropzone');
  zone.addEventListener('dragover', event => {
    if (!event.dataTransfer.types.includes('Files')) return;
    event.preventDefault(); zone.classList.add('is-dragging');
  });
  zone.addEventListener('dragleave', event => { if (!zone.contains(event.relatedTarget)) zone.classList.remove('is-dragging'); });
  zone.addEventListener('drop', async event => {
    event.preventDefault(); zone.classList.remove('is-dragging');
    await importFiles([...event.dataTransfer.files]); scrollWorkspace();
  });
  const count = one('#library-count');
  const syncCount = () => all('.shell-library-count').forEach(node => { node.textContent = count.textContent; });
  new MutationObserver(syncCount).observe(count, {childList: true, characterData: true, subtree: true}); syncCount();
  const search = one('#tool-search');
  search.oninput = () => one('.feature-filters [aria-pressed="true"]')?.click();
  const menu = one('.menu-toggle'), shade = one('.sidebar-shade'), sidebar = one('.coconut-sidebar');
  function closeMenu() {
    document.body.classList.remove('sidebar-open'); menu.setAttribute('aria-expanded', 'false'); shade.hidden = true;
  }
  menu.onclick = () => {
    if (menu.getAttribute('aria-expanded') === 'true') { closeMenu(); return; }
    document.body.classList.add('sidebar-open'); menu.setAttribute('aria-expanded', 'true'); shade.hidden = false;
    sidebar.querySelector('a')?.focus();
  };
  shade.onclick = closeMenu;
  for (const link of all('.sidebar-nav a')) link.addEventListener('click', closeMenu);
  const help = one('#coconut-help');
  for (const button of all('.help-trigger')) button.onclick = () => { closeMenu(); help.showModal(); };
  help.addEventListener('click', event => { if (event.target === help) { const r=help.getBoundingClientRect(); if(event.clientX<r.left||event.clientX>r.right||event.clientY<r.top||event.clientY>r.bottom) help.close(); } });
  document.addEventListener('keydown', event => {
    if (event.key === 'Escape' && menu.getAttribute('aria-expanded') === 'true') { closeMenu(); menu.focus(); }
    if (event.key === '/' && !event.target.matches('input, textarea, [contenteditable="true"]') && !document.querySelector('dialog[open]')) {
      event.preventDefault(); search.focus(); search.scrollIntoView({behavior: motion(), block: 'center'});
    }
    if (event.key === 'Tab' && menu.getAttribute('aria-expanded') === 'true') {
      const focusable = [...sidebar.querySelectorAll('a,button')], first = focusable[0], last = focusable.at(-1);
      if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
      else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
    }
  });
  one('#demo-upload').textContent = '＋ Dosya ekle';
  document.dispatchEvent(new Event('coconut-ready'));
}
