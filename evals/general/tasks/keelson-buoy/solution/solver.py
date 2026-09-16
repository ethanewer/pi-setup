#!/usr/bin/env python3
"""CargoOps data repair tool (keelson-buoy reference implementation).

Usage:
    repair.py DSN BACKUP_SQL

  DSN        a postgresql:// connection string to the target database
  BACKUP_SQL path to a pg_dump-style plain-SQL snapshot of the `positions`
             table taken before the corruption

The tool discovers the corruption itself: the `positions` table's cargo
column carries values that were overwritten by a bad sync job. The correct
value of each row is recoverable from records already present in the
database: the pre-corruption snapshot (the cargo as of the snapshot moment)
combined with the change journal (`movements`), which records every signed
cargo delta applied since that snapshot, keyed by position_id.

    correct_cargo_kg = COALESCE(snapshot.cargo_kg, 0)
                       + COALESCE(SUM(movements.delta_kg), 0)

Rows absent from the snapshot were created after it and their whole story
lives in the journal. Rows in the snapshot that never moved simply keep
their snapshot value. The repair therefore:

  1. parses the snapshot COPY block (no dependency on the file format
     beyond pg_dump's documented plain output; the header/trailer are
     ignored),
  2. loads it into a temporary table in the target database,
  3. recomputes every row's correct cargo from the snapshot and the
     journal, and
  4. applies a single UPDATE that touches ONLY the cargo column and only
     the rows whose stored value differs.

It is idempotent: a second run finds every row already correct and changes
nothing. It must never drop, truncate, delete, insert into, or restore
over `positions`, and never modify `movements`; those would destroy the
very records the repair is built on. Only the standard library and
psycopg2 are used; no files other than the two CLI arguments are read.
"""
import re
import sys

import psycopg2

POSITIONS = 'positions'
MOVEMENTS = 'movements'
CARGO = 'cargo_kg'


def unescape(v):
    """Undo pg_dump's COPY escaping for a single field."""
    if v == '\\N':
        return None
    out = []
    i = 0
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
    """Return (columns, rows) from the COPY block of a pg_dump plain dump."""
    cols = None
    rows = []
    with open(path, 'r', encoding='utf-8') as fh:
        in_copy = False
        for line in fh:
            line = line.rstrip('\n')
            if line.startswith('COPY ') and ' FROM stdin;' in line:
                m = re.match(r'COPY\s+([^\s(]+)\s*\(([^)]*)\)\s+FROM\s+stdin;', line)
                if m:
                    table = m.group(1).split('.')[-1]
                    if table == POSITIONS:
                        cols = [c.strip() for c in m.group(2).split(',')]
                        in_copy = True
                continue
            if in_copy:
                if line == '\\.':
                    in_copy = False
                    continue
                rows.append([unescape(v) for v in line.split('\t')])
    if cols is None:
        raise RuntimeError(f'no {POSITIONS} COPY block found in {path}')
    return cols, rows


def main():
    if len(sys.argv) != 3:
        print('usage: repair.py DSN BACKUP_SQL', file=sys.stderr)
        return 2
    dsn, backup = sys.argv[1], sys.argv[2]

    cols, rows = parse_snapshot(backup)
    if cols[0] != 'position_id' or CARGO not in cols:
        print(f'snapshot columns unexpected: {cols}', file=sys.stderr)
        return 3
    si_id = cols.index('position_id')
    si_kg = cols.index(CARGO)

    conn = psycopg2.connect(dsn)
    try:
        with conn.cursor() as cur:
            cur.execute(
                'CREATE TEMP TABLE snapshot_mirror '
                '(position_id integer PRIMARY KEY, cargo_kg integer) '
                'ON COMMIT DROP'
            )
            cur.executemany(
                'INSERT INTO snapshot_mirror (position_id, cargo_kg) VALUES (%s, %s)',
                [(int(r[si_id]), int(r[si_kg])) for r in rows
                 if r[si_id] is not None and r[si_kg] is not None],
            )

            # --- reconcile every live row against snapshot + journal ---
            cur.execute(
                f"""
                SELECT p.position_id,
                       COALESCE(s.cargo_kg, 0) + COALESCE(m.total_delta, 0) AS expected
                  FROM {POSITIONS} p
                  LEFT JOIN snapshot_mirror s ON s.position_id = p.position_id
                  LEFT JOIN (
                      SELECT position_id, SUM(delta_kg) AS total_delta
                        FROM {MOVEMENTS}
                       GROUP BY position_id
                  ) m ON m.position_id = p.position_id
                """
            )
            expected = cur.fetchall()
            if not expected:
                print('fatal: no rows to reconcile', file=sys.stderr)
                conn.rollback()
                return 4

            cur.execute(
                f"""
                UPDATE {POSITIONS} p
                   SET {CARGO} = e.expected
                  FROM (VALUES
                    {','.join('(%s, %s)' for _ in expected)}
                  ) AS e(position_id, expected)
                 WHERE p.position_id = e.position_id
                   AND p.{CARGO} IS DISTINCT FROM e.expected
                """,
                [v for pair in expected for v in pair],
            )
            fixed = cur.rowcount

            # --- proof: after the update nothing may disagree anymore ---
            cur.execute(
                f"""
                SELECT count(*)
                  FROM {POSITIONS} p
                  LEFT JOIN snapshot_mirror s ON s.position_id = p.position_id
                  LEFT JOIN (
                      SELECT position_id, SUM(delta_kg) AS total_delta
                        FROM {MOVEMENTS}
                       GROUP BY position_id
                  ) m ON m.position_id = p.position_id
                 WHERE p.{CARGO} IS DISTINCT FROM
                       (COALESCE(s.cargo_kg, 0) + COALESCE(m.total_delta, 0))
                """
            )
            leftover = cur.fetchone()[0]
            conn.commit()

        print(f'repair complete: {fixed} rows corrected, {leftover} remaining '
              f'mismatches, {len(rows)} snapshot rows read')
        return 0 if leftover == 0 else 5
    finally:
        conn.close()


if __name__ == '__main__':
    sys.exit(main())