-- hidden scenario: quietdock (port 5432, different db/user/password)
CREATE TABLE sensor_readings (
    id        serial PRIMARY KEY,
    station   text NOT NULL,
    metric    text NOT NULL,
    value     integer NOT NULL,
    taken_at  timestamptz NOT NULL DEFAULT now()
);
INSERT INTO sensor_readings (station, metric, value) VALUES
  ('CRAB-3',  'ph',       7),
  ('CRAB-3',  'temp',    12),
  ('HERON-8', 'salinity', 29),
  ('HERON-8', 'temp',    15),
  ('KEEL-4',  'temp',    13);
GRANT SELECT ON sensor_readings TO quaybot;
