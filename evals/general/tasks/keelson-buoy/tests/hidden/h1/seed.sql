-- keelson-buoy cargoops scenario data (deterministic, generated).
-- Replayed on an empty target database by pgctl and by the verifier.
BEGIN;

CREATE TABLE IF NOT EXISTS positions (
    position_id integer PRIMARY KEY,
    vessel_code text NOT NULL,
    cargo_kg integer NOT NULL,
    tariff_code text NOT NULL,
    updated_at timestamptz NOT NULL,
    seal_tag text NOT NULL
);

CREATE TABLE IF NOT EXISTS movements (
    move_id integer PRIMARY KEY,
    position_id integer NOT NULL,
    delta_kg integer NOT NULL,
    moved_at timestamptz NOT NULL
);

CREATE INDEX IF NOT EXISTS movements_position_idx ON movements (position_id);

INSERT INTO positions (position_id, vessel_code, cargo_kg, tariff_code, updated_at, seal_tag) VALUES
    (1001, 'MSC-LYRA', 4662, 'TRF-5197', '2024-11-15 15:54:00+00', 'KEEP-DELTA'),
    (1002, 'MSC-LYRA', 15129, 'TRF-6206', '2025-01-07 23:44:00+00', 'KEEP-EPSILON'),
    (1003, 'MV-PELICAN', 14072, 'TRF-3177', '2024-12-28 08:38:00+00', 'KEEP-ZETA'),
    (1004, 'MV-PELICAN', 0, 'TRF-1934', '2024-09-05 07:41:00+00', 'ROUTINE'),
    (1005, 'MV-PELICAN', 0, 'TRF-5345', '2024-07-18 17:07:00+00', 'ROUTINE'),
    (1006, 'MSC-TALOS', 0, 'TRF-7873', '2024-11-07 22:35:00+00', 'ROUTINE'),
    (1007, 'MSC-DIONE', 0, 'TRF-6545', '2024-12-05 23:23:00+00', 'ROUTINE'),
    (1008, 'MV-CORMORANT', 77629, 'TRF-4504', '2024-12-11 08:57:00+00', 'ROUTINE'),
    (1009, 'MV-ORCA', 71398, 'TRF-6165', '2024-05-11 14:13:00+00', 'ROUTINE'),
    (1010, 'MSC-TALOS', 53225, 'TRF-6157', '2024-12-28 08:41:00+00', 'ROUTINE'),
    (1011, 'CS-GANNET', 0, 'TRF-7256', '2024-12-08 17:31:00+00', 'ROUTINE'),
    (1012, 'CS-GANNET', 46500, 'TRF-6614', '2024-12-17 04:41:00+00', 'ROUTINE');

INSERT INTO movements (move_id, position_id, delta_kg, moved_at) VALUES
    (1, 1002, -4725, '2024-12-13 23:08:00+00'),
    (2, 1002, -2775, '2025-01-07 23:44:00+00'),
    (3, 1003, 3450, '2024-12-10 07:15:00+00'),
    (4, 1003, -1975, '2024-12-28 08:38:00+00'),
    (5, 1007, 4325, '2024-12-05 23:23:00+00'),
    (6, 1008, 5000, '2024-12-02 01:58:00+00'),
    (7, 1008, 5300, '2024-12-11 08:57:00+00'),
    (8, 1010, 50775, '2024-12-19 15:28:00+00'),
    (9, 1010, 2450, '2024-12-28 08:41:00+00'),
    (10, 1011, 4950, '2024-12-08 17:31:00+00'),
    (11, 1012, 40825, '2024-12-13 05:59:00+00'),
    (12, 1012, 3850, '2024-12-16 19:01:00+00'),
    (13, 1012, 1825, '2024-12-17 04:41:00+00');

COMMIT;
