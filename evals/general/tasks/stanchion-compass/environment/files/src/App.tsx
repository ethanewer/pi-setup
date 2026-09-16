import { useEffect, useState } from 'react';
import Home from './pages/Home';
import ChartsView from './views/ChartsView';
import ReportsView from './views/ReportsView';
import AdminView from './views/AdminView';

const ROUTES = ['#/', '#/charts', '#/reports', '#/admin'];

function useHash() {
  const [hash, setHash] = useState(() => window.location.hash || '#/');
  useEffect(() => {
    const onHash = () => setHash(window.location.hash || '#/');
    window.addEventListener('hashchange', onHash);
    return () => window.removeEventListener('hashchange', onHash);
  }, []);
  return hash;
}

export default function App() {
  const hash = useHash();
  const active = ROUTES.includes(hash) ? hash : '#/';
  return (
    <div className="app">
      <header className="app-header">
        <h1>Stanchion Compass</h1>
        <nav>
          <a href="#/">Home</a>
          <a href="#/charts">Charts</a>
          <a href="#/reports">Reports</a>
          <a href="#/admin">Admin</a>
        </nav>
      </header>
      <main>
        {active === '#/' && <Home />}
        {active === '#/charts' && <ChartsView />}
        {active === '#/reports' && <ReportsView />}
        {active === '#/admin' && <AdminView />}
      </main>
    </div>
  );
}