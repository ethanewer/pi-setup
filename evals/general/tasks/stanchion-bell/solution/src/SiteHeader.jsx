/**
 * Site banner: skip link, brand, primary navigation and the current
 * announcement (announced to assistive technology as it changes).
 */
export default function SiteHeader({ site, announcement }) {
  const primary = site.nav || [];
  return (
    <header className="site-header">
      <a className="skip-link" href="#main-content">Skip to main content</a>
      <img className="brand-logo" src="/img/lantern.svg" alt={`${site.name} logo`} />
      <p className="brand-name">{site.name}</p>
      <nav className="site-nav" aria-label="Primary">
        {primary.map((item) => (
          <a key={item.href} className="nav-link" href={item.href}>
            {item.label}
          </a>
        ))}
      </nav>
      <button
        type="button"
        className="menu-toggle"
        aria-expanded="false"
        aria-label="Open navigation menu"
      >
        <span aria-hidden="true">☰</span>
      </button>
      <div className="announcement" role="status">{announcement}</div>
    </header>
  );
}
