#!/usr/bin/env bash
# Verifier for granary-ledge: executes the deliverable /app/inspect.py on the
# provided stack file and on hidden stack/database scenarios (different
# service names, credentials, databases, list-style environments, and data),
# and checks the visible deliverable /app/report.json. Writes REWARD (0/1) to
# /logs/verifier/reward.txt on every exit path.
set -u

mkdir -p /logs/verifier
printf 0 > /logs/verifier/reward.txt

reward=0
if python3 - <<'PY'
import glob, json, os, shutil, subprocess, sys, tempfile, time

SOLVE = "/app/inspect.py"
PGBIN = None
for cand in sorted(glob.glob("/usr/lib/postgresql/*/bin")):
    PGBIN = cand
if not PGBIN:
    print("verify: no postgres binaries", file=sys.stderr)
    sys.exit(1)
PSQL = os.path.join(PGBIN, "psql")

failures = []


def psql(db, sql):
    """Run SQL over the unix socket as the bootstrap superuser (trust)."""
    return subprocess.run(
        [PSQL, "-U", "postgres", "-d", db, "-tA", "-v", "ON_ERROR_STOP=1", "-q", "-c", sql],
        capture_output=True, text=True, timeout=60,
    )


def norm(obj):
    assert isinstance(obj, dict), "report is not a JSON object"
    assert set(obj.keys()) == {"service", "database", "low_stock",
                               "restock_units", "restock_value"}, sorted(obj.keys())
    assert isinstance(obj["service"], str) and obj["service"], obj["service"]
    assert isinstance(obj["database"], str) and obj["database"], obj["database"]
    low = obj["low_stock"]
    assert isinstance(low, list), low
    rows = []
    for r in low:
        assert isinstance(r, dict) and set(r.keys()) == {
            "sku", "name", "stock", "reorder_point"}, r
        rows.append((str(r["sku"]), str(r["name"]), int(r["stock"]), int(r["reorder_point"])))
    units = obj["restock_units"]
    assert isinstance(units, int) and not isinstance(units, bool), units
    value = round(float(obj["restock_value"]), 2)
    return (obj["service"], obj["database"], sorted(rows), units, value)


def load_expected(path):
    with open(path, encoding="utf-8") as fh:
        return norm(json.load(fh))


def run_case(compose_path, expected_path, label):
    out = tempfile.mktemp(suffix=".json")
    try:
        r = subprocess.run(
            [sys.executable, SOLVE, compose_path, out],
            capture_output=True, text=True, timeout=90,
        )
        if r.returncode != 0 or not os.path.exists(out):
            failures.append("%s: inspect.py exited %d" % (label, r.returncode))
            return False
        try:
            with open(out, encoding="utf-8") as fh:
                got = norm(json.load(fh))
            return got == load_expected(expected_path)
        except Exception as exc:
            failures.append("%s: bad report (%s)" % (label, exc))
            return False
    except Exception as exc:
        failures.append("%s: %s" % (label, exc))
        return False
    finally:
        if os.path.exists(out):
            os.remove(out)


# --- deliverables must exist -------------------------------------------------
if not os.path.isfile(SOLVE):
    print("verify failures: missing /app/inspect.py", file=sys.stderr)
    sys.exit(1)
if not os.path.isfile("/app/report.json"):
    print("verify failures: missing /app/report.json", file=sys.stderr)
    sys.exit(1)

ok = True

# --- visible case: EXECUTE inspect.py on the live provided stack -------------
if not run_case("/app/deploy/stack.yml", "/tests/expected.json", "visible-run"):
    ok = False
# the committed deliverable /app/report.json must match the visible expected
try:
    with open("/app/report.json", encoding="utf-8") as fh:
        if norm(json.load(fh)) != load_expected("/tests/expected.json"):
            failures.append("report.json does not match visible expected")
            ok = False
except Exception as exc:
    failures.append("report.json unreadable (%s)" % exc)
    ok = False

# --- hidden stack/database scenarios ----------------------------------------
tmp = tempfile.mkdtemp(prefix="granary_hidden_")
try:
    cases = 0
    for cdir in sorted(glob.glob("/tests/hidden/*/")):
        compose = os.path.join(cdir, "compose.yaml")
        seed = os.path.join(cdir, "seed.sql")
        exp = os.path.join(cdir, "expected.json")
        if not all(os.path.isfile(p) for p in (compose, seed, exp)):
            failures.append("hidden '%s' malformed" % cdir)
            ok = False
            continue
        cases += 1
        name = os.path.basename(cdir.rstrip("/"))

        # derive credentials from the hidden stack file (guarded parse)
        try:
            import yaml
            with open(compose, encoding="utf-8") as fh:
                doc = yaml.safe_load(fh)
            svc_name, svc = next(
                (n, s) for n, s in (doc.get("services") or {}).items()
                if "postgres" in str((s or {}).get("image", ""))
            )
            env = svc.get("environment") or {}
            if isinstance(env, list):
                env = dict(e.split("=", 1) for e in env)
            user = env["POSTGRES_USER"]
            password = env["POSTGRES_PASSWORD"]
            dbname = env["POSTGRES_DB"]
            if not (user and password and dbname and svc_name):
                raise ValueError("incomplete credentials in %s" % compose)
        except Exception as exc:
            failures.append("hidden '%s': fixture parse failed (%s)" % (name, exc))
            ok = False
            continue

        def sh(cmd, timeout=90):
            return subprocess.run(cmd, shell=True, capture_output=True,
                                  text=True, timeout=timeout)

        # (re)create role + database for this scenario (with retries; the
        # comparison itself stays strict)
        created = False
        for _ in range(4):
            sh('"%s" --if-exists -U postgres -c "DROP DATABASE IF EXISTS %s"'
               % (os.path.join(PGBIN, "dropdb"), dbname))
            r1 = psql("postgres",
                      "DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '%s') "
                      "THEN CREATE ROLE %s LOGIN PASSWORD '%s'; ELSE ALTER ROLE %s LOGIN PASSWORD '%s'; "
                      "END IF; END $$;" % (user, user, password, user, password))
            r2 = subprocess.run([os.path.join(PGBIN, "createdb"), "-U", "postgres",
                                 "-O", user, dbname], capture_output=True, text=True, timeout=60)
            if r1.returncode == 0 and r2.returncode == 0:
                created = True
                break
            time.sleep(1)
        if not created:
            failures.append("hidden '%s': db/role provisioning failed" % name)
            ok = False
            continue

        seeded = False
        for _ in range(4):
            r = subprocess.run([PSQL, "-U", "postgres", "-d", dbname,
                                "-v", "ON_ERROR_STOP=1", "-q", "-f", seed],
                               capture_output=True, text=True, timeout=60)
            if r.returncode == 0:
                seeded = True
                break
            time.sleep(1)
        if not seeded:
            failures.append("hidden '%s': seed failed" % name)
            ok = False
            continue
        psql(dbname, "GRANT SELECT ON items TO %s;" % user)

        # run the deliverable on a COPY of the hidden stack file
        case_compose = os.path.join(tmp, "%s_stack.yaml" % name)
        shutil.copyfile(compose, case_compose)
        if not run_case(case_compose, exp, "hidden:%s" % name):
            ok = False

        subprocess.run([os.path.join(PGBIN, "dropdb"), "--if-exists", "-U", "postgres",
                        dbname], capture_output=True, text=True, timeout=60)

    if cases < 1:
        failures.append("no hidden scenarios")
        ok = False
finally:
    shutil.rmtree(tmp, ignore_errors=True)

if failures:
    print("verify failures: %s" % "; ".join(failures), file=sys.stderr)
sys.exit(0 if (ok and not failures) else 1)
PY
then
  reward=1
fi

echo "$reward" > /logs/verifier/reward.txt
exit 0
