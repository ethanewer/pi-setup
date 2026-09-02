CREATE TABLE specimens (
  id           serial PRIMARY KEY,
  catalog_code text NOT NULL,
  species      text NOT NULL,
  quadrant     text NOT NULL,
  collected_at date NOT NULL,
  mass_g       integer NOT NULL
);

INSERT INTO specimens (catalog_code, species, quadrant, collected_at, mass_g) VALUES
  ('XC-3301', 'Dryas integrifolia',        'Q1', '2031-08-04',  66),
  ('XC-3302', 'Rhododendron tomentosum',   'Q8', '2031-08-15', 154);
