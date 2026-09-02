-- hidden case estuary: database name equals the user name (no POSTGRES_DB)
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'estuary') THEN
    CREATE ROLE estuary LOGIN PASSWORD 'Bight-Sluice-7788';
  END IF;
END $$;
SELECT 'CREATE DATABASE estuary OWNER postgres'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'estuary')\gexec
\connect estuary
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
  ('Reed Flat',    'pm25', 8.75, 'verified'),
  ('Reed Flat',    'no2',  13.4, 'raw'),
  ('Gunwale Quay', 'o3',   27.2, 'verified'),
  ('Gunwale Quay', 'pm25', 5.05, 'verified');
GRANT SELECT ON readings TO estuary;
