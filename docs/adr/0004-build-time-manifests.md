---
section: Architecture Decisions
---
# ADR 0004 — Sidebar manifests are build-time generated and committed

- **Status:** Accepted (May 7, 2026)
- **Context:** Architecture review (May 7, 2026) flagged the committed `*-manifest.js` files as a "generated artefact in git" smell.

## Decision

Keep `assets/js/docs-manifest.js` and `assets/js/posts-manifest.js` as build-time outputs of `scripts/build_manifests.py`, committed to git. Browser loads them via a plain `<script>` tag. Do not move to runtime fetch.

CI gate: `tests/test_doc_links.py` fails when the committed manifest drifts from what the script would emit, so "added a doc but forgot to regen" is a red CI build.

## Why

- **Static hosts can't list directories.** GitHub Pages, Azure Static Web Apps, S3 — none serve a "give me all `.md` files in `docs/`" endpoint. Runtime discovery still needs *some* index, which is exactly what the manifest is. "No build" doesn't eliminate the manifest, it just shifts who writes it.
- **First paint is fast.** Sidebar renders immediately from a `<script>` tag with the manifest pre-baked. Runtime discovery would mean: page loads → fetch index → parse → render sidebar. Guaranteed extra round-trip before the user sees anything.
- **Front-matter parsing in the browser is non-trivial.** YAML in pure JS means shipping `js-yaml` (~30KB) or hand-rolling a parser. The Python script does it for free at build time.
- **CI catches drift.** The pytest drift test means the failure mode is loud, early, and free.
- **Authoring ergonomics are already good.** Add a doc → run `python scripts/build_manifests.py` → commit. Recent rewrite is fully convention-driven (front-matter `section:` first, then leading folder name, then `DEFAULT_SECTION`, then `"Other"`), so the only "human input" is dropping the `.md` file.
- **Manifests are tiny.** ~2KB each. They change only when docs change. Diffs read like a changelog. This is not the "generated files in git" anti-pattern in a meaningful way.

## Rejected alternatives

- **Runtime fetch with `index.json`:** extra round-trip to first paint, extra JS to parse YAML, no SSR/SEO win (already client-rendered per ADR 0002). All cost, no offsetting benefit.
- **No manifest, hand-curated `<nav>` in HTML:** loses the drift gate entirely; sidebar can disagree with the docs tree silently.
- **Pre-commit hook to auto-run the generator:** considered and rejected. Adds installation friction; the pytest drift test already covers the failure mode in CI.

## Triggers to revisit

- The docs tree grows past ~100 files and the generator becomes slow enough to notice.
- We add doc-authoring workflows that don't go through git (e.g., a CMS), making "regenerate on commit" structurally impossible.

Neither is on any plausible roadmap for this repo.
