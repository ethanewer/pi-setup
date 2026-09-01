CREATE TABLE records (
    id     INTEGER PRIMARY KEY,
    tag    TEXT,
    amount REAL
);
-- Original table held rows with id from 1..1500; the on-disk file was truncated.
