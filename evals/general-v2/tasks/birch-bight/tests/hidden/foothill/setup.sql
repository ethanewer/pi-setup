-- hidden case foothill: no verified rows at all (header-only CSV expected)
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'fhwatch') THEN
    CREATE ROLE fhwatch LOGIN PASSWORD 'Fern-Hollow-3310';
  END IF;
END $$;
SELECT 'CREATE DATABASE foothill OWNER postgres'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'foothill')\gexec
\connect foothill
CREATE TABLE IF NOT EXISTS readings (
  id          serial PRIMARY KEY,
  site        text NOT NULL,
  metric      text NOT NULL,
  value       double precision NOT NULL,
  tier        text NOT NULL,
  recorded_at timestamptz NOT NULL DEFAULT now()
);
TRUNCATE readings RESTART IDENTITY;
INSERT INTO readings (site, metric, value, tier) VALUES
  ('Fern Hollow', 'pm25', 3.5,  'raw'),
  ('Fern Hollow', 'no2',  9.99, 'pending'),
  ('Bog Side',    'o3',   19.5, 'raw');
GRANT SELECT ON readings TO fhwatch;
