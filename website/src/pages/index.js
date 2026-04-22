/**
 * HVE-Core-inspired landing page.
 * Hero with two CTAs, "Quick links" pills, "Deep dive" 4-card grid, "Collections" grid.
 */

import clsx from 'clsx';
import Link from '@docusaurus/Link';
import useDocusaurusContext from '@docusaurus/useDocusaurusContext';
import Layout from '@theme/Layout';

import styles from './index.module.css';

function Hero() {
  const { siteConfig } = useDocusaurusContext();
  return (
    <header className={clsx('hero', styles.hero)}>
      <div className="container">
        <div className={styles.heroBadge}>Reference Implementation · Microsoft Agent 365</div>
        <h1 className={styles.heroTitle}>{siteConfig.title}</h1>
        <p className={styles.heroSubtitle}>{siteConfig.tagline}</p>
        <div className={styles.heroButtons}>
          <Link className="button button--primary button--lg" to="/docs/quickstart">
            Get started
          </Link>
          <Link
            className="button button--secondary button--lg"
            to="/learning-series"
          >
            Read the learning series
          </Link>
        </div>
        <div className={styles.quickPills}>
          <Link to="/docs/quickstart" className={styles.pill}>
            <span className={styles.pillLabel}>QUICKSTART</span>
            <span className={styles.pillText}>Provision in &lt; 1 hour</span>
          </Link>
          <Link to="/docs/learning-guide" className={styles.pill}>
            <span className={styles.pillLabel}>CONCEPTS</span>
            <span className={styles.pillText}>What is Agent 365?</span>
          </Link>
          <Link to="/docs/design" className={styles.pill}>
            <span className={styles.pillLabel}>ARCHITECTURE</span>
            <span className={styles.pillText}>System design</span>
          </Link>
          <Link to="/docs/blueprint-policy" className={styles.pill}>
            <span className={styles.pillLabel}>GOVERNANCE</span>
            <span className={styles.pillText}>Security blueprint</span>
          </Link>
          <Link to="/docs/code-walkthrough" className={styles.pill}>
            <span className={styles.pillLabel}>CODE</span>
            <span className={styles.pillText}>F5 → response trace</span>
          </Link>
          <Link to="/docs/evidence/round-trip" className={styles.pill}>
            <span className={styles.pillLabel}>EVIDENCE</span>
            <span className={styles.pillText}>Reproducibility proof</span>
          </Link>
        </div>
      </div>
    </header>
  );
}

const deepDive = [
  {
    title: 'Quick Start',
    blurb: 'Provision Azure OpenAI, Entra app, A365 blueprint, and agent identity in one script.',
    links: [
      { to: '/docs/quickstart', label: 'Quickstart guide' },
      { to: '/docs/setup-walkthrough', label: 'Setup walkthrough' },
      { to: '/docs/troubleshooting', label: 'Troubleshooting' },
    ],
  },
  {
    title: 'Build with A365',
    blurb: 'Pro-code agents that plug into Agent 365 for governance, identity, and audit.',
    links: [
      { to: '/docs/learning-guide', label: 'Concept walkthrough' },
      { to: '/docs/code-walkthrough', label: 'Request flow' },
      { to: '/docs/design', label: 'Design' },
    ],
  },
  {
    title: 'Plan & Architect',
    blurb: 'Understand the moving parts before touching code — host, agent, MCP tools, governance.',
    links: [
      { to: '/docs/design', label: 'Architecture overview' },
      { to: '/docs/project-scope', label: 'Scope & gap analysis' },
      { to: '/docs/blueprint-policy', label: 'Security blueprint' },
    ],
  },
  {
    title: 'Prove & Extend',
    blurb: 'Captured evidence for reproducibility and inheritance, plus extension patterns.',
    links: [
      { to: '/docs/evidence/multi-instance-inheritance', label: 'Multi-instance inheritance' },
      { to: '/docs/evidence/round-trip', label: 'Round-trip reproducibility' },
      { to: '/learning-series', label: 'Learning series' },
    ],
  },
];

function DeepDive() {
  return (
    <section className={styles.section}>
      <div className="container">
        <h2 className={styles.sectionTitle}>Deep dive</h2>
        <p className={styles.sectionSubtitle}>
          Explore the starter from concept to evidence — every card links to runnable
          code in this repository.
        </p>
        <div className={styles.cardGrid}>
          {deepDive.map((card) => (
            <div key={card.title} className={styles.card}>
              <h3 className={styles.cardTitle}>{card.title}</h3>
              <p className={styles.cardBlurb}>{card.blurb}</p>
              <ul className={styles.cardLinks}>
                {card.links.map((l) => (
                  <li key={l.to}>
                    <Link to={l.to}>{l.label} →</Link>
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}

const collections = [
  {
    name: 'governance',
    badge: 'STABLE',
    blurb: 'Blueprint policy, scope inheritance, agent identity',
    count: '6 docs',
    to: '/docs/blueprint-policy',
  },
  {
    name: 'setup',
    badge: 'STABLE',
    blurb: 'Provisioning scripts, environment config, teardown',
    count: '4 docs',
    to: '/docs/setup-walkthrough',
  },
  {
    name: 'architecture',
    badge: 'STABLE',
    blurb: 'Host pattern, MCP tools, observability',
    count: '5 docs',
    to: '/docs/design',
  },
  {
    name: 'concepts',
    badge: 'STABLE',
    blurb: 'A365 building blocks, what works pre-Frontier',
    count: '3 docs',
    to: '/docs/learning-guide',
  },
  {
    name: 'evidence',
    badge: 'PREVIEW',
    blurb: 'Captured proof for inheritance and reproducibility',
    count: '2 docs',
    to: '/docs/evidence/round-trip',
  },
  {
    name: 'learning-series',
    badge: 'STABLE',
    blurb: 'Blog-style guided reading path with try-it-yourself sections',
    count: '7 posts',
    to: '/learning-series',
  },
];

function Collections() {
  return (
    <section className={clsx(styles.section, styles.sectionAlt)}>
      <div className="container">
        <h2 className={styles.sectionTitle}>Collections</h2>
        <p className={styles.sectionSubtitle}>Browse content bundles by topic.</p>
        <div className={styles.collectionGrid}>
          {collections.map((c) => (
            <Link key={c.name} to={c.to} className={styles.collectionCard}>
              <div className={styles.collectionHeader}>
                <span className={styles.collectionName}>{c.name}</span>
                <span
                  className={clsx(styles.collectionBadge, {
                    [styles.badgePreview]: c.badge === 'PREVIEW',
                  })}
                >
                  {c.badge}
                </span>
              </div>
              <p className={styles.collectionBlurb}>{c.blurb}</p>
              <div className={styles.collectionCount}>{c.count}</div>
            </Link>
          ))}
        </div>
      </div>
    </section>
  );
}

export default function Home() {
  const { siteConfig } = useDocusaurusContext();
  return (
    <Layout
      title={siteConfig.title}
      description={siteConfig.tagline}
    >
      <Hero />
      <main>
        <DeepDive />
        <Collections />
      </main>
    </Layout>
  );
}
