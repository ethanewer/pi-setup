import { useState } from 'react';
import { TEMPLATES, REPORT_HEAD, REPORT_MARKER, expandTemplate } from '../lib/reportTemplates';

export default function ReportsView() {
  const [detailId, setDetailId] = useState<string | null>(null);
  return (
    <section className="view" data-testid="reports-view" data-marker={REPORT_MARKER}>
      <h2 data-testid="reports-head">{REPORT_HEAD}</h2>
      <ul data-testid="reports-list">
        {TEMPLATES.slice(0, 12).map((t) => (
          <li key={t.id}>
            <span className="rid">{t.id}</span> {t.title}{' '}
            <button
              data-testid={`expand-${t.id}`}
              type="button"
              onClick={() => setDetailId(detailId === t.id ? null : t.id)}
            >
              {detailId === t.id ? 'Collapse' : 'Expand'}
            </button>
          </li>
        ))}
      </ul>
      <div data-testid="report-detail">{detailId ? expandTemplate(detailId) : ''}</div>
    </section>
  );
}