/**
 * Shared site helpers: configure marked + Prism + render markdown with
 * mode-aware link rewriting so internal .md links route through the
 * single-page docs / learning-series viewers instead of 404'ing.
 *
 * Called from docs.js (mode='docs') and learning-series.js (mode='posts').
 */
(function () {
  if (typeof marked === 'undefined') return;

  const REPO_BASE =
    'https://github.com/vinay199129/a365-governed-procode-agent-starter/blob/master';

  /**
   * Rewrite a relative href found inside a rendered markdown file.
   *
   * Rules (docs mode — file lives under docs/):
   *   foo.md           -> docs.html?doc=foo
   *   evidence/foo.md  -> docs.html?doc=evidence/foo
   *   ../README.md     -> GitHub blob URL (out of docs/)
   *   ../agent.py      -> GitHub blob URL
   *   #anchor          -> unchanged (in-page)
   *   https://...      -> unchanged
   *
   * Rules (posts mode — file lives under posts/):
   *   foo.md           -> learning-series.html?post=foo
   *   ../docs/foo.md   -> docs.html?doc=foo
   *   ../README.md     -> GitHub blob URL
   *   ../agent.py      -> GitHub blob URL
   */
  function rewriteHref(href, mode) {
    if (!href) return href;
    if (/^(https?:|mailto:|#)/i.test(href)) return href;

    const hashIndex = href.indexOf('#');
    const pathOnly = hashIndex === -1 ? href : href.slice(0, hashIndex);
    const hash = hashIndex === -1 ? '' : href.slice(hashIndex);

    if (mode === 'docs') {
      if (pathOnly.startsWith('../')) {
        return `${REPO_BASE}/${pathOnly.slice(3)}${hash}`;
      }
      if (pathOnly.endsWith('.md')) {
        const slug = pathOnly.replace(/\.md$/, '');
        return `docs.html?doc=${encodeURIComponent(slug)}${hash}`;
      }
      return `docs/${pathOnly}${hash}`;
    }

    if (mode === 'posts') {
      if (pathOnly.startsWith('../docs/')) {
        const slug = pathOnly.replace(/^\.\.\/docs\//, '').replace(/\.md$/, '');
        return `docs.html?doc=${encodeURIComponent(slug)}${hash}`;
      }
      if (pathOnly.startsWith('../')) {
        return `${REPO_BASE}/${pathOnly.slice(3)}${hash}`;
      }
      if (pathOnly.endsWith('.md')) {
        const slug = pathOnly.replace(/\.md$/, '');
        return `learning-series.html?post=${encodeURIComponent(slug)}${hash}`;
      }
      return `posts/${pathOnly}${hash}`;
    }

    return href;
  }

  // Exposed for unit testing.
  window.__rewriteHref = rewriteHref;

  function buildRenderer(mode) {
    const renderer = new marked.Renderer();

    // Code: handle both v4-style (code, infostring) and v12 token style.
    renderer.code = function (code, infostring) {
      const lang = (infostring || (code && code.lang) || '').trim().split(/\s+/)[0];
      const langClass = lang ? ` class="language-${lang}"` : '';
      const codeStr = typeof code === 'string' ? code : (code && code.text) || '';
      const escaped = codeStr
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;');
      return `<pre${langClass}><code${langClass}>${escaped}</code></pre>`;
    };

    // Link: marked v12 passes a token; older versions pass (href, title, text).
    renderer.link = function (hrefOrToken, title, text) {
      let href, linkTitle, linkText;
      if (hrefOrToken && typeof hrefOrToken === 'object') {
        href = hrefOrToken.href;
        linkTitle = hrefOrToken.title;
        linkText = this.parser
          ? this.parser.parseInline(hrefOrToken.tokens)
          : hrefOrToken.text;
      } else {
        href = hrefOrToken;
        linkTitle = title;
        linkText = text;
      }

      const rewritten = rewriteHref(href, mode);
      const titleAttr = linkTitle ? ` title="${linkTitle}"` : '';
      const isExternal = /^https?:/i.test(rewritten);
      const extAttrs = isExternal ? ' target="_blank" rel="noopener"' : '';
      return `<a href="${rewritten}"${titleAttr}${extAttrs}>${linkText}</a>`;
    };

    return renderer;
  }

  window.renderMarkdown = function (md, mode) {
    return marked.parse(md, {
      renderer: buildRenderer(mode),
      gfm: true,
      breaks: false,
    });
  };

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

  window.highlightAll = function () {
    if (typeof Prism !== 'undefined') {
      Prism.highlightAll();
    }
  };
})();
