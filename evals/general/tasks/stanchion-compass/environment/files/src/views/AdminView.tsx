import { useState } from 'react';
import { AUDIT_INDEX, AUDIT_HEAD, AUDIT_MARKER, auditChecksum } from '../lib/auditIndex';

export default function AdminView() {
  const [checksum, setChecksum] = useState<string | null>(null);
  return (
    <section className="view" data-testid="admin-view" data-marker={AUDIT_MARKER}>
      <h2 data-testid="audit-head">{AUDIT_HEAD}</h2>
      <p className="row">
        <button data-testid="audit-verify" type="button" onClick={() => setChecksum(auditChecksum())}>
          Verify index
        </button>
        Checksum: <output data-testid="audit-sum">{checksum ?? ''}</output>
      </p>
      <ul data-testid="audit-list">
        {AUDIT_INDEX.slice(0, 10).map((e) => (
          <li key={e.id}>
            <code className="aid">{e.id}</code> {e.desc}
          </li>
        ))}
      </ul>
    </section>
  );
}