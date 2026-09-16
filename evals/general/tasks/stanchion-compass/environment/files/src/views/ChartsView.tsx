import { useState } from 'react';
import { STATIONS, LAST_VALUES, CHART_HEAD, CHART_MARKER, reseedChart } from '../lib/chartsData';

export default function ChartsView() {
  const [seed, setSeed] = useState(1);
  return (
    <section className="view" data-testid="charts-view" data-marker={CHART_MARKER}>
      <h2 data-testid="charts-head">{CHART_HEAD}</h2>
      <p className="row">
        Seed badge: <output data-testid="charts-seed">{reseedChart(seed)}</output>
        <button data-testid="charts-reseed" type="button" onClick={() => setSeed((s) => (s % 20) + 1)}>
          Reseed chart
        </button>
      </p>
      <table data-testid="charts-table">
        <thead>
          <tr>
            <th>Station</th>
            <th>Last value</th>
          </tr>
        </thead>
        <tbody>
          {STATIONS.map((st) => (
            <tr key={st.name}>
              <td>{st.name}</td>
              <td>{LAST_VALUES[st.name]}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </section>
  );
}