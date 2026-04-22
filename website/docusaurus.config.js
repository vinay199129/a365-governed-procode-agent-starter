// @ts-check
// Docusaurus config for the A365 Governed Pro-Code Agent Starter site.
// See https://docusaurus.io/docs/api/docusaurus-config

import { themes as prismThemes } from 'prism-react-renderer';

/** @type {import('@docusaurus/types').Config} */
const config = {
  title: 'A365 Governed Pro-Code Agent Starter',
  tagline: 'Build governed, audited AI agents on Microsoft Agent 365 — without Copilot Studio',
  favicon: 'img/favicon.ico',

  // Set the production url and base path. Update org/project to match your GitHub.
  url: 'https://vinay199129.github.io',
  baseUrl: '/a365-governed-procode-agent-starter/',

  organizationName: 'vinay199129',
  projectName: 'a365-governed-procode-agent-starter',
  deploymentBranch: 'gh-pages',
  trailingSlash: false,

  onBrokenLinks: 'warn',
  onBrokenMarkdownLinks: 'warn',

  i18n: {
    defaultLocale: 'en',
    locales: ['en'],
  },

  presets: [
    [
      'classic',
      /** @type {import('@docusaurus/preset-classic').Options} */
      ({
        docs: {
          // Pull markdown straight from the repo's existing docs/ folder.
          // No content duplication — the docs are the source of truth.
          path: '../docs',
          routeBasePath: 'docs',
          sidebarPath: './sidebars.js',
          editUrl:
            'https://github.com/vinay199129/a365-governed-procode-agent-starter/tree/main/',
        },
        blog: {
          path: 'blog',
          routeBasePath: 'learning-series',
          blogTitle: 'Learning Series',
          blogDescription:
            'A guided reading path through the starter — concepts, architecture, setup, and evidence.',
          showReadingTime: true,
          postsPerPage: 10,
          blogSidebarTitle: 'Recent posts',
          blogSidebarCount: 'ALL',
          editUrl:
            'https://github.com/vinay199129/a365-governed-procode-agent-starter/tree/main/website/',
        },
        theme: {
          customCss: './src/css/custom.css',
        },
      }),
    ],
  ],

  themeConfig:
    /** @type {import('@docusaurus/preset-classic').ThemeConfig} */
    ({
      image: 'img/social-card.png',
      colorMode: {
        defaultMode: 'light',
        respectPrefersColorScheme: true,
      },
      navbar: {
        title: 'A365 Starter',
        logo: {
          alt: 'A365 Starter Logo',
          src: 'img/logo.svg',
        },
        items: [
          {
            type: 'docSidebar',
            sidebarId: 'docsSidebar',
            position: 'left',
            label: 'Docs',
          },
          { to: '/learning-series', label: 'Learning Series', position: 'left' },
          { to: '/docs/quickstart', label: 'Quickstart', position: 'left' },
          {
            href: 'https://github.com/vinay199129/a365-governed-procode-agent-starter',
            label: 'GitHub',
            position: 'right',
          },
        ],
      },
      footer: {
        style: 'dark',
        links: [
          {
            title: 'Documentation',
            items: [
              { label: 'Quickstart', to: '/docs/quickstart' },
              { label: 'Concepts', to: '/docs/learning-guide' },
              { label: 'Architecture', to: '/docs/design' },
              { label: 'Setup walkthrough', to: '/docs/setup-walkthrough' },
            ],
          },
          {
            title: 'Governance',
            items: [
              { label: 'Blueprint policy', to: '/docs/blueprint-policy' },
              { label: 'Multi-instance evidence', to: '/docs/evidence/multi-instance-inheritance' },
              { label: 'Round-trip evidence', to: '/docs/evidence/round-trip' },
            ],
          },
          {
            title: 'Resources',
            items: [
              { label: 'Learning Series', to: '/learning-series' },
              { label: 'Troubleshooting', to: '/docs/troubleshooting' },
              {
                label: 'Microsoft Agent 365 docs',
                href: 'https://learn.microsoft.com/en-us/microsoft-agent-365/developer/',
              },
            ],
          },
          {
            title: 'Community',
            items: [
              {
                label: 'GitHub',
                href: 'https://github.com/vinay199129/a365-governed-procode-agent-starter',
              },
              {
                label: 'Issues',
                href: 'https://github.com/vinay199129/a365-governed-procode-agent-starter/issues',
              },
            ],
          },
        ],
        copyright: `© ${new Date().getFullYear()} A365 Governed Pro-Code Agent Starter contributors. Built with Docusaurus.`,
      },
      prism: {
        theme: prismThemes.github,
        darkTheme: prismThemes.dracula,
        additionalLanguages: ['powershell', 'bash', 'python', 'json', 'yaml'],
      },
      announcementBar: {
        id: 'preview-banner',
        content:
          '🚀 <b>Microsoft Agent 365 reaches GA on May 1, 2026.</b> Until then, ingest-side features require <a target="_blank" rel="noopener noreferrer" href="https://adoption.microsoft.com/copilot/frontier-program/">Frontier preview</a>.',
        backgroundColor: '#0a3d91',
        textColor: '#ffffff',
        isCloseable: true,
      },
    }),
};

export default config;
