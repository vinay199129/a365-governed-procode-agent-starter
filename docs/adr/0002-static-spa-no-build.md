---
section: Architecture Decisions
---
# ADR 0002 — Static SPA, no build pipeline

- **Status:** Accepted (May 7, 2026)
- **Context:** [Architecture review](../../.copilot-tracking/research/subagents/2026-05-07/) flagged the no-build SPA as a potential long-term liability.

## Decision

Keep the marketing/docs site as a static SPA with zero build step. Two CDN-pinned-with-SRI dependencies (`marked@12.0.2`, `prismjs@1.29.0`). Add JSDoc-driven type checking via `assets/jsconfig.json` (`checkJs: true`, `strict: true`). Do not migrate to Vite, Astro, or any SSG.

## Why

- **Zero supply-chain surface in the repo.** No `package.json`, no `node_modules`, no Dependabot noise. The only third-party JS is two CDN-pinned files.
- **Zero build = zero "works on my machine."** The artefact in git is the artefact in production. Edit JS → refresh browser → see result.
- **Hosts anywhere.** GitHub Pages, Azure Static Web Apps, S3 bucket, USB stick.
- **Fits the audience.** Docs site for an OSS sample. Reader bandwidth/CPU is not the bottleneck. Marked parses 30KB of markdown in milliseconds.
- **Already governed.** SRI hashes prevent CDN tampering. The pytest drift test (see ADR 0004) catches manifest staleness.

## Type-safety guardrail

`assets/jsconfig.json` enables `tsc --checkJs --strict` from JSDoc annotations alone. Catches the renderer-bug class we just fought through (empty-string `slugify`, off-by-one `stripFrontMatter`) at edit time in VS Code, with no `.ts` files and no build artefact change. `noImplicitAny` is off — annotate what matters, leave the rest tolerant.

## Rejected alternatives

- **Migrate to Astro / 11ty / Vite now:** premature. 3 JS files totalling ~30KB. Infrastructure cost (build server, npm supply chain, Node version pinning) buys benefits that are speculative at current scale.
- **Stay completely as-is, no JSDoc:** the type-safety gap is real and proven (we just fixed bugs `tsc --checkJs` would catch). Cheapest non-trivial improvement available.

## Triggers to revisit

Either of these reopens the ADR and considers a static site generator:

- The site needs SEO (e.g., we want this to rank for "Agent 365 starter").
- The JS surface crosses ~1000 lines or we add interactive components beyond the current renderer.
