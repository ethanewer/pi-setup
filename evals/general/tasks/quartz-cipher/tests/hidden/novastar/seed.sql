-- novastar hidden (edge): a database with baseline rows but ZERO committed
-- wal-committed records. The agent query must return an empty set here.
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
  ('N1-AA',   3,  'Lane Nine',    'seed'),
  ('N1-BB',   4,  'Lane Ten',     'seed');