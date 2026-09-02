CREATE TABLE readings (
  id          INTEGER PRIMARY KEY,
  sensor      TEXT    NOT NULL,
  metric      TEXT    NOT NULL,
  value       REAL    NOT NULL,
  recorded_on TEXT    NOT NULL
);
