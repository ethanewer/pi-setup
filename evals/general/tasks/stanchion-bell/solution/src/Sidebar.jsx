/**
 * Supporting column with quick links, rendered after the main content so
 * keyboard users reach it last.
 */
export default function Sidebar({ links }) {
  return (
    <aside className="sidebar">
      <h2 className="sidebar-title">Quick links</h2>
      <ul className="sidebar-links">
        {links.map((item) => (
          <li key={item.href}>
            <a href={item.href} className="sidebar-link">{item.label}</a>
          </li>
        ))}
      </ul>
    </aside>
  );
}
