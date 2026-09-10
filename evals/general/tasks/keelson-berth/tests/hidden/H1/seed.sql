-- Hidden case H1: a mid-size catalogue with unicode titles, an empty
-- category, index-like skus that share prefixes, and stores with zero stock.

CREATE TABLE IF NOT EXISTS items (
  sku TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  price REAL NOT NULL,
  quantity INTEGER NOT NULL,
  category TEXT NOT NULL
);

INSERT INTO items (sku, title, price, quantity, category) VALUES
  ('pr-2',   'A5 pad ruled',           2.25, 60,   'paper'),
  ('pr-202', 'A5 pad dotted',          2.25, 0,    'paper'),
  ('pr-20',  'A5 pad grid',            2.50, 33,   'paper'),
  ('pen-7',  'Ballpoint fine blue',    1.10, 200,  'writing'),
  ('pen-7b', 'Ballpoint fine black',   1.10, 199,  'writing'),
  ('pen-70', 'Gel pen 0.5 pack 3',     4.75, 25,   'writing'),
  ('st-00',  'Sticky notes 75x75',     3.25, 120,  'desk'),
  ('st-01',  'Sticky notes 127x76',    4.00, 90,   'desk'),
  ('desk-a', 'Cable manager pack',     8.90, 14,   'desk'),
  ('desk-b', 'Monitor riser curved',   22.5, 6,    'desk'),
  ('lit-1',  'Desk lamp steel',        29.99, 9,   'desk'),
  ('lit-1x', 'Desk lamp white',        31.0, 11,   'desk'),
  ('art-9', 'Café notebook kraft',    6.4,  40,   'paper'),
  ('box-z',  'Archive box small',      12.0, 0,    'storage');