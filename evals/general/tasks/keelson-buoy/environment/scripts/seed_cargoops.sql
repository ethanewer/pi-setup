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
    (1001, 'MV-SOREL', 84725, 'TRF-4292', '2024-11-08 06:30:00+00', 'KEEP-ALPHA'),
    (1002, 'MV-CALDER', 87208, 'TRF-4971', '2024-12-22 05:08:00+00', 'KEEP-BETA'),
    (1003, 'MV-TRITON', -9228, 'TRF-3279', '2024-12-20 03:34:00+00', 'ROUTINE'),
    (1004, 'MSC-ERIDANUS', 8958, 'TRF-5050', '2024-10-01 11:46:00+00', 'ROUTINE'),
    (1005, 'CS-NORFOLK', -58858, 'TRF-8780', '2024-12-11 02:40:00+00', 'ROUTINE'),
    (1006, 'MV-CALDER', 107219, 'TRF-7283', '2024-06-26 18:09:00+00', 'ROUTINE'),
    (1007, 'MV-SOREL', 124081, 'TRF-1475', '2024-12-31 13:51:00+00', 'ROUTINE'),
    (1008, 'CS-NORFOLK', 29842, 'TRF-0603', '2024-12-28 13:40:00+00', 'ROUTINE'),
    (1009, 'MV-CALDER', 4852, 'TRF-5327', '2025-01-06 02:15:00+00', 'ROUTINE'),
    (1010, 'MV-SOREL', 26195, 'TRF-7117', '2024-06-11 18:17:00+00', 'ROUTINE'),
    (1011, 'MSC-BANSHEE', 62752, 'TRF-4413', '2025-01-07 15:25:00+00', 'ROUTINE'),
    (1012, 'MSC-BANSHEE', 40657, 'TRF-3599', '2025-01-08 18:50:00+00', 'ROUTINE'),
    (1013, 'MV-CALDER', 43550, 'TRF-1968', '2025-01-04 12:19:00+00', 'KEEP-GAMMA'),
    (1014, 'CS-HEKTOR', 43950, 'TRF-0996', '2024-12-30 17:47:00+00', 'ROUTINE'),
    (1015, 'MV-TRITON', -8875, 'TRF-8675', '2025-01-06 14:54:00+00', 'ROUTINE'),
    (1016, 'MSC-ERIDANUS', -200, 'TRF-6760', '2024-12-29 06:35:00+00', 'ROUTINE');

INSERT INTO movements (move_id, position_id, delta_kg, moved_at) VALUES
    (1, 1002, -2700, '2024-12-05 10:13:00+00'),
    (2, 1002, 4275, '2024-12-19 15:02:00+00'),
    (3, 1002, 5750, '2024-12-22 05:08:00+00'),
    (4, 1003, -550, '2024-12-20 03:34:00+00'),
    (5, 1005, -4450, '2024-12-03 06:52:00+00'),
    (6, 1005, -3750, '2024-12-11 02:40:00+00'),
    (7, 1007, 5425, '2024-12-03 13:40:00+00'),
    (8, 1007, -1075, '2024-12-31 13:51:00+00'),
    (9, 1008, -700, '2024-12-12 09:03:00+00'),
    (10, 1008, 1550, '2024-12-28 13:40:00+00'),
    (11, 1009, 2525, '2024-12-19 07:22:00+00'),
    (12, 1009, -4600, '2024-12-29 10:42:00+00'),
    (13, 1009, 725, '2025-01-06 02:15:00+00'),
    (14, 1011, 1875, '2024-12-30 22:18:00+00'),
    (15, 1011, -1325, '2025-01-02 14:42:00+00'),
    (16, 1011, -4275, '2025-01-07 15:25:00+00'),
    (17, 1012, 5200, '2024-12-21 22:12:00+00'),
    (18, 1012, 4750, '2024-12-29 16:00:00+00'),
    (19, 1012, 4775, '2025-01-08 18:50:00+00'),
    (20, 1013, 44700, '2024-12-05 16:59:00+00'),
    (21, 1013, 800, '2024-12-23 11:57:00+00'),
    (22, 1013, -1950, '2025-01-04 12:19:00+00'),
    (23, 1014, 44675, '2024-12-07 01:33:00+00'),
    (24, 1014, -725, '2024-12-30 17:47:00+00'),
    (25, 1015, 8050, '2024-12-28 22:43:00+00'),
    (26, 1015, 1800, '2024-12-31 19:10:00+00'),
    (27, 1015, -975, '2025-01-06 14:54:00+00'),
    (28, 1016, 2425, '2024-12-24 04:46:00+00'),
    (29, 1016, -2225, '2024-12-29 06:35:00+00');

COMMIT;
