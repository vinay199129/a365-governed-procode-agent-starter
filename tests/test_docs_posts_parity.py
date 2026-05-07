"""Parity tests between the narrative posts/ tree and the canonical docs/ tree.

posts/*.md are derivative narratives — each one MUST cite a `Canonical doc:`
or `Canonical evidence:` link that points to the underlying docs/*.md page.
If a doc is renamed or moved without the post being updated, the SPA's
"More" panel link breaks silently. These tests catch that drift in CI.

Scope: link-target existence only. We don't compare body content because
posts are intentionally summarised, not 1:1 copies.
"""

import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
POSTS_DIR = REPO_ROOT / "posts"
DOCS_DIR = REPO_ROOT / "docs"

CANONICAL_LINE = re.compile(
    r"Canonical (?:doc|evidence):\s*\[[^\]]+\]\((\.\./docs/[\w/.-]+\.md)\)"
)
RELATIVE_DOC_LINK = re.compile(r"\]\((\.\./docs/[\w/.-]+\.md)\)")


def _all_posts() -> list[Path]:
    return sorted(POSTS_DIR.glob("*.md"))


def test_posts_directory_exists_and_is_populated():
    assert POSTS_DIR.is_dir(), "posts/ directory missing"
    assert _all_posts(), "posts/ is empty — at least one narrative post expected"


def test_every_post_declares_a_canonical_doc():
    """Every published narrative must point readers at the source-of-truth page."""
    missing = [p.name for p in _all_posts() if not CANONICAL_LINE.search(p.read_text(encoding="utf-8"))]
    assert not missing, (
        f"Posts without 'Canonical doc:' or 'Canonical evidence:' link: {missing}. "
        "Every narrative post must link back to the underlying docs/*.md page."
    )


def test_every_canonical_link_resolves_to_a_real_doc():
    """The cited canonical doc must exist on disk, otherwise the link 404s."""
    broken: list[str] = []
    for post in _all_posts():
        text = post.read_text(encoding="utf-8")
        for match in CANONICAL_LINE.finditer(text):
            target = (post.parent / match.group(1)).resolve()
            if not target.is_file():
                broken.append(f"{post.name} -> {match.group(1)}")
    assert not broken, (
        f"Canonical links in posts pointing to missing docs: {broken}. "
        "Either restore the doc or update the post to cite the new location."
    )


def test_every_relative_docs_link_resolves():
    """Defence in depth: any ../docs/...md link in any post must resolve."""
    broken: list[str] = []
    for post in _all_posts():
        text = post.read_text(encoding="utf-8")
        for match in RELATIVE_DOC_LINK.finditer(text):
            target = (post.parent / match.group(1)).resolve()
            if not target.is_file():
                broken.append(f"{post.name} -> {match.group(1)}")
    assert not broken, f"Broken ../docs/*.md links in posts: {broken}"
