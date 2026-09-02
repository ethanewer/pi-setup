CREATE TABLE telemetry_readings (
    reading_id integer PRIMARY KEY,
    sensor_id  text NOT NULL,
    reading    integer NOT NULL,
    quality    text NOT NULL
);
INSERT INTO telemetry_readings (reading_id, sensor_id, reading, quality) VALUES
  (31, 'd-alpha', 900, 'nominal'),
  (32, 'd-beta',  733, 'drift');
