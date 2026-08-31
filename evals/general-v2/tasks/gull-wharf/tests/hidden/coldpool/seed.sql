CREATE TABLE readings (
  id        serial PRIMARY KEY,
  station   text NOT NULL,
  celsius   numeric(6,2) NOT NULL,
  taken_at  timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON readings TO pool_probe;

INSERT INTO readings (station, celsius) VALUES
  ('brine-step',  2.00),
  ('brine-step',  3.50),
  ('brine-step',  4.00),
  ('frostline',  -1.25),
  ('frostline',   0.50),
  ('frostline',   2.75),
  ('frostline',   1.00);
