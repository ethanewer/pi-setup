CREATE TABLE telemetry_readings (
    reading_id integer PRIMARY KEY,
    sensor_id  text NOT NULL,
    reading    integer NOT NULL,
    quality    text NOT NULL
);
INSERT INTO telemetry_readings (reading_id, sensor_id, reading, quality) VALUES
  (11, 'nr-dome',  733, 'nominal'),
  (12, 'nr-dome',  740, 'drift'),
  (13, 'nr-ridge', 118, 'nominal');
