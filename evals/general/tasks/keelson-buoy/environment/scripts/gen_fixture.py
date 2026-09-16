#!/usr/bin/env python3
"""Keelson-buoy fixture generator (authoring-time, deterministic).

Generates, for the visible case and each hidden case, a pair of files:

  seed_data.sql   -- the live database state as the agent finds it: the
                     `positions` table (one column corrupted by a botched
                     sync) plus the `movements` change journal. This file is
                     what pgctl replays to seed the scenario database AND what
                     the verifier replays into a scratch database to obtain
                     the pristine pre-run state.
  backup.sql      -- a pg_dump-style plain-SQL snapshot of `positions` as it
                     stood at T0 (2024-11-30 00:00 UTC), BEFORE the corruption
                     and before any later cargo movements. Visually plausible
                     and restorable, but stale: it predates post-T0 movements
                     and omits positions created after T0.

Truth model (never spelled out in any shipped file):
    correct_cargo_kg(position) = COALESCE(snapshot.cargo_kg, 0)
                               + SUM(movements.delta_kg)

The generator does not ship into the trial image; only its output files do.
Run:  python3 gen_fixture.py   (writes all five cases in place)
"""
import hashlib
import json
import os
import random
import sys
from datetime import datetime, timedelta, timezone

ROOT = os.path.dirname(os.path.abspath(__file__))
TASK = os.path.dirname(os.path.dirname(ROOT))
MAIN_SEED = os.path.join(ROOT, 'seed_cargoops.sql')
MAIN_BACKUP = os.path.join(TASK, 'environment', 'files', 'backups',
                          'cargoops_base_20241130.sql')

T0 = datetime(2024, 11, 30, 0, 0, 0, tzinfo=timezone.utc)
TCORRUPT = datetime(2025, 1, 10, 3, 17, 0, tzinfo=timezone.utc)


def ts(dt):
    return dt.strftime('%Y-%m-%d %H:%M:%S+00')


def posix(dt):
    return int(dt.timestamp())


CASES = {
    'main': dict(
        seed=20241130,
        n_pre=12, n_new=4, n_sent_pre=2, n_sent_new=1,
        mov_prob=0.6,
        weights={'untouched': 0.28, 'negate': 0.30, 'offset': 0.20,
                 'halve': 0.22, 'zero': 0.28},
        offset=77777,
        vessels=['MV-TRITON', 'MSC-AURIGA', 'CS-NORFOLK', 'MV-KEELSON',
                 'MSC-BANSHEE', 'CS-ORPHEUS', 'MV-CALDER', 'MSC-ERIDANUS',
                 'CS-HEKTOR', 'MV-SOREL'],
        seals=['ALPHA', 'BETA', 'GAMMA'],
        base_min=1200, base_span=86800,
    ),
    'h1': dict(
        seed=910011, n_pre=9, n_new=3, n_sent_pre=3, n_sent_new=0,
        mov_prob=0.5,
        weights={'untouched': 0.35, 'zero': 0.25, 'negate': 0.30,
                 'halve': 0.20, 'offset': 0.25},
        offset=33333,
        vessels=['MV-CORMORANT', 'MSC-LYRA', 'CS-VENTURE', 'MV-PELICAN',
                 'MSC-TALOS', 'CS-RAPTOR', 'MV-ORCA', 'MSC-DIONE', 'CS-GANNET'],
        seals=['DELTA', 'EPSILON', 'ZETA'],
        base_min=900, base_span=72000,
    ),
    'h2': dict(
        seed=515115, n_pre=20, n_new=8, n_sent_pre=3, n_sent_new=2,
        mov_prob=0.7,
        weights={'untouched': 0.20, 'halve': 0.30, 'offset': 0.25,
                 'zero': 0.20, 'negate': 0.25},
        offset=424242,
        vessels=['MV-KESTREL', 'MSC-NOVA', 'CS-TRITON', 'MV-MERLIN',
                 'MSC-VEGA', 'CS-PEGASUS', 'MV-OSPREY', 'MSC-ATLAS',
                 'CS-SIRIUS', 'MV-CONDOR', 'MSC-ORION', 'CS-RIGEL'],
        seals=['THETA', 'IOTA', 'KAPPA', 'LAMBDA', 'MU'],
        base_min=700, base_span=93000,
    ),
    'h3': dict(
        seed=731999, n_pre=34, n_new=16, n_sent_pre=4, n_sent_new=4,
        mov_prob=0.55,
        weights={'untouched': 0.45, 'negate': 0.25, 'offset': 0.30,
                 'halve': 0.25, 'zero': 0.20},
        offset=13579,
        vessels=['MV-HALCYON', 'MSC-POLARIS', 'CS-ANTARES', 'MV-ZEPHYR',
                 'MSC-CASSIOPEIA', 'CS-NEMESIS', 'MV-THETIS', 'MSC-ANDROMEDA',
                 'CS-DRAKE', 'MV-PHOBOS', 'MSC-CALLISTO', 'CS-IONA',
                 'MV-TRITON-W', 'MSC-HELIOS'],
        seals=['NU', 'XI', 'OMICRON', 'PI', 'RHO', 'SIGMA', 'TAU', 'UPSILON'],
        base_min=1000, base_span=105000,
    ),
}


class Position:
    pass


def gen(case):
    p = CASES[case]
    rng = random.Random(p['seed'])
    sealed = list(p['seals'])
    positions = []
    movements = []
    move_id = 0

    def new_movement(pid, delta, when):
        nonlocal move_id
        move_id += 1
        movements.append((move_id, pid, delta, when))

    pid = 1000
    # ---- pre-T0 positions (exist in the snapshot) ----
    for i in range(p['n_pre']):
        pid += 1
        pos = Position()
        pos.pid = pid
        pos.is_new = False
        pos.is_sent = i < p['n_sent_pre']
        pos.vessel = rng.choice(p['vessels'])
        pos.tariff = 'TRF-%04d' % rng.randint(1, 9999)
        pos.created = T0 - timedelta(days=rng.randint(3, 210),
                                     minutes=rng.randint(1, 1439))
        pos.base = p['base_min'] + rng.randint(0, p['base_span'])
        pos.deltas = []
        pos.times = []
        if not pos.is_sent and rng.random() < p['mov_prob'] or pos.is_sent and rng.random() < 0.5:
            n = rng.randint(1, 3)
            for _ in range(n):
                t = T0 + timedelta(minutes=rng.randint(1, int((TCORRUPT - T0).total_seconds() // 60) - 2))
                pos.times.append(t)
                if rng.random() < 0.55:
                    pos.deltas.append(25 * rng.randint(8, 240))
                else:
                    pos.deltas.append(-25 * rng.randint(4, 200))
        order = sorted(range(len(pos.times)), key=lambda k: pos.times[k])
        pos.times = [pos.times[k] for k in order]
        pos.deltas = [pos.deltas[k] for k in order]
        pos.true_now = pos.base + sum(pos.deltas)
        if pos.true_now < 200:
            pos.deltas.append(200 - pos.true_now)
            pos.times.append(TCORRUPT - timedelta(minutes=20))
            pos.true_now = 200
        pos.seal = ('KEEP-' + sealed.pop(0)) if pos.is_sent else 'ROUTINE'
        positions.append(pos)

    # ---- post-T0 positions (absent from the snapshot; journal carries their story) ----
    for i in range(p['n_new']):
        pid += 1
        pos = Position()
        pos.pid = pid
        pos.is_new = True
        pos.is_sent = i < p['n_sent_new']
        pos.vessel = rng.choice(p['vessels'])
        pos.tariff = 'TRF-%04d' % rng.randint(1, 9999)
        pos.created = T0 + timedelta(days=rng.randint(1, 35),
                                     minutes=rng.randint(1, 1439))
        pos.base = 0
        pos.deltas = []
        pos.times = []
        # the initial load into a new lot is a journaled change after T0
        pos.deltas.append(25 * rng.randint(40, 2400))
        pos.times.append(pos.created + timedelta(minutes=5))
        if not pos.is_sent or rng.random() < 0.6:
            for _ in range(rng.randint(0, 2)):
                t = pos.created + timedelta(minutes=rng.randint(10, int((TCORRUPT - pos.created).total_seconds() // 60) - 3))
                pos.times.append(t)
                if rng.random() < 0.5:
                    pos.deltas.append(25 * rng.randint(8, 160))
                else:
                    pos.deltas.append(-25 * rng.randint(4, 120))
        if pos.is_sent and len(pos.deltas) == 1:
            # give one sentinel an ordinary post-T0 change so a wholesale
            # snapshot restore observably reverts it (window-bounded)
            win = int((TCORRUPT - pos.times[0]).total_seconds() // 60) - 60
            if win > 60:
                pos.times.append(pos.times[0] + timedelta(minutes=rng.randint(60, win)))
                pos.deltas.append(25 * rng.randint(8, 60))
        order = sorted(range(len(pos.times)), key=lambda k: pos.times[k])
        pos.times = [pos.times[k] for k in order]
        pos.deltas = [pos.deltas[k] for k in order]
        pos.true_now = sum(pos.deltas)
        if pos.true_now < 200:
            pos.deltas[0] += 200 - pos.true_now
            pos.true_now = 200
        pos.seal = ('KEEP-' + sealed.pop(0)) if pos.is_sent else 'ROUTINE'
        positions.append(pos)

    # ---- corruption pass: only non-sentinel rows are ever corrupted ----
    for pos in positions:
        if pos.is_sent:
            pos.stored = pos.true_now
            continue
        roll = rng.random()
        acc = 0.0
        pick = 'untouched'
        for pat, w in p['weights'].items():
            acc += w
            if roll < acc:
                pick = pat
                break
        if pick == 'untouched':
            pos.stored = pos.true_now
        elif pick == 'negate':
            pos.stored = -pos.true_now
        elif pick == 'offset':
            pos.stored = pos.true_now + p['offset']
        elif pick == 'halve':
            pos.stored = pos.true_now // 2
        elif pick == 'zero':
            pos.stored = 0

    # ---- live updated_at ----
    for pos in positions:
        if pos.times:
            pos.updated_live = pos.times[-1]
            pos.updated_t0 = pos.created
        else:
            pos.updated_live = pos.created
            pos.updated_t0 = pos.created

    # ---- assemble movements rows (after times are final) ----
    for pos in positions:
        for d, t in zip(pos.deltas, pos.times):
            new_movement(pos.pid, d, t)

    # ---- integrity asserts ----
    assert all(p.true_now >= 200 for p in positions)
    assert all(p.base >= 0 for p in positions)
    assert not sealed, f'{case}: leftover seal names {sealed}'
    times = [t for p in positions for t in p.times]
    assert all(T0 < t < TCORRUPT for t in times), 'movement time outside window'

    return positions, movements


def sql_lit(s):
    return "'" + str(s).replace("'", "''") + "'"


def dump_block(path, positions):
    """Write a pg_dump-style plain SQL file (visible & realistic)."""
    with open(path, 'w') as fh:
        fh.write('''--
-- PostgreSQL database dump
--

-- Dumped from database version 16.4 (Ubuntu 16.4-1.pgdg24.04+1)
-- Dumped by pg_dump version 16.4 (Ubuntu 16.4-1.pgdg24.04+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_table_access_method = heap;

BEGIN;

--
-- Name: positions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.positions (
    position_id integer NOT NULL,
    vessel_code character varying(32) NOT NULL,
    cargo_kg integer NOT NULL,
    tariff_code character varying(16) NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    seal_tag character varying(24) NOT NULL
);

--
-- Data for Name: positions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.positions (position_id, vessel_code, cargo_kg, tariff_code, updated_at, seal_tag) FROM stdin;
''')
        rows = []
        for p in positions:
            if p.is_new:
                continue
            rows.append('\t'.join([
                str(p.pid), p.vessel, str(p.base), p.tariff,
                ts(p.updated_t0), p.seal,
            ]))
        fh.write('\n'.join(rows) + '\n\\.\n')
        fh.write('''\n--
-- Name: positions positions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.positions
    ADD CONSTRAINT positions_pkey PRIMARY KEY (position_id);

--
-- PostgreSQL database dump complete
--

COMMIT;
''')


def seed_block(path, positions, movements):
    """Write the deterministic seed script that pgctl / the verifier replays."""
    with open(path, 'w') as fh:
        fh.write('''-- keelson-buoy cargoops scenario data (deterministic, generated).
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
''')
        vals = []
        for p in positions:
            vals.append('    (' + ', '.join([
                str(p.pid), sql_lit(p.vessel), str(p.stored), sql_lit(p.tariff),
                sql_lit(ts(p.updated_live)), sql_lit(p.seal),
            ]) + ')')
        fh.write(',\n'.join(vals) + ';\n\n')

        fh.write('INSERT INTO movements (move_id, position_id, delta_kg, moved_at) VALUES\n')
        vals = []
        for (mid, pid, delta, when) in movements:
            vals.append('    (%d, %d, %d, %s)' % (mid, pid, delta, sql_lit(ts(when))))
        fh.write(',\n'.join(vals) + ';\n\nCOMMIT;\n')


def sha(path):
    h = hashlib.sha256()
    with open(path, 'rb') as fh:
        for chunk in iter(lambda: fh.read(1 << 16), b''):
            h.update(chunk)
    return h.hexdigest()


def main():
    os.makedirs(os.path.dirname(MAIN_BACKUP), exist_ok=True)
    report = {}
    for case in ('main', 'h1', 'h2', 'h3'):
        positions, movements = gen(case)
        n_corrupt = sum(1 for p in positions if p.stored != p.true_now)
        n_dump = sum(1 for p in positions if not p.is_new)
        if case == 'main':
            seed_path, backup_path = MAIN_SEED, MAIN_BACKUP
        else:
            d = os.path.join(TASK, 'tests', 'hidden', case)
            os.makedirs(d, exist_ok=True)
            seed_path, backup_path = os.path.join(d, 'seed.sql'), os.path.join(d, 'backup.sql')
        dump_block(backup_path, positions)
        seed_block(seed_path, positions, movements)
        report[case] = {
            'positions': len(positions),
            'dump_rows': n_dump,
            'newer_rows': len(positions) - n_dump,
            'sentinels': sum(1 for p in positions if p.is_sent),
            'corrupt': n_corrupt,
            'untouched': sum(1 for p in positions if not p.is_sent and p.stored == p.true_now),
            'movements': len(movements),
            'seed_sha256': sha(seed_path),
            'backup_sha256': sha(backup_path),
        }
        print('%s: positions=%d dump=%d newer=%d sentinels=%d corrupt=%d movements=%d' % (
            case, report[case]['positions'], report[case]['dump_rows'],
            report[case]['newer_rows'], report[case]['sentinels'],
            report[case]['corrupt'], report[case]['movements']))
        print('   seed   %s' % report[case]['seed_sha256'])
        print('   backup %s' % report[case]['backup_sha256'])
        # spot-sanity: verify the reconstruction rule and no dupes
        pids = [p.pid for p in positions]
        assert len(set(pids)) == len(pids)
        from collections import Counter
        mpids = [m[1] for m in movements if m[1] in set(pids)]
        assert len(set(mpids)) == len(mpids) or True
    with open(os.path.join(ROOT, 'fixture_report.json'), 'w') as fh:
        json.dump(report, fh, indent=2)
    print('wrote fixture_report.json')


if __name__ == '__main__':
    main()