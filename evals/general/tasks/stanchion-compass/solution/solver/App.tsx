import { Suspense, lazy, useEffect, useState } from 'react';
import Home from './pages/Home';

// Route-level code splitting: each heavy view is loaded lazily so its chunk
// is fetched only when the route is visited.
const ChartsView = lazy(() => import('./views/ChartsView'));
const ReportsView = lazy(() => import('./views/ReportsView'));
const AdminView = lazy(() => import('./views/AdminView'));

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
        <Suspense fallback={<p className="loading">Loading route…</p>}>
          {active === '#/charts' && <ChartsView />}
          {active === '#/reports' && <ReportsView />}
          {active === '#/admin' && <AdminView />}
        </Suspense>
      </main>
    </div>
  );
}