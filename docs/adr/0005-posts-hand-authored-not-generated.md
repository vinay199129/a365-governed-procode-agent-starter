---
section: Architecture Decisions
---
# ADR 0005 — Posts are hand-authored narratives, not generated from docs

- **Status:** Accepted (May 7, 2026)
- **Context:** [Architecture review](../../.copilot-tracking/research/subagents/2026-05-07/) flagged the dual content tree (`docs/` + `posts/`) as a maintenance risk and asked whether `posts/` should be generated.

## Decision

Keep `posts/*.md` as hand-authored narrative summaries, distinct from `docs/*.md` reference content. Enforce the relationship via `tests/test_docs_posts_parity.py` (every post must declare `Canonical doc:` or `Canonical evidence:`, link must resolve). Do not auto-generate posts from docs.

## Editorial contract

The two trees serve two audiences and two modes of explanation:

| Tree     | Voice                              | Reader question it answers       |
|----------|------------------------------------|----------------------------------|
| `docs/`  | Reference, dense, complete         | "What does this do?"             |
| `posts/` | Narrative, framing, opinion        | "Why should I care?"             |

**Rule of thumb:** if a post is going to be a slightly-shorter version of its canonical doc, don't write it. Posts exist to add framing, opinion, or "why should you care" context that the reference doc deliberately omits.

## Why

- **Tone genuinely differs.** Generation can't produce narrative voice from reference content without an LLM in the loop, and even then the result reads like a summary, not a story.
- **The repo's content shape doesn't justify generator infrastructure.** 7 posts, 9 docs. Building a pipeline (front-matter conventions, excerpt extraction, build step, drift check) costs more than the current 2-minute manual sync — and we'd still need a human pass to make output read like prose.
- **The parity test is enough governance.** Catches the worst failure mode (renamed/deleted doc, broken link). Content drift within an existing post is a milder bug that PR review can catch.
- **Real editorial value exists.** `posts/what-is-agent-365.md` tells a story (why Agent 365 exists, what problem it solves) that cannot be derived from `docs/learning-guide.md` because the canonical doc is structured as a reference.

## Rejected alternatives

- **Auto-generate posts from docs front-matter + excerpt windows:** infrastructure cost is concrete and immediate; drift-prevention benefit is small at this scale and partly already covered by the parity test.
- **Delete `posts/` entirely:** `posts/what-is-agent-365.md` and the two evidence narratives have unique editorial value. Not redundant.
- **Codify "posts must add narrative" as a test:** can't reliably automate "this prose has a voice." Reviewer judgment call. Documented in this ADR; PR review enforces.

## Triggers to revisit

- `posts/` grows past ~25 entries.
- We add a publishing cadence (weekly post, monthly newsletter) that creates real velocity pressure.
- We discover the audience for `posts/` is large enough that content-drift bugs cause user reports.
