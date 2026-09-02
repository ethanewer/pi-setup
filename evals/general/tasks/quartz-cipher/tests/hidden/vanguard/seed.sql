-- vanguard hidden scenario: replay of the same schema/marker with different
-- seed + wal-committed rows (agent query must not be hard-coded to the
-- visible skus).
DROP TABLE IF EXISTS shipments;
CREATE TABLE shipments (
  id          serial PRIMARY KEY,
  sku         text NOT NULL,
  qty         integer NOT NULL,
  destination text NOT NULL,
  batch       text NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now()
);
INSERT INTO shipments (sku, qty, destination, batch) VALUES
  ('VG-01',   8,  'Base Dock A',   'seed'),
  ('VG-02',   5,  'Base Dock B',   'seed'),
  ('HZ-71',  11,  'Ridge Yard',    'wal-committed'),
  ('HZ-12',   2,  'Outer Spur',    'wal-committed');