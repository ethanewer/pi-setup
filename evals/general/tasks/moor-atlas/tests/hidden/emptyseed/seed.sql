DROP TABLE IF EXISTS beacons;
CREATE TABLE beacons (
  beacon_id  serial PRIMARY KEY,
  code       text NOT NULL,
  grid       text NOT NULL,
  strength   integer NOT NULL,
  status     text NOT NULL,
  logged_at  timestamptz NOT NULL DEFAULT now()
);

