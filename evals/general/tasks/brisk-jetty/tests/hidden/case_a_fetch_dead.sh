#!/bin/bash
# Hidden case A — edge/malformed inputs for fetch.py.
# Fetching a dead/unreachable URL (or a malformed URL) must fail cleanly:
# non-zero exit, no error on stderr is fine, but the output file must NOT be
# created, truncated or modified.
set -u
OUT=/tmp/nysa_case_a.out
printf 'NYSA-CASE-A-SENTINEL\n' > "$OUT"

# 1) dead URL: a closed loopback port (nysa.test now resolves to 127.0.0.1)
python3 /app/fetch.py http://nysa.test:59991/live "$OUT" >/tmp/case_a1.log 2>&1
rc=$?
[ "$rc" -ne 0 ] || { echo "case_a: expected nonzero rc for dead URL, got 0" >&2; exit 1; }
[ "$(cat "$OUT")" = "NYSA-CASE-A-SENTINEL" ] || { echo "case_a: output file mutated on dead URL" >&2; exit 1; }

# 2) malformed URL (no scheme handled by urllib would raise too, but be explicit)
rm -f "$OUT"; printf 'NYSA-CASE-A-SENTINEL\n' > "$OUT"
python3 /app/fetch.py not-a-valid-url "$OUT" >/tmp/case_a2.log 2>&1
rc=$?
[ "$rc" -ne 0 ] || { echo "case_a: expected nonzero rc for malformed URL" >&2; exit 1; }
[ "$(cat "$OUT")" = "NYSA-CASE-A-SENTINEL" ] || { echo "case_a: output mutated on malformed URL" >&2; exit 1; }

# 3) no output file must be created when it did not exist
rm -f /tmp/nysa_case_a.never
python3 /app/fetch.py http://127.0.0.1:59992/nope /tmp/nysa_case_a.never >/tmp/case_a3.log 2>&1
rc=$?
[ "$rc" -ne 0 ] || { echo "case_a: expected nonzero rc (no file)" >&2; exit 1; }
[ -e /tmp/nysa_case_a.never ] && { echo "case_a: created output file on failure" >&2; exit 1; }

exit 0
