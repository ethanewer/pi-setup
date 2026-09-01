CREATE TABLE meter_readings (
  id           serial PRIMARY KEY,
  meter        text NOT NULL,
  kwh          numeric NOT NULL,
  reading_date date NOT NULL,
  logged_at    timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON meter_readings TO gprobe;
