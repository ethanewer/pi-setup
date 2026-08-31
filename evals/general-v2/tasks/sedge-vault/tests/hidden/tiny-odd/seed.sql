CREATE TABLE specimens (
  id           serial PRIMARY KEY,
  catalog_code text NOT NULL,
  species      text NOT NULL,
  quadrant     text NOT NULL,
  collected_at date NOT NULL,
  mass_g       integer NOT NULL
);

INSERT INTO specimens (catalog_code, species, quadrant, collected_at, mass_g) VALUES
  ('TN-4401', 'Saxifraga aizoides ''Alba''', 'Q6', '2031-09-09',  58),
  ('TN-4402', 'Vigna radiata — mire form',   'Q3', '2031-09-21',  90);
