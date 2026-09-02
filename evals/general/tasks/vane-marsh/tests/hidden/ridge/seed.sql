CREATE TABLE meter_readings (
  id           serial PRIMARY KEY,
  meter        text NOT NULL,
  kwh          numeric NOT NULL,
  reading_date date NOT NULL,
  logged_at    timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON meter_readings TO ridgeline;

INSERT INTO meter_readings (meter, kwh, reading_date) VALUES
  ('MTR-9001', 7.5, '2032-01-15');
