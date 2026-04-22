/**
 * Learning Series viewer — list posts in a sidebar, render selected post in main area.
 */
(function () {
  const posts = window.POSTS_MANIFEST || [];
  if (posts.length === 0) return;

  const params = new URLSearchParams(window.location.search);
  const requestedSlug = params.get('post') || posts[0].slug;

  // Build post list.
  const list = document.getElementById('post-list');
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

  // Render selected post.
  const entry = posts.find((p) => p.slug === requestedSlug) || posts[0];
  const target = document.getElementById('post-content');

  document.title = `${entry.title} · A365 Starter`;

  fetch(entry.path)
    .then((r) => {
      if (!r.ok) throw new Error(`HTTP ${r.status} fetching ${entry.path}`);
      return r.text();
    })
    .then((md) => {
      target.innerHTML = marked.parse(window.stripFrontMatter(md));
      window.highlightAll();
    })
    .catch((err) => {
      target.innerHTML = `<h1>Could not load post</h1><p>${err.message}</p>`;
    });
})();
