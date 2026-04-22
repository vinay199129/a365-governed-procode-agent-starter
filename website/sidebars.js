// @ts-check

/**
 * Sidebar configuration for the A365 Starter docs.
 *
 * The docs plugin reads from `../docs/` (the canonical content folder).
 * This sidebar groups those files into a reading-friendly hierarchy.
 *
 * @type {import('@docusaurus/plugin-content-docs').SidebarsConfig}
 */
const sidebars = {
  docsSidebar: [
    {
      type: 'category',
      label: 'Getting Started',
      collapsed: false,
      items: ['quickstart', 'troubleshooting'],
    },
    {
      type: 'category',
      label: 'Concepts',
      collapsed: false,
      items: ['learning-guide', 'project-scope'],
    },
    {
      type: 'category',
      label: 'Architecture',
      collapsed: false,
      items: ['design', 'code-walkthrough'],
    },
    {
      type: 'category',
      label: 'Setup & Operations',
      collapsed: false,
      items: ['setup-walkthrough'],
    },
    {
      type: 'category',
      label: 'Governance',
      collapsed: false,
      items: ['blueprint-policy'],
    },
    {
      type: 'category',
      label: 'Evidence',
      collapsed: false,
      items: [
        'evidence/multi-instance-inheritance',
        'evidence/round-trip',
      ],
    },
  ],
};

export default sidebars;
