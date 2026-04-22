# Website

This folder is the [Docusaurus](https://docusaurus.io) site that powers
<https://vinay199129.github.io/a365-governed-procode-agent-starter/>.

It is **separate from the application code** and only contains site
configuration, theming, and the blog. Documentation content lives in
[`../docs/`](../docs/) — Docusaurus reads from there directly so the
docs and the site never drift.

## Local preview

```pwsh
# Requires Node.js 18+
cd website
npm install
npm start
# Opens http://localhost:3000/a365-governed-procode-agent-starter/
```

## Production build

```pwsh
cd website
npm install
npm run build
# Output lands in website/build/
```

## Deployment

The repository ships with `.github/workflows/pages.yml` that builds this
folder and publishes to GitHub Pages on every push to `main`. To enable:

1. Repo **Settings → Pages**
2. Source: **GitHub Actions**

The published site lives at the URL configured in
[`docusaurus.config.js`](docusaurus.config.js) (`url` + `baseUrl`).

## Layout

| Path | Purpose |
| --- | --- |
| `docusaurus.config.js` | Site config — title, navbar, footer, theme |
| `sidebars.js` | Sidebar grouping for the docs (sourced from `../docs/`) |
| `src/pages/index.js` | Custom landing page (hero + cards + collections) |
| `src/css/custom.css` | Brand colors and typography |
| `blog/` | Learning Series posts (Docusaurus blog format) |
| `static/img/` | Logos and images |

## Adding a learning-series post

Drop a Markdown file in [`blog/`](blog/) named
`YYYY-MM-DD-short-slug.md` with Docusaurus front matter:

```md
---
slug: my-post-slug
title: My Post Title
authors: starter-team
tags: [a365, concepts]
---

Post body here. End with a "Go deeper" link to the canonical doc in
`../docs/`.
```

Authors are defined in [`blog/authors.yml`](blog/authors.yml).
