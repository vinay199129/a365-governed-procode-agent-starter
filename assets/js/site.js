/**
 * Shared site helpers: configure marked + Prism.
 * Called from docs.js and learning-series.js.
 */
(function () {
  if (typeof marked === 'undefined') return;

  // Use a custom renderer to attach Prism language classes so syntax
  // highlighting works without the optional `marked-highlight` package.
  const renderer = new marked.Renderer();
  const origCode = renderer.code.bind(renderer);
  renderer.code = function (code, infostring) {
    const lang = (infostring || '').trim().split(/\s+/)[0];
    const langClass = lang ? ` class="language-${lang}"` : '';
    const codeStr = typeof code === 'string' ? code : (code && code.text) || '';
    const escaped = codeStr
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;');
    return `<pre${langClass}><code${langClass}>${escaped}</code></pre>`;
  };

  marked.setOptions({
    renderer,
    gfm: true,
    breaks: false,
    headerIds: true,
    mangle: false,
  });

  /**
   * Strip a leading YAML front-matter block (between --- lines) if present.
   * Used so blog posts authored with front matter render cleanly.
   */
  window.stripFrontMatter = function (md) {
    if (md.startsWith('---')) {
      const end = md.indexOf('\n---', 3);
      if (end !== -1) {
        const after = md.indexOf('\n', end + 4);
        return md.slice(after + 1);
      }
    }
    return md;
  };

  /**
   * Re-run Prism over the rendered article so code blocks get highlighted.
   */
  window.highlightAll = function () {
    if (typeof Prism !== 'undefined') {
      Prism.highlightAll();
    }
  };
})();
