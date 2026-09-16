/**
 * Supporting column with quick links.
 */
export default function Sidebar({ links }) {
  return (
    <aside className="sidebar">
      <h3 className="sidebar-title">Quick links</h3>
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
