CREATE TABLE telemetry_readings (
    reading_id integer PRIMARY KEY,
    sensor_id  text NOT NULL,
    reading    integer NOT NULL,
    quality    text NOT NULL
);
INSERT INTO telemetry_readings (reading_id, sensor_id, reading, quality) VALUES
  (21, 'q-sensor',  55,  'edge'),
  (22, 'q-sensor',  61,  'edge'),
  (23, 'q-sonde',   540, 'nominal');
