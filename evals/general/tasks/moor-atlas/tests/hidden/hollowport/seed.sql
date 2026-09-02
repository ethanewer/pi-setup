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
  ('HOL-21', 'Black Gutter', 11, 'active'),
  ('HOL-22', 'Black Gutter', 3, 'idle'),
  ('HOL-23', 'Sike Shaw', 11, 'active');
