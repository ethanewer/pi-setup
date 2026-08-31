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
  ('FEN-31', 'Rise Moss', 8, 'active'),
  ('FEN-32', 'Rise Moss', 2, 'offline'),
  ('FEN-33', 'Nether Heys', 8, 'active');
