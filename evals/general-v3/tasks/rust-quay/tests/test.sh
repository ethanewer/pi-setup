#!/bin/bash
# Verifier for rust-quay: guards the no-modify rule on the supplied /app
# inputs, checks the visible deliverables (/app/quay.db-wal, /app/secrets.json),
# and EXECUTES the deliverable tool (/app/dewal.py) decode+extract on the
# visible case and on every hidden case in /tests/hidden. Writes REWARD (0/1)
# to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

PRISTINE_DB_SHA="a209ba85773882b79b8147779c406fbb67a12dcb723ba7c4ea7ca3168e651cc8"
PRISTINE_ENC_SHA="351c7412afdb162093a58491973fd61299f02f4fbcb8e5b7c907364858dc1f28"

no_modify_broken=0
for pair in "/app/quay.db:$PRISTINE_DB_SHA" "/app/quay.db-wal.enc:$PRISTINE_ENC_SHA"; do
    path="${pair%%:*}"
    want="${pair#*:}"
    if [ ! -f "$path" ]; then
        echo "no-modify: $path missing" >&2
        no_modify_broken=1
    else
        actual="$(sha256sum "$path" | awk '{print $1}')"
        if [ "$actual" != "$want" ]; then
            echo "no-modify: $path was modified" >&2
            no_modify_broken=1
        fi
    fi
done

python3 - "$no_modify_broken" <<'PY'
import json, os, shutil, sqlite3, struct, subprocess, sys, tempfile

TOOL = "/app/dewal.py"
WAL_MAGICS = (b"\x37\x7f\x06\x82", b"\x37\x7f\x06\x83")
no_modify_broken = int(sys.argv[1])
failures = []

if no_modify_broken:
    failures.append("supplied /app inputs modified or missing")


def read_bytes(p):
    with open(p, "rb") as f:
        return f.read()


def wal_sane(wal):
    if len(wal) < 32 or wal[0:4] not in WAL_MAGICS:
        return False
    version, page_size = struct.unpack_from(">II", wal, 4)
    if version != 3007000:
        return False
    if page_size < 512 or page_size > 65536 or (page_size & (page_size - 1)):
        return False
    return True


def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=120)


def extract_rows(tool, db_copy, wal_bytes, out_json):
    """Copy db+wal to a temp dir, run `extract`, return parsed JSON."""
    tmp = tempfile.mkdtemp(prefix="quay-verify-")
    try:
        wdb = os.path.join(tmp, "case.db")
        shutil.copy(db_copy, wdb)
        if wal_bytes is not None:
            with open(wdb + "-wal", "wb") as f:
                f.write(wal_bytes)
        r = run([sys.executable, TOOL, "extract", wdb, out_json])
        if r.returncode != 0:
            return None
        with open(out_json) as f:
            return json.load(f)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def load_json(p):
    with open(p) as f:
        return json.load(f)


if not os.path.isfile(TOOL):
    failures.append("missing /app/dewal.py")
else:
    # --- visible case: EXECUTE decode on the live supplied input ---
    r = run([sys.executable, TOOL, "decode",
             "/app/quay.db-wal.enc", "/tmp/quay_vis_wal"])
    if r.returncode != 0:
        failures.append("visible decode run failed")
    else:
        got = read_bytes("/tmp/quay_vis_wal")
        want = read_bytes("/tests/expected/wal.ref")
        if got != want:
            failures.append("visible decoded WAL bytes mismatch")
        if not wal_sane(got):
            failures.append("visible decoded WAL header not sane")

    # --- visible deliverable: /app/quay.db-wal ---
    if not os.path.isfile("/app/quay.db-wal"):
        failures.append("missing /app/quay.db-wal")
    elif read_bytes("/app/quay.db-wal") != read_bytes("/tests/expected/wal.ref"):
        failures.append("/app/quay.db-wal does not match reference WAL")
    elif not wal_sane(read_bytes("/app/quay.db-wal")):
        failures.append("/app/quay.db-wal header not sane")

    # --- visible deliverable: /app/secrets.json (and tool extract agrees) ---
    want_rows = load_json("/tests/expected/secrets.json")
    got_rows = None
    if os.path.isfile("/app/secrets.json"):
        try:
            got_rows = load_json("/app/secrets.json")
        except Exception:
            failures.append("/app/secrets.json unreadable")
    else:
        failures.append("missing /app/secrets.json")
    if got_rows is not None and got_rows != want_rows:
        failures.append("/app/secrets.json does not match expected rows")
    tmp_json = "/tmp/quay_vis_extract.json"
    extracted = extract_rows(TOOL, "/app/quay.db",
                             read_bytes("/tests/expected/wal.ref"), tmp_json)
    if extracted is None:
        failures.append("visible extract run failed")
    elif extracted != want_rows:
        failures.append("visible extract output mismatch")

    # --- hidden cases ---
    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(os.listdir(hidden_dir))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden_dir, c)
            db = os.path.join(base, "db.bin")
            enc = os.path.join(base, "wal.enc")
            ref = os.path.join(base, "decoded.ref")
            rows = os.path.join(base, "rows.json")
            if not all(os.path.isfile(p) for p in (db, enc, ref, rows)):
                failures.append("hidden '%s' malformed" % c)
                continue
            out_wal = "/tmp/quay_%s_wal" % c
            r = run([sys.executable, TOOL, "decode", enc, out_wal])
            if r.returncode != 0:
                failures.append("hidden '%s': decode failed" % c)
                continue
            got = read_bytes(out_wal)
            if got != read_bytes(ref):
                failures.append("hidden '%s': decoded WAL mismatch" % c)
                continue
            if not wal_sane(got):
                failures.append("hidden '%s': decoded WAL header not sane" % c)
                continue
            out_json = "/tmp/quay_%s_rows.json" % c
            extracted = extract_rows(TOOL, db, got, out_json)
            if extracted is None:
                failures.append("hidden '%s': extract failed" % c)
            elif extracted != load_json(rows):
                failures.append("hidden '%s': extract output mismatch" % c)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
