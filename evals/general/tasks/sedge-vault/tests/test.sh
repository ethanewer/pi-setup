#!/bin/bash
# Verifier for sedge-vault: checks the visible-case deliverables, enforces the
# no-modify rule on the supplied stack file, EXECUTES /app/export.py on the
# visible stack and on every hidden stack file in /tests/hidden (provisioning
# each hidden database scenario on the live instance first), and writes the
# REWARD (0/1) to /logs/verifier/reward.txt on every exit path.
set -u

mkdir -p /logs/verifier
printf 0 > /logs/verifier/reward.txt

overall=1
finalize_reward() {
  if [ "${overall:-0}" = "1" ]; then
    printf 1 > /logs/verifier/reward.txt
  else
    printf 0 > /logs/verifier/reward.txt
  fi
}
trap 'finalize_reward' EXIT

python3 - <<'PY'
import glob
import hashlib
import json
import os
import re
import subprocess
import sys

failures = []

PSQL = None
for hit in sorted(glob.glob("/usr/lib/postgresql/*/bin/psql")):
    PSQL = hit
if PSQL is None:
    PSQL = "psql"

HOST = "127.0.0.1"
PORT = "5541"
CURATOR_USER = "curator"
CURATOR_PASS = "Fenwick-Alder-914"
STACK = "/app/archive/stack.yaml"
EXPORT = "/app/export.py"
SPECIMENS = "/app/specimens.json"

PRISTINE_STACK_SHA = "55d3ff8c5e36e5312ac7ac0b112fdbd996c9ff1ce7e6225111f88809126fb7bc"

# ---- no-modify guard on the supplied visible stack file ---------------------
if not os.path.isfile(STACK):
    failures.append("no-modify: %s missing" % STACK)
else:
    actual = hashlib.sha256(open(STACK, "rb").read()).hexdigest()
    if actual != PRISTINE_STACK_SHA:
        failures.append("no-modify: %s was modified" % STACK)


def psql(user, password, db, *args, timeout=45):
    env = dict(os.environ)
    env["PGPASSWORD"] = password
    return subprocess.run(
        [PSQL, "-h", HOST, "-p", PORT, "-U", user, "-d", db,
         "-v", "ON_ERROR_STOP=1", "-tA"] + list(args),
        capture_output=True, text=True, timeout=timeout, env=env)


def parse_stack(path):
    """Derive (port, user, password, db) from a compose-style stack file."""
    text = open(path, encoding="utf-8").read()

    def envval(key):
        m = re.search(r"^\s*%s\s*:\s*(.*)$" % key, text, re.M)
        if not m:
            raise ValueError("missing %s" % key)
        v = m.group(1).strip()
        if len(v) >= 2 and v[0] == '"' and v[-1] == '"':
            v = v[1:-1]
        return v

    db = envval("POSTGRES_DB")
    user = envval("POSTGRES_USER")
    pw = envval("POSTGRES_PASSWORD")
    m = re.search(r'^\s*-\s*"?(\d+)\s*:\s*5432"?\s*$', text, re.M)
    if not m:
        raise ValueError("missing port mapping")
    return m.group(1), user, pw, db


def norm_export(obj):
    assert isinstance(obj, list), "export must be a JSON array"
    rows = []
    for row in obj:
        assert isinstance(row, dict), "each export row must be an object"
        assert set(row.keys()) == {
            "catalog_code", "species", "quadrant", "collected_at", "mass_g"
        }, row.keys()
        rows.append((
            str(row["catalog_code"]), str(row["species"]), str(row["quadrant"]),
            str(row["collected_at"]), int(row["mass_g"]),
        ))
    return sorted(rows)


def run_export(stack, out):
    if os.path.exists(out):
        os.remove(out)
    try:
        r = subprocess.run([sys.executable, EXPORT, stack, out],
                           capture_output=True, text=True, timeout=120)
    except Exception as exc:
        failures.append("export run raised: %s" % exc)
        return False
    if r.returncode != 0 or not os.path.exists(out):
        failures.append("export run failed (rc=%s)" % r.returncode)
        return False
    return True


def export_matches(stack, expected_path, label):
    out = "/tmp/sedge_vault_export.json"
    if not run_export(stack, out):
        return
    try:
        with open(out, encoding="utf-8") as fh:
            got = json.load(fh)
        with open(expected_path, encoding="utf-8") as fh:
            want = json.load(fh)
        if norm_export(got) != norm_export(want):
            failures.append("%s: export content mismatch" % label)
    except Exception as exc:
        failures.append("%s: export unreadable/invalid: %s" % (label, exc))


# ---- deliverables exist ------------------------------------------------------
if not os.path.isfile(EXPORT):
    failures.append("missing /app/export.py")
else:
    # --- visible case: execute the deliverable on the supplied stack file ---
    export_matches(STACK, "/tests/expected.json", "visible case")

    # --- visible-case deliverable: /app/specimens.json must match too -------
    if not os.path.isfile(SPECIMENS):
        failures.append("missing /app/specimens.json")
    else:
        try:
            with open(SPECIMENS, encoding="utf-8") as fh:
                got = json.load(fh)
            with open("/tests/expected.json", encoding="utf-8") as fh:
                want = json.load(fh)
            if norm_export(got) != norm_export(want):
                failures.append("specimens.json does not match visible expected")
        except Exception as exc:
            failures.append("specimens.json unreadable: %s" % exc)

    # --- hidden cases: distinct databases / roles / formatting --------------
    hidden_dir = "/tests/hidden"
    if not os.path.isdir(hidden_dir) or not os.listdir(hidden_dir):
        failures.append("no hidden cases present")
    else:
        for case in sorted(os.listdir(hidden_dir)):
            base = os.path.join(hidden_dir, case)
            stack = os.path.join(base, "stack.yaml")
            seed = os.path.join(base, "seed.sql")
            exp = os.path.join(base, "expected.json")
            if not all(os.path.isfile(p) for p in (stack, seed, exp)):
                failures.append("hidden '%s' malformed" % case)
                continue
            try:
                port, user, pw, db = parse_stack(stack)
            except Exception as exc:
                failures.append("hidden '%s': bad stack fixture: %s" % (case, exc))
                continue
            try:
                if user != CURATOR_USER:
                    r = psql(CURATOR_USER, CURATOR_PASS, "postgres",
                             "-c", "DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles "
                             "WHERE rolname = '%s') THEN CREATE ROLE %s LOGIN "
                             "SUPERUSER PASSWORD '%s'; END IF; END $$;"
                             % (user, user, pw))
                    if r.returncode != 0:
                        failures.append("hidden '%s': role provisioning failed" % case)
                        continue
                r1 = psql(CURATOR_USER, CURATOR_PASS, "postgres",
                          "-c", "DROP DATABASE IF EXISTS %s" % db,
                          "-c", "CREATE DATABASE %s OWNER %s" % (db, user))
                if r1.returncode != 0:
                    failures.append("hidden '%s': database provisioning failed" % case)
                    continue
                r2 = psql(user, pw, db, "-f", seed)
                if r2.returncode != 0:
                    failures.append("hidden '%s': seeding failed" % case)
                    continue
            except Exception as exc:
                failures.append("hidden '%s': provisioning error: %s" % (case, exc))
                continue
            export_matches(stack, exp, "hidden case '%s'" % case)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then overall=1; else overall=0; fi
