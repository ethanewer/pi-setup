CREATE TABLE specimens (
  id           serial PRIMARY KEY,
  catalog_code text NOT NULL,
  species      text NOT NULL,
  quadrant     text NOT NULL,
  collected_at date NOT NULL,
  mass_g       integer NOT NULL
);

INSERT INTO specimens (catalog_code, species, quadrant, collected_at, mass_g) VALUES
  ('AU-2201', 'Saxifraga oppositifolia',  'Q4', '2031-07-03', 142),
  ('AU-2202', 'Loiseleuria procumbens',   'Q9', '2031-07-11',  77),
  ('AU-2203', 'Cryptogramma crispa',      'Q2', '2031-07-30', 205);
