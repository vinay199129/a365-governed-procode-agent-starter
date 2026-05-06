/**
 * Docs viewer — reads ?doc=<slug>, renders markdown from DOCS_MANIFEST.
 */
(function () {
  const manifest = window.DOCS_MANIFEST || [];
  const params = new URLSearchParams(window.location.search);
  const requestedSlug = params.get('doc') || 'quickstart';

  // Build the sidebar.
  const sidebar = document.getElementById('sidebar');
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

  // Find and render the requested doc.
  const entry = flat.find((i) => i.slug === requestedSlug) || flat[0];
  const target = document.getElementById('doc');
  const editLink = document.getElementById('edit-link');

  if (!entry) {
    target.innerHTML = '<p>No documentation found.</p>';
    return;
  }

  document.title = `${entry.title} · A365 Starter`;

  fetch(entry.path)
    .then((r) => {
      if (!r.ok) throw new Error(`HTTP ${r.status} fetching ${entry.path}`);
      return r.text();
    })
    .then((md) => {
      target.innerHTML = window.renderMarkdown(window.stripFrontMatter(md), 'docs');
      window.highlightAll();
      editLink.innerHTML = `<a href="https://github.com/vinay199129/a365-governed-procode-agent-starter/edit/master/${entry.path}" target="_blank" rel="noopener">Edit this page on GitHub →</a>`;
    })
    .catch((err) => {
      target.innerHTML = `<h1>Could not load ${entry.title}</h1><p>${err.message}</p>`;
    });
})();
