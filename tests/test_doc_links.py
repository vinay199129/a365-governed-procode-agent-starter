"""Link-checker for the docs/ and posts/ markdown trees.

Catches broken internal references before they 404 in the website viewer.
External http(s) URLs are validated for syntax only, not reachability.

Rules tested:
  - [x](foo.md) under docs/ must resolve to an existing docs/<foo>.md AND
    appear as a slug in assets/js/docs-manifest.js
  - [x](evidence/foo.md) under docs/ must resolve to docs/evidence/<foo>.md
  - [x](../something) under docs/ must resolve to a real file at the repo root
  - [x](foo.md) under posts/ must resolve to posts/<foo>.md AND appear in
    assets/js/posts-manifest.js
  - [x](../docs/foo.md) under posts/ must resolve to docs/<foo>.md
"""

import re
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent
DOCS_DIR = REPO_ROOT / "docs"
POSTS_DIR = REPO_ROOT / "posts"
DOCS_MANIFEST = REPO_ROOT / "assets" / "js" / "docs-manifest.js"
POSTS_MANIFEST = REPO_ROOT / "assets" / "js" / "posts-manifest.js"

# Markdown link: [text](href) — captures href only, ignoring images ![]()
LINK_RE = re.compile(r"(?<!!)\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")


def _read_manifest_slugs(manifest_path: Path, key: str) -> set[str]:
    """Pull slug values out of a JS manifest. Handles both legacy single-quoted
    (`slug: 'foo'`) and JSON-style double-quoted (`"slug": "foo"`) formats."""
    text = manifest_path.read_text(encoding="utf-8")
    return set(re.findall(rf"['\"]?{key}['\"]?\s*:\s*['\"]([^'\"]+)['\"]", text))


def _strip_anchor(href: str) -> str:
    return href.split("#", 1)[0]


def _iter_links(md_path: Path):
    text = md_path.read_text(encoding="utf-8")
    # Skip fenced code blocks so example links aren't checked.
    cleaned = re.sub(r"```.*?```", "", text, flags=re.DOTALL)
    for href in LINK_RE.findall(cleaned):
        yield href


@pytest.fixture(scope="module")
def docs_slugs() -> set[str]:
    return _read_manifest_slugs(DOCS_MANIFEST, "slug")


@pytest.fixture(scope="module")
def posts_slugs() -> set[str]:
    return _read_manifest_slugs(POSTS_MANIFEST, "slug")


def _check_docs_link(href: str, source: Path, docs_slugs: set[str]) -> str | None:
    """Return an error message if the link is broken, else None."""
    pathonly = _strip_anchor(href)
    if not pathonly:
        return None
    if pathonly.startswith(("http://", "https://", "mailto:")):
        return None

    # Hardcoded website-style URLs (used by posts mainly, but allow in docs too).
    if pathonly.startswith("docs.html?doc="):
        slug = pathonly[len("docs.html?doc="):]
        if slug not in docs_slugs:
            return f"docs.html link to unknown slug: {slug}"
        return None
    if pathonly.startswith("learning-series.html"):
        return None  # validated separately by posts checker

    if pathonly.startswith("../"):
        # Relative to the source file's directory, NOT the repo root.
        target = (source.parent / pathonly).resolve()
        if not target.exists():
            return f"missing file at {target.relative_to(REPO_ROOT) if REPO_ROOT in target.parents else target}"
        return None

    if pathonly.endswith(".md"):
        # Relative to the source's directory, then validated as a docs slug if under docs/
        target = (source.parent / pathonly).resolve()
        if not target.exists():
            return f"missing doc file: {pathonly} (resolved to {target})"
        if DOCS_DIR in target.parents or target.parent == DOCS_DIR:
            slug = str(target.relative_to(DOCS_DIR).with_suffix("")).replace("\\", "/")
            if slug not in docs_slugs:
                return f"slug not in docs-manifest.js: {slug}"
        return None

    target = (source.parent / pathonly).resolve()
    if not target.exists():
        return f"missing relative file: {pathonly}"
    return None


def _check_posts_link(href: str, source: Path, posts_slugs: set[str], docs_slugs: set[str]) -> str | None:
    pathonly = _strip_anchor(href)
    if not pathonly:
        return None
    if pathonly.startswith(("http://", "https://", "mailto:")):
        return None

    # Hardcoded website-style URLs.
    if pathonly.startswith("docs.html?doc="):
        slug = pathonly[len("docs.html?doc="):]
        if slug not in docs_slugs:
            return f"docs.html link to unknown slug: {slug}"
        return None
    if pathonly.startswith("learning-series.html?post="):
        slug = pathonly[len("learning-series.html?post="):]
        if slug not in posts_slugs:
            return f"learning-series.html link to unknown slug: {slug}"
        return None
    if pathonly.startswith("learning-series.html"):
        return None

    if pathonly.startswith("../"):
        target = (source.parent / pathonly).resolve()
        if not target.exists():
            return f"missing file: {pathonly}"
        return None

    if pathonly.endswith(".md"):
        target = (source.parent / pathonly).resolve()
        if not target.exists():
            return f"missing post file: {pathonly}"
        slug = target.stem
        if slug not in posts_slugs:
            return f"slug not in posts-manifest.js: {slug}"
        return None

    target = (source.parent / pathonly).resolve()
    if not target.exists():
        return f"missing relative file: {pathonly}"
    return None


def test_docs_manifest_slugs_match_filesystem(docs_slugs):
    """Every doc on disk should be reachable from the manifest (and vice versa)."""
    on_disk = {
        str(p.relative_to(DOCS_DIR).with_suffix("")).replace("\\", "/")
        for p in DOCS_DIR.rglob("*.md")
    }
    only_in_manifest = docs_slugs - on_disk
    only_on_disk = on_disk - docs_slugs
    assert not only_in_manifest, f"manifest references missing files: {sorted(only_in_manifest)}"
    assert not only_on_disk, f"orphan docs not in manifest: {sorted(only_on_disk)}"


def test_posts_manifest_slugs_match_filesystem(posts_slugs):
    on_disk = {p.stem for p in POSTS_DIR.glob("*.md")}
    only_in_manifest = posts_slugs - on_disk
    only_on_disk = on_disk - posts_slugs
    assert not only_in_manifest, f"manifest references missing files: {sorted(only_in_manifest)}"
    assert not only_on_disk, f"orphan posts not in manifest: {sorted(only_on_disk)}"


def test_all_docs_links_resolve(docs_slugs):
    failures: list[str] = []
    for md in DOCS_DIR.rglob("*.md"):
        for href in _iter_links(md):
            err = _check_docs_link(href, md, docs_slugs)
            if err:
                failures.append(f"{md.relative_to(REPO_ROOT)}: [{href}] {err}")
    assert not failures, "Broken docs links:\n  " + "\n  ".join(failures)


def test_all_posts_links_resolve(posts_slugs, docs_slugs):
    failures: list[str] = []
    for md in POSTS_DIR.glob("*.md"):
        for href in _iter_links(md):
            err = _check_posts_link(href, md, posts_slugs, docs_slugs)
            if err:
                failures.append(f"{md.relative_to(REPO_ROOT)}: [{href}] {err}")
    assert not failures, "Broken posts links:\n  " + "\n  ".join(failures)


def test_manifests_match_generator():
    """Manifests on disk must equal what scripts/build_manifests.py would write.
    Prevents drift when contributors add markdown without re-running the generator."""
    import importlib.util

    spec = importlib.util.spec_from_file_location(
        "build_manifests", REPO_ROOT / "scripts" / "build_manifests.py"
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    expected_docs = module._build_docs_manifest()
    expected_posts = module._build_posts_manifest()
    actual_docs = DOCS_MANIFEST.read_text(encoding="utf-8")
    actual_posts = POSTS_MANIFEST.read_text(encoding="utf-8")

    assert actual_docs == expected_docs, (
        "docs-manifest.js is stale. Run: uv run python scripts/build_manifests.py"
    )
    assert actual_posts == expected_posts, (
        "posts-manifest.js is stale. Run: uv run python scripts/build_manifests.py"
    )
