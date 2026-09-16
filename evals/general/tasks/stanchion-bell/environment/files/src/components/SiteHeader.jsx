/**
 * Site banner: brand, primary navigation and the current announcement.
 */
export default function SiteHeader({ site, announcement }) {
  const primary = site.nav || [];
  return (
    <header className="site-header">
      <img className="brand-logo" src="/img/lantern.svg" />
      <h1 className="brand-name">{site.name}</h1>
      <nav className="site-nav">
        {primary.map((item) => (
          <a key={item.href} className="nav-link" href={item.href}>
            {item.label}
          </a>
        ))}
      </nav>
      <span className="menu-toggle" role="button" aria-expanded="false">
        <span aria-hidden="true">☰</span>
      </span>
      <div className="announcement">{announcement}</div>
    </header>
  );
}
