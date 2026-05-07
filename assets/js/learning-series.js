/**
 * Learning Series viewer — list posts, render selected post.
 *
 * Behavior mirrors docs.js: explicit 404 for unknown slugs, anchor scroll
 * after async render, dynamic <title> + meta description for sharing.
 */
(function () {
  const posts = window.POSTS_MANIFEST || [];
  const list = document.getElementById('post-list');
  const target = document.getElementById('post-content');

  if (posts.length === 0) return;

  const params = new URLSearchParams(window.location.search);
  const requestedSlug = params.get('post') || posts[0].slug;

  const ul = document.createElement('ul');
  posts.forEach((p) => {
    const li = document.createElement('li');
    const a = document.createElement('a');
    a.href = `learning-series.html?post=${encodeURIComponent(p.slug)}`;
    if (p.slug === requestedSlug) a.classList.add('active');
    a.innerHTML = `<span class="post-date">${p.date}</span><span class="post-title">${p.title}</span>`;
    li.appendChild(a);
    ul.appendChild(li);
  });
  list.appendChild(ul);

  const entry = posts.find((p) => p.slug === requestedSlug);

  if (!entry) {
    document.title = 'Post not found · A365 Starter';
    const safe = requestedSlug.replace(/[<>&"]/g, (c) => ({
      '<': '&lt;', '>': '&gt;', '&': '&amp;', '"': '&quot;',
    }[c]));
    target.innerHTML =
      `<h1>Post not found</h1>` +
      `<p>No post with slug <code>${safe}</code>. ` +
      `Pick one from the list, or start with <a href="learning-series.html?post=${encodeURIComponent(posts[0].slug)}">${posts[0].title}</a>.</p>`;
    return;
  }

  document.title = `${entry.title} · A365 Starter`;
  setMetaDescription(`${entry.title} — A365 Governed Pro-Code Agent Starter learning series.`);

  fetch(entry.path)
    .then((r) => {
      if (!r.ok) throw new Error(`HTTP ${r.status} fetching ${entry.path}`);
      return r.text();
    })
    .then((md) => {
      target.innerHTML = window.renderMarkdown(window.stripFrontMatter(md), 'posts', entry.slug);
      window.highlightAll();
      scrollToHashAfterRender();
    })
    .catch((err) => {
      // Build the error panel via DOM APIs so err.message can never inject HTML.
      const h1 = document.createElement('h1');
      h1.textContent = 'Could not load post';
      const p = document.createElement('p');
      p.textContent = err.message;
      target.replaceChildren(h1, p);
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

  function scrollToHashAfterRender() {
    if (!window.location.hash) return;
    const id = decodeURIComponent(window.location.hash.slice(1));
    requestAnimationFrame(() => {
      const el = document.getElementById(id);
      if (el) el.scrollIntoView({ behavior: 'auto', block: 'start' });
    });
  }
})();
