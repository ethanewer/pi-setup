#!/usr/bin/env python3
"""keelson-buoy verifier body.

Executed by tests/test.sh (which owns /logs/verifier/reward.txt). This file
performs every assertion and exits 0 only when all of them hold; test.sh
derives the binary reward from that exit status. None of the reward logic
lives here.

For every scenario (the visible 'main' cargoops instance plus the hidden
instances h1..h3) it:

  1. pins the seed and snapshot files by baked sha256, so tampering with
     either is a failure in itself;
  2. replays the deterministic seed into a scratch database to recompute
     the pristine pre-run state (row count, unrelated-column checksums,
     sentinel row set, journal checksum, column inventory, journal sums);
  3. runs the deliverable /app/repair.py against the live database with
     the scenario's snapshot path;
  4. asserts the overwritten column is fully reconciled against the
     snapshot + journal, and that everything else is bit-identical to the
     pristine state.

Destructive shortcuts — dropping/truncating the table, unscoped DELETE,
wholesale restore of the stale snapshot, writing any column other than the
damaged one, touching the journal — each violate at least one of the
pristine-state assertions below.
"""
import hashlib
import os
import re
import subprocess
import sys

PGBIN = '/usr/lib/postgresql/16/bin'
HOST, PORT = '127.0.0.1', 5432
DELIVERABLE = '/app/repair.py'
MAIN_DSN = 'postgresql://ops@127.0.0.1:5432/cargoops'

PINNED = {
    'main_seed': 'bf2ee33860e367be9e93b46a2fcc7ee6aec71f8772dd2b49a463164301d0d650',
    'main_backup': '4a7ea2c9f546fc30669e7b5c8b01fb2f186d351ebff8cb7050f460c37e98d6df',
    'h1_seed': '55478d68baecb01bb0a748ca11f0aa55d05ed166235ddecd32ab2cddeb40632d',
    'h1_backup': '68244120e1dfa27e615aec0dde754c434678c5f96563732f672a733c98025374',
    'h2_seed': '85a636ccb08c7d7ed02bdd01e52dab899e3e9454dc891a7e28483cdfc28892fd',
    'h2_backup': '72e93381700779209d53e1e772ba202ba2d17504660b742c445c81fe4968b81b',
    'h3_seed': '9bd4fa6cc872f816c1629c4b94da0706db9d637582a9e9f0ce846acab8b289eb',
    'h3_backup': '9f2088a5057faeaeb44e7fbc9724142d9a295dbfd444f3aedd77198b4c4a0913',
}

FAILS = []


def fail(msg):
    FAILS.append(msg)
    print('FAIL: ' + msg, flush=True)


def sha256_file(path):
    if not os.path.isfile(path):
        return None
    h = hashlib.sha256()
    with open(path, 'rb') as fh:
        for chunk in iter(lambda: fh.read(1 << 16), b''):
            h.update(chunk)
    return h.hexdigest()


def psql(db, sql):
    """Run one statement; return stdout lines (stripped)."""
    out = subprocess.run(
        [os.path.join(PGBIN, 'psql'), '-h', HOST, '-p', str(PORT),
         '-U', 'postgres', '-d', db, '-tA', '-q', '-c', sql],
        capture_output=True, text=True, timeout=90)
    if out.returncode != 0:
        return None
    return [ln for ln in out.stdout.splitlines() if ln.strip() != '']


def psql_file(db, path):
    out = subprocess.run(
        [os.path.join(PGBIN, 'psql'), '-h', HOST, '-p', str(PORT),
         '-U', 'postgres', '-d', db, '-v', 'ON_ERROR_STOP=1', '-q', '-f', path],
        capture_output=True, text=True, timeout=150)
    return out.returncode == 0


def createdb(name):
    subprocess.run([os.path.join(PGBIN, 'dropdb'), '--if-exists',
                    '-h', HOST, '-p', str(PORT), '-U', 'postgres', name],
                   capture_output=True, timeout=60)
    out = subprocess.run([os.path.join(PGBIN, 'createdb'),
                          '-h', HOST, '-p', str(PORT), '-U', 'postgres', '-O', 'postgres', name],
                         capture_output=True, text=True, timeout=90)
    return out.returncode == 0


def dropdb(name):
    subprocess.run([os.path.join(PGBIN, 'dropdb'), '--if-exists',
                    '-h', HOST, '-p', str(PORT), '-U', 'postgres', name],
                   capture_output=True, timeout=60)


def md5_rows(lines):
    h = hashlib.md5()
    for ln in lines or []:
        h.update(ln.encode('utf-8', 'replace'))
        h.update(b'\x1f')
    return h.hexdigest()


def unescape(v):
    if v == '\\N':
        return None
    out, i = [], 0
    while i < len(v):
        c = v[i]
        if c == '\\' and i + 1 < len(v):
            nxt = v[i + 1]
            if nxt == 't':
                out.append('\t'); i += 2; continue
            if nxt == 'n':
                out.append('\n'); i += 2; continue
            if nxt == 'r':
                out.append('\r'); i += 2; continue
            if nxt == '\\':
                out.append('\\'); i += 2; continue
        out.append(c)
        i += 1
    return ''.join(out)


def parse_snapshot(path):
    """(position_id -> cargo_kg) from the positions COPY block."""
    dump = {}
    with open(path, 'r', encoding='utf-8') as fh:
        in_copy = False
        for line in fh:
            line = line.rstrip('\n')
            if line.startswith('COPY ') and ' FROM stdin;' in line:
                m = re.match(r'COPY\s+([^\s(]+)\s*\(([^)]*)\)\s+FROM\s+stdin;', line)
                if m and m.group(1).split('.')[-1] == 'positions':
                    cols = [c.strip() for c in m.group(2).split(',')]
                    in_copy = ('cargo_kg' in cols and 'position_id' in cols)
                continue
            if in_copy:
                if line == '\\.':
                    in_copy = False
                    continue
                fields = [unescape(v) for v in line.split('\t')]
                if len(fields) >= len(cols):
                    pid = fields[cols.index('position_id')]
                    kg = fields[cols.index('cargo_kg')]
                    if pid is not None and kg is not None:
                        dump[int(pid)] = int(kg)
    return dump


def collect(db):
    """Pristine metrics for one database (replayed seed OR live)."""
    m = {}
    rows = psql(db, 'SELECT count(*) FROM positions')
    m['count'] = int(rows[0]) if rows else -1
    m['unrelated'] = md5_rows(psql(
        db, "SELECT position_id || '|' || vessel_code || '|' || tariff_code "
            "|| '|' || updated_at::text || '|' || seal_tag FROM positions "
            "ORDER BY position_id"))
    m['sentinels'] = psql(
        db, "SELECT position_id || '|' || vessel_code || '|' || cargo_kg "
            "|| '|' || tariff_code || '|' || updated_at::text || '|' || seal_tag "
            "FROM positions WHERE seal_tag LIKE 'KEEP-%' ORDER BY position_id") or []
    m['movements_md5'] = md5_rows(psql(
        db, "SELECT move_id || '|' || position_id || '|' || delta_kg "
            "|| '|' || moved_at::text FROM movements ORDER BY move_id"))
    m['columns'] = psql(
        db, "SELECT column_name || ':' || data_type FROM information_schema.columns "
            "WHERE table_schema = 'public' AND table_name = 'positions' "
            "ORDER BY ordinal_position") or []
    m['jsum'] = {}
    for ln in psql(db, 'SELECT position_id, COALESCE(SUM(delta_kg), 0) FROM movements GROUP BY position_id') or []:
        pid, _, s = ln.partition('|')
        try:
            m['jsum'][int(pid)] = int(s)
        except ValueError:
            pass
    return m


def scenario(name, seed_path, backup_path, live_db, dsn, pinned_seed, pinned_backup):
    print(f'=== scenario {name} (live db {live_db}) ===', flush=True)
    live_seeded = False

    if sha256_file(seed_path) != pinned_seed:
        fail(f'{name}: seed file hash mismatch (tampered or replaced)')
        return
    if sha256_file(backup_path) != pinned_backup:
        fail(f'{name}: snapshot file hash mismatch (tampered or replaced)')
        return

    # --- pristine replay: the deterministic pre-run state ---
    pdb = f'kbx_pristine_{name}'
    if createdb(pdb):
        if not psql_file(pdb, seed_path):
            fail(f'{name}: pristine replay of seed failed')
            dropdb(pdb)
            return
    else:
        fail(f'{name}: could not create pristine database')
        return

    pristine = collect(pdb)
    if pristine['count'] < 1:
        fail(f'{name}: pristine replay produced no rows')
        dropdb(pdb)
        return

    # --- live database ---
    if name == 'main':
        rows = psql(live_db, 'SELECT count(*) FROM positions')
        if rows is None:
            fail('main: cargoops positions table is unreadable (dropped?)')
            dropdb(pdb)
            return
    else:
        live_seeded = True
        if not createdb(live_db):
            fail(f'{name}: could not create scenario database')
            dropdb(pdb)
            return
        if not psql_file(live_db, seed_path):
            fail(f'{name}: seeding scenario database failed')
            dropdb(pdb)
            dropdb(live_db)
            return

    # --- deliverable runner (the tool must exist and run) ---
    def run_deliverable(label):
        if not os.path.isfile(DELIVERABLE):
            fail(f'{label}: deliverable {DELIVERABLE} missing')
            return False
        try:
            out = subprocess.run(
                ['python3', DELIVERABLE, dsn, backup_path],
                capture_output=True, text=True, timeout=90)
            if out.returncode != 0:
                fail(f'{label}: deliverable exited {out.returncode}: '
                     f'{(out.stderr or out.stdout).strip()[:200]}')
                return False
        except subprocess.TimeoutExpired:
            fail(f'{label}: deliverable timed out (>90s)')
            return False
        return True

    dump = parse_snapshot(backup_path)

    def assert_reconciled(label):
        bad = []
        for ln in psql(live_db, 'SELECT position_id, cargo_kg FROM positions ORDER BY position_id') or []:
            pid, _, stored = ln.partition('|')
            try:
                pid = int(pid)
                stored = int(stored)
            except ValueError:
                fail(f'{label}: unreadable row {ln!r}')
                continue
            expected = dump.get(pid, 0) + pristine['jsum'].get(pid, 0)
            if stored != expected:
                bad.append((pid, stored, expected))
        if bad:
            shown = ', '.join(f'{p}:{s}!={e}' for p, s, e in bad[:5])
            fail(f'{label}: {len(bad)} row(s) not reconciled with snapshot+journal '
                 f'(first: {shown})')

    def assert_pristine(live, label):
        if live['count'] != pristine['count']:
            fail(f'{label}: row count changed ({live["count"]} vs pristine '
                 f'{pristine["count"]}) — rows were added, removed, or restored stale')
        if live['unrelated'] != pristine['unrelated']:
            fail(f'{label}: unrelated columns differ from the pre-run state — '
                 'something other than the damaged cells was modified')
        if live['sentinels'] != pristine['sentinels']:
            fail(f'{label}: sentinel (seal-tagged) row set differs from the '
                 'pre-run state')
        if live['movements_md5'] != pristine['movements_md5']:
            fail(f'{label}: change-journal table was modified')
        if live['columns'] != pristine['columns']:
            fail(f'{label}: column inventory changed')

    def cleanup():
        dropdb(pdb)
        if live_seeded:
            dropdb(live_db)

    # --- first run + full assertions against the pristine state ---
    if not run_deliverable(name):
        cleanup()
        return
    live = collect(live_db)
    if live['count'] < 1:
        fail(f'{name}: positions table unreadable or empty after repair')
        cleanup()
        return
    assert_reconciled(name)
    assert_pristine(live, name)

    # --- second run: the tool must be idempotent (the stated output
    # contract); a repair that re-applies deltas or rewrites state on a
    # re-run changes one of the pristine metrics or breaks reconciliation ---
    if not run_deliverable(f'{name} (idempotence re-run)'):
        cleanup()
        return
    live2 = collect(live_db)
    if live2['count'] < 1:
        fail(f'{name}: positions table unreadable or empty after re-run')
        cleanup()
        return
    assert_reconciled(f'{name} (idempotence re-run)')
    for key in ('count', 'unrelated', 'sentinels', 'movements_md5',
                'columns', 'jsum'):
        if live2[key] != live[key]:
            fail(f'{name}: not idempotent — {key} changed on the second run')
    assert_pristine(live2, f'{name} (idempotence re-run)')

    cleanup()
    print(f'=== scenario {name}: assertions complete ===', flush=True)


def main():
    # Bring the scenario up (idempotent): ensures the server is running and
    # seeds cargoops exactly once if nobody else did.
    up = subprocess.run(['/opt/cargoctl/pgctl.sh', 'up'],
                        capture_output=True, text=True, timeout=180)
    if up.returncode != 0:
        fail('infra: pgctl up failed — postgres not available')
        print(up.stderr[-500:], file=sys.stderr)

    scenario('main', '/opt/cargoctl/seed_cargoops.sql',
             '/app/backups/cargoops_base_20241130.sql', 'cargoops', MAIN_DSN,
             PINNED['main_seed'], PINNED['main_backup'])
    for h in ('h1', 'h2', 'h3'):
        scenario(h, f'/tests/hidden/{h}/seed.sql', f'/tests/hidden/{h}/backup.sql',
                 f'kbx_{h}', f'postgresql://ops@127.0.0.1:5432/kbx_{h}',
                 PINNED[f'{h}_seed'], PINNED[f'{h}_backup'])

    print(flush=True)
    if FAILS:
        print(f'keelson-buoy verifier FAILED with {len(FAILS)} assertion(s)', flush=True)
        return 1
    print('keelson-buoy verifier: all scenarios passed', flush=True)
    return 0


if __name__ == '__main__':
    sys.exit(main())