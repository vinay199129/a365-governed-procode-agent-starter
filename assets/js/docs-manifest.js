/**
 * Sidebar manifest for the docs viewer.
 * Each entry's `path` is relative to the repo root (where docs.html lives).
 * `slug` is what appears as ?doc=<slug> in the URL.
 */
window.DOCS_MANIFEST = [
  {
    section: 'Getting Started',
    items: [
      { slug: 'quickstart', title: 'Quickstart', path: 'docs/quickstart.md' },
      { slug: 'troubleshooting', title: 'Troubleshooting', path: 'docs/troubleshooting.md' },
    ],
  },
  {
    section: 'Concepts',
    items: [
      { slug: 'learning-guide', title: 'Learning Guide', path: 'docs/learning-guide.md' },
      { slug: 'project-scope', title: 'Project Scope', path: 'docs/project-scope.md' },
    ],
  },
  {
    section: 'Architecture',
    items: [
      { slug: 'design', title: 'Design', path: 'docs/design.md' },
      { slug: 'code-walkthrough', title: 'Code Walkthrough', path: 'docs/code-walkthrough.md' },
    ],
  },
  {
    section: 'Setup & Operations',
    items: [
      { slug: 'setup-walkthrough', title: 'Setup Walkthrough', path: 'docs/setup-walkthrough.md' },
    ],
  },
  {
    section: 'Governance',
    items: [
      { slug: 'blueprint-policy', title: 'Blueprint Policy', path: 'docs/blueprint-policy.md' },
    ],
  },
  {
    section: 'Evidence',
    items: [
      { slug: 'evidence/multi-instance-inheritance', title: 'Multi-instance inheritance', path: 'docs/evidence/multi-instance-inheritance.md' },
      { slug: 'evidence/round-trip', title: 'Round-trip reproducibility', path: 'docs/evidence/round-trip.md' },
    ],
  },
];
