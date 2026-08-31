-- hidden scenario: mistvale (port 5544, different db/user/password)
CREATE TABLE sensor_readings (
    id        serial PRIMARY KEY,
    station   text NOT NULL,
    metric    text NOT NULL,
    value     integer NOT NULL,
    taken_at  timestamptz NOT NULL DEFAULT now()
);
INSERT INTO sensor_readings (station, metric, value) VALUES
  ('ASH-2', 'temp',     11),
  ('ELM-6', 'ph',        9),
  ('ELM-6', 'temp',     17),
  ('OAK-9', 'salinity', 33);
GRANT SELECT ON sensor_readings TO fogbot;
