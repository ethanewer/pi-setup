-- hidden case northridge: distinct role/password/db and rows
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'nrreader') THEN
    CREATE ROLE nrreader LOGIN PASSWORD 'Ridge-Mist-2201';
  END IF;
END $$;
SELECT 'CREATE DATABASE northridge OWNER postgres'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'northridge')\gexec
\connect northridge
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
  ('Drift Point',  'pm25', 14.5,  'verified'),
  ('Drift Point',  'o3',   22.0,  'raw'),
  ('Cinder Marsh', 'pm25', 6.25,  'verified'),
  ('Cinder Marsh', 'so2',  1.5,   'verified'),
  ('Long Pier',    'no2',  15.75, 'pending');
GRANT SELECT ON readings TO nrreader;
