export default function Home() {
  return (
    <section className="view" data-testid="home-view">
      <h2 data-testid="home-head">Console home</h2>
      <p>
        Stanchion Compass aggregates telemetry from the station network. Use
        the links above to explore charts, reports and the audit index.
      </p>
      <ul className="home-links">
        <li>
          <a href="#/charts">Station time-series charts</a>
        </li>
        <li>
          <a href="#/reports">Report template catalogue</a>
        </li>
        <li>
          <a href="#/admin">Audit index browser</a>
        </li>
      </ul>
    </section>
  );
}