-- Visible development fixture for the keelson-berth catalogue service.
-- The verifier uses its own hidden fixtures; this one is for the agent to
-- develop against.  The schema is the service contract: every fixture (this
-- one included) is built from exactly this DDL plus data rows.

CREATE TABLE IF NOT EXISTS items (
  sku TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  price REAL NOT NULL,
  quantity INTEGER NOT NULL,
  category TEXT NOT NULL
);

INSERT INTO items (sku, title, price, quantity, category) VALUES
  ('ml-001', 'Linen notebook A5',   9.99,  40, 'stationery'),
  ('ml-002', 'Linen notebook A4',   14.5,  12, 'stationery'),
  ('ml-003', 'Ink bottle - blue',   6.25,  80, 'stationery'),
  ('ml-004', 'Ink bottle - sepia',  7.00,   0, 'stationery'),
  ('ml-005', 'Padfolio deluxe',     39.9,   5, 'leather'),
  ('ml-006', 'Padfolio standard',   24.0,  18, 'leather'),
  ('ml-007', 'Condenser microphone',129.5,  3, 'audio'),
  ('ml-008', 'Dynamic microphone',  59.0,  22, 'audio'),
  ('ml-009', 'Studio monitor pair', 349.99, 2, 'audio'),
  ('ml-010', 'Softbox kit',         45.5,   9, 'studio');