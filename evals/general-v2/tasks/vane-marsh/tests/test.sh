#!/bin/bash
# Verifier for vane-marsh. Executes the deliverable /app/export.py on the
# visible compose fixture and on hidden compose/database scenarios, checks the
# visible deliverable /app/report.json, enforces the no-modify rule on
# /app/grid/compose.yaml, and writes the reward to /logs/verifier/reward.txt
# on every exit path.
set -u

mkdir -p /logs/verifier
printf 0 > /logs/verifier/reward.txt

TIMEOUT_CMD=$(command -v timeout || true)
[ -n "${TIMEOUT_CMD-}" ] || TIMEOUT_CMD=""

# Keep the scenario live (idempotent infrastructure, in the image).
$TIMEOUT_CMD 120 /opt/gridctl/dbctl.sh up >/dev/null 2>&1

overall=1
msgs=""

# Pristine sha256 of the supplied visible compose fixture (no-modify rule).
PRISTINE_COMPOSE_SHA="f511c04668fa83cb54e199e0daf67c0abf299300f8a0503011ccdbe7909f768d"

if [ ! -f /app/grid/compose.yaml ]; then
    overall=0; msgs="$msgs no-modify:compose-missing"
else
    actual="$(sha256sum /app/grid/compose.yaml | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_COMPOSE_SHA" ]; then
        overall=0; msgs="$msgs no-modify:compose-modified"
    fi
fi

[ -f /app/export.py ]   || { overall=0; msgs="$msgs missing:export.py"; }
[ -f /app/report.json ] || { overall=0; msgs="$msgs missing:report.json"; }

runpy=$("$TIMEOUT_CMD" 280 python3 - "$overall" <<'PYEOF'
import json, os, re, subprocess, sys, tempfile

overall = sys.argv[1] == "1"
failures = []

PGBIN_DIR = "/usr/bin"
PSQL = os.path.join(PGBIN_DIR, "psql") if os.path.exists(
    os.path.join(PGBIN_DIR, "psql")) else "psql"

REF_QUERY = ("SELECT meter, kwh::text, reading_date::text "
             "FROM meter_readings ORDER BY meter, reading_date, kwh")


def norm_report(obj):
    assert isinstance(obj, dict), "report is not a JSON object"
    assert set(obj.keys()) == {"database", "user", "row_count", "readings"}, \
        "unexpected keys: %s" % sorted(obj.keys())
    readings = obj["readings"]
    assert isinstance(readings, list)
    norm_readings = []
    for r in readings:
        assert isinstance(r, dict) and set(r.keys()) == \
            {"meter", "kwh", "reading_date"}, "bad reading row: %r" % (r,)
        norm_readings.append((str(r["meter"]), round(float(r["kwh"]), 6),
                              str(r["reading_date"])))
    assert obj["row_count"] == len(readings), "row_count != len(readings)"
    return (str(obj["database"]), str(obj["user"]), norm_readings)


def run_export(compose, out):
    if os.path.exists(out):
        os.remove(out)
    r = subprocess.run(
        [sys.executable, "/app/export.py", compose, out],
        capture_output=True, text=True, timeout=90,
    )
    if r.returncode != 0 or not os.path.exists(out):
        return None
    try:
        with open(out) as f:
            return json.load(f)
    except Exception:
        return None


def psql_superuser(db, sql):
    env = dict(os.environ)
    r = subprocess.run(
        ["timeout", "60", PSQL, "-h", "127.0.0.1", "-p", "5433",
         "-U", "postgres", "-d", db, "-tA", "-F", "|", "-v", "ON_ERROR_STOP=1",
         "-c", sql],
        env=env, capture_output=True, text=True, timeout=70,
    )
    if r.returncode != 0:
        raise RuntimeError("psql failed: %s" % r.stderr.strip()[:300])
    return r.stdout


def reference_rows(db):
    out = psql_superuser(db, REF_QUERY)
    rows = []
    for line in out.splitlines():
        if not line.strip():
            continue
        meter, kwh_txt, date_txt = line.split("|", 2)
        rows.append((meter, round(float(kwh_txt), 6), date_txt))
    return rows


def parse_compose(path):
    text = open(path, encoding="utf-8").read()
    def scalar(key):
        m = re.search(r'^\s*%s:\s*(.+?)\s*$' % key, text, re.M)
        assert m, "compose missing %s" % key
        v = m.group(1).strip()
        if len(v) >= 2 and v[0] == v[-1] and v[0] in ("'", '"'):
            v = v[1:-1]
        return v
    pm = re.search(r'ports:\s*\n\s*-\s*"(\d+):\d+"', text)
    assert pm, "compose missing ports"
    return scalar("POSTGRES_DB"), scalar("POSTGRES_USER"), \
        scalar("POSTGRES_PASSWORD"), int(pm.group(1))


# ---- visible case: execute the deliverable, compare with frozen expected ----
if overall:
    got = run_export("/app/grid/compose.yaml", "/tmp/vm_visible.json")
    if got is None:
        failures.append("visible: export.py crashed or produced no output")
    else:
        try:
            want = json.load(open("/tests/expected.json"))
            if norm_report(got) != norm_report(want):
                failures.append("visible: export.py output mismatch")
        except Exception as exc:
            failures.append("visible expected unreadable: %s" % exc)

    # visible deliverable /app/report.json must match the frozen expected
    if os.path.isfile("/app/report.json"):
        try:
            got_rep = json.load(open("/app/report.json"))
            want = json.load(open("/tests/expected.json"))
            if norm_report(got_rep) != norm_report(want):
                failures.append("visible: /app/report.json mismatch")
        except Exception as exc:
            failures.append("report.json unreadable: %s" % exc)
    else:
        failures.append("missing /app/report.json")

# ---- hidden compose/database scenarios ----
hidden_dir = "/tests/hidden"
cases = sorted(d for d in os.listdir(hidden_dir)
               if os.path.isdir(os.path.join(hidden_dir, d))) \
    if os.path.isdir(hidden_dir) else []
if not cases:
    failures.append("hidden: no cases present")

for case in cases:
    if not overall:
        break
    base = os.path.join(hidden_dir, case)
    compose = os.path.join(base, "compose.yaml")
    seed = os.path.join(base, "seed.sql")
    if not (os.path.isfile(compose) and os.path.isfile(seed)):
        failures.append("hidden %s: malformed fixture" % case)
        continue
    try:
        db, user, pw, port = parse_compose(compose)
        assert port == 5433, "unexpected hidden port %s" % port
    except Exception as exc:
        failures.append("hidden %s: bad compose (%s)" % (case, exc))
        continue
    # provision the hidden instance as a distinct db + role
    try:
        psql_superuser("postgres", "DROP DATABASE IF EXISTS %s;" % db)
        psql_superuser("postgres", "DROP ROLE IF EXISTS %s;" % user)
        psql_superuser("postgres",
                       "CREATE ROLE %s LOGIN PASSWORD '%s';" % (user, pw))
        psql_superuser("postgres", "CREATE DATABASE %s;" % db)
        psql_superuser(db, open(seed, encoding="utf-8").read())
    except Exception as exc:
        failures.append("hidden %s: provisioning failed (%s)" % (case, exc))
        continue
    got = run_export(compose, "/tmp/vm_hidden_%s.json" % case)
    if got is None:
        failures.append("hidden %s: export.py crashed or produced no output"
                        % case)
    else:
        try:
            want = {"database": db, "user": user,
                    "row_count": None, "readings": None}
            ref_rows = reference_rows(db)
            want["row_count"] = len(ref_rows)
            want["readings"] = [
                {"meter": m, "kwh": k, "reading_date": d}
                for (m, k, d) in ref_rows
            ]
            if norm_report(got) != norm_report(want):
                failures.append("hidden %s: report mismatch" % case)
        except Exception as exc:
            failures.append("hidden %s: reference build failed (%s)"
                            % (case, exc))
    try:
        psql_superuser("postgres", "DROP DATABASE IF EXISTS %s;" % db)
        psql_superuser("postgres", "DROP ROLE IF EXISTS %s;" % user)
    except Exception:
        pass

if failures or not overall:
    print("vane-marsh verifier FAIL: %s" % "; ".join(failures + [msgs]),
          file=sys.stderr)
    sys.exit(1)
sys.exit(0)
PYEOF
)

if [ $? -eq 0 ] && [ "$overall" = "1" ]; then
    printf 1 > /logs/verifier/reward.txt
else
    printf 0 > /logs/verifier/reward.txt
fi
exit 0
