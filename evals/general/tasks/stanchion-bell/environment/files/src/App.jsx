import home from './data/home.mjs';
import SiteHeader from './components/SiteHeader.jsx';
import SiteFooter from './components/SiteFooter.jsx';
import Sidebar from './components/Sidebar.jsx';
import PageMain from './components/PageMain.jsx';

/**
 * Lanternwell Clinic website root. Renders one page from its definition;
 * defaults to the home page.
 */
export default function App({ page }) {
  const def = page || home;
  return (
    <>
      <SiteHeader site={def.site} announcement={def.announcement} />
      <Sidebar links={def.sidebarLinks} />
      <PageMain page={def} />
      <SiteFooter name={def.site.name} />
    </>
  );
}
