-- Larkfield Airshed visible scenario seed (image infrastructure only).
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'airanalyst') THEN
    CREATE ROLE airanalyst LOGIN PASSWORD 'Larkfield-Brume-9417';
  END IF;
END $$;
SELECT 'CREATE DATABASE airshed OWNER postgres'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'airshed')\gexec
\connect airshed
CREATE TABLE IF NOT EXISTS readings (
  id          serial PRIMARY KEY,
  site        text NOT NULL,
  metric      text NOT NULL,
  value       double precision NOT NULL,
  tier        text NOT NULL,
  recorded_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON readings TO airanalyst;
-- Fully idempotent seed: only populate when the table is still empty, so a
-- re-run of the scenario bootstrap can never duplicate rows.
INSERT INTO readings (site, metric, value, tier)
SELECT v.site, v.metric, v.value, v.tier
FROM (VALUES
  ('Mill Pond',    'pm25', 11.5,   'verified'),
  ('Quarry Gate',  'pm25', 18.25,  'raw'),
  ('Quarry Gate',  'no2',  7.75,   'verified'),
  ('Mill Pond',    'o3',   31.5,   'verified'),
  ('Tide Sluice',  'pm25', 9.0,    'verified'),
  ('Tide Sluice',  'so2',  2.125,  'pending'),
  ('Harbor Row',   'no2',  12.625, 'verified')
) AS v(site, metric, value, tier)
WHERE NOT EXISTS (SELECT 1 FROM readings);
