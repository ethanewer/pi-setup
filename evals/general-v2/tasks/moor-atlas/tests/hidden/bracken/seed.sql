DROP TABLE IF EXISTS beacons;
CREATE TABLE beacons (
  beacon_id  serial PRIMARY KEY,
  code       text NOT NULL,
  grid       text NOT NULL,
  strength   integer NOT NULL,
  status     text NOT NULL,
  logged_at  timestamptz NOT NULL DEFAULT now()
);
INSERT INTO beacons (code, grid, strength, status) VALUES
  ('BRK-11', 'Lantern Fell', 6, 'active'),
  ('BRK-12', 'Lantern Fell', 6, 'active'),
  ('BRK-13', 'Cradle Rigg', 15, 'idle'),
  ('BRK-14', 'Cradle Rigg', 15, 'active'),
  ('BRK-15', 'Whin Sill', 0, 'active');
