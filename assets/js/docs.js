/**
 * Docs viewer — reads ?doc=<slug>, renders markdown from DOCS_MANIFEST.
 *
 * Behavior:
 *  - Unknown slug → explicit 404 panel (does not silently fall back).
 *  - location.hash → scroll to matching heading after async render.
 *  - Per-doc <title> + <meta name="description"> for shareable URLs.
 *  - "Edit on GitHub" link uses window.A365_REPO_EDIT_BASE from site.js.
 */
(function () {
  const manifest = window.DOCS_MANIFEST || [];
  const params = new URLSearchParams(window.location.search);
  const requestedSlug = params.get('doc') || 'quickstart';

  const sidebar = document.getElementById('sidebar');
  const target = document.getElementById('doc');
  const editLink = document.getElementById('edit-link');

  const flat = [];
  manifest.forEach((section) => {
    const h = document.createElement('h4');
    h.textContent = section.section;
    sidebar.appendChild(h);
    const ul = document.createElement('ul');
    section.items.forEach((item) => {
      flat.push(item);
      const li = document.createElement('li');
      const a = document.createElement('a');
      a.href = `docs.html?doc=${encodeURIComponent(item.slug)}`;
      a.textContent = item.title;
      if (item.slug === requestedSlug) a.classList.add('active');
      li.appendChild(a);
      ul.appendChild(li);
    });
    sidebar.appendChild(ul);
  });

  const entry = flat.find((i) => i.slug === requestedSlug);

  if (!entry) {
    document.title = 'Not found · A365 Starter';
    const safe = requestedSlug.replace(/[<>&"]/g, (c) => ({
      '<': '&lt;', '>': '&gt;', '&': '&amp;', '"': '&quot;',
    }[c]));
    target.innerHTML =
      `<h1>Doc not found</h1>` +
      `<p>No doc with slug <code>${safe}</code>. ` +
      `Pick one from the sidebar, or jump to <a href="docs.html?doc=quickstart">Quickstart</a>.</p>`;
    return;
  }

  document.title = `${entry.title} · A365 Starter`;
  setMetaDescription(`${entry.title} — A365 Governed Pro-Code Agent Starter docs.`);

  fetch(entry.path)
    .then((r) => {
      if (!r.ok) throw new Error(`HTTP ${r.status} fetching ${entry.path}`);
      return r.text();
    })
    .then((md) => {
      target.innerHTML = window.renderMarkdown(window.stripFrontMatter(md), 'docs');
      window.highlightAll();
      const editBase = window.A365_REPO_EDIT_BASE || 'https://github.com/vinay199129/a365-governed-procode-agent-starter/edit/master';
      editLink.innerHTML = `<a href="${editBase}/${entry.path}" target="_blank" rel="noopener">Edit this page on GitHub →</a>`;
      scrollToHashAfterRender();
    })
    .catch((err) => {
      target.innerHTML = `<h1>Could not load ${entry.title}</h1><p>${err.message}</p>`;
    });

  function setMetaDescription(text) {
    let meta = document.querySelector('meta[name="description"]');
    if (!meta) {
      meta = document.createElement('meta');
      meta.setAttribute('name', 'description');
      document.head.appendChild(meta);
    }
    meta.setAttribute('content', text);
  }

  // Content arrives async (after DOMContentLoaded), so the browser's native
  // hash scroll has already failed by the time the heading exists.
  function scrollToHashAfterRender() {
    if (!window.location.hash) return;
    const id = decodeURIComponent(window.location.hash.slice(1));
    // marked emits slug-based IDs on headings; give the DOM one frame to settle.
    requestAnimationFrame(() => {
      const el = document.getElementById(id);
      if (el) el.scrollIntoView({ behavior: 'auto', block: 'start' });
    });
  }
})();
