CREATE TABLE readings (
  id        serial PRIMARY KEY,
  station   text NOT NULL,
  celsius   numeric(6,2) NOT NULL,
  taken_at  timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON readings TO well_reader;

INSERT INTO readings (station, celsius) VALUES
  ('deepsound',    4.50),
  ('deepsound',    6.00),
  ('deepsound',    5.25),
  ('deepsound',    7.00),
  ('kettle-cove', 10.00),
  ('kettle-cove', 12.50);
