CREATE TABLE meter_readings (
  id           serial PRIMARY KEY,
  meter        text NOT NULL,
  kwh          numeric NOT NULL,
  reading_date date NOT NULL,
  logged_at    timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON meter_readings TO weirbot;

INSERT INTO meter_readings (meter, kwh, reading_date) VALUES
  ('MTR-7701', 12.5,  '2031-06-01'),
  ('MTR-7701', 12.5,  '2031-06-01'),
  ('MTR-0812', 3.125, '2031-06-02'),
  ('MTR-5250', 40,    '2031-06-03'),
  ('MTR-5250', 41.5,  '2031-06-01');
