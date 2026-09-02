#!/bin/bash
#
# moor-atlas verifier.
# Executes the deliverable /app/audit.py on the provided stack file and on
# hidden stack/database scenarios (different service names, credentials,
# databases, a different listening instance via its published port, a
# list-style environment, an empty registry), and checks the visible
# deliverable /app/audit.json. Hidden expect-failure scenarios (bad password,
# unreachable port) must make the program exit non-zero WITHOUT creating the
# output file. Writes REWARD (0/1) to /logs/verifier/reward.txt on every
# exit path.
set -u

mkdir -p /logs/verifier
printf 0 > /logs/verifier/reward.txt

reward=0
if /opt/moorctl/dbctl.sh up >/dev/null 2>&1 && python3 - <<'PY'
import glob, json, os, shutil, subprocess, sys, tempfile, time

SOLVE = "/app/audit.py"
PGBIN = None
for cand in sorted(glob.glob("/usr/lib/postgresql/*/bin")):
    PGBIN = cand
if not PGBIN:
    print("verify: no postgres binaries", file=sys.stderr)
    sys.exit(1)
PSQL = os.path.join(PGBIN, "psql")

# Infra guard: both scenario clusters must be listening (main + decoy).
for port in (5581, 5591):
    r = subprocess.run([os.path.join(PGBIN, "pg_isready"), "-h", "127.0.0.1",
                        "-p", str(port)], capture_output=True, timeout=30)
    if r.returncode != 0:
        print("verify: postgres not ready on %d" % port, file=sys.stderr)
        sys.exit(1)

failures = []


def norm(obj):
    assert isinstance(obj, dict), "audit is not a JSON object"
    assert set(obj.keys()) == {"database", "user", "port", "beacons_total",
                               "active", "by_grid", "strongest"}, sorted(obj.keys())
    database = str(obj["database"])
    user = str(obj["user"])
    port = int(obj["port"])
    total = int(obj["beacons_total"])
    active = int(obj["active"])
    by = obj["by_grid"]
    assert isinstance(by, dict), by
    by_t = tuple(sorted((str(k), int(v)) for k, v in by.items()))
    s = obj["strongest"]
    if s is None:
        s_t = None
    else:
        assert isinstance(s, dict) and set(s.keys()) == {"code", "grid", "strength"}, s
        s_t = (str(s["code"]), str(s["grid"]), int(s["strength"]))
    return (database, user, port, total, active, by_t, s_t)


def load_expected(path):
    with open(path, encoding="utf-8") as fh:
        return norm(json.load(fh))


def run_case(stack_path, expected_path, label):
    """Execute the deliverable; 0 ok, 1 mismatch, 2 must-fail-and-did."""
    out = tempfile.mktemp(suffix=".json")
    try:
        r = subprocess.run(
            [sys.executable, SOLVE, stack_path, out],
            capture_output=True, text=True, timeout=90,
        )
        if expected_path is None:
            # expect-failure scenario: non-zero exit AND no output file
            if r.returncode == 0:
                leak = ""
                if os.path.exists(out):
                    try:
                        with open(out, encoding="utf-8") as fh:
                            leak = fh.read()[:400]
                    except Exception:
                        pass
                failures.append("%s: should have failed, exited 0 (stderr: %s; out: %s)"
                                % (label, (r.stderr or "").strip()[:300], leak))
                return 1
            if os.path.exists(out):
                failures.append("%s: created output despite failure" % label)
                return 1
            return 2
        if r.returncode != 0 or not os.path.exists(out):
            failures.append("%s: audit.py exited %d" % (label, r.returncode))
            return 1
        try:
            with open(out, encoding="utf-8") as fh:
                got = norm(json.load(fh))
            return 0 if got == load_expected(expected_path) else 1
        except Exception as exc:
            failures.append("%s: bad audit (%s)" % (label, exc))
            return 1
    except subprocess.TimeoutExpired:
        failures.append("%s: timed out" % label)
        return 1
    except Exception as exc:
        failures.append("%s: %s" % (label, exc))
        return 1
    finally:
        if os.path.exists(out):
            os.remove(out)


# --- deliverables must exist -------------------------------------------------
if not os.path.isfile(SOLVE):
    print("verify failures: missing /app/audit.py", file=sys.stderr)
    sys.exit(1)
if not os.path.isfile("/app/audit.json"):
    print("verify failures: missing /app/audit.json", file=sys.stderr)
    sys.exit(1)

ok = True

# --- visible case: EXECUTE audit.py on the live provided stack ---------------
if run_case("/app/deploy/services.yml", "/tests/expected.json", "visible-run") != 0:
    ok = False
# the committed deliverable /app/audit.json must match the visible expected
try:
    with open("/app/audit.json", encoding="utf-8") as fh:
        if norm(json.load(fh)) != load_expected("/tests/expected.json"):
            failures.append("audit.json does not match visible expected")
            ok = False
except Exception as exc:
    failures.append("audit.json unreadable (%s)" % exc)
    ok = False

# --- hidden stack/database scenarios -----------------------------------------
tmp = tempfile.mkdtemp(prefix="moor_hidden_")
try:
    cases = 0
    for cdir in sorted(glob.glob("/tests/hidden/*/")):
        name = os.path.basename(cdir.rstrip("/"))
        compose = os.path.join(cdir, "compose.yaml")
        if not os.path.isfile(compose):
            failures.append("hidden '%s': no compose.yaml" % name)
            ok = False
            continue
        cases += 1

        seed = os.path.join(cdir, "seed.sql")
        exp = os.path.join(cdir, "expected.json")
        expect_fail = exp is None or not os.path.isfile(exp) or not os.path.isfile(seed)

        # run on a COPY of the hidden stack file (never write into /tests)
        case_compose = os.path.join(tmp, "%s_stack.yaml" % name)
        shutil.copyfile(compose, case_compose)

        if expect_fail:
            res = run_case(case_compose, None, "hidden:%s" % name)
            if res != 2:
                ok = False
            continue

        # derive credentials + port from the hidden stack file (guarded parse)
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
                env = dict(e.split("=", 1) for e in env if "=" in str(e))
            user = str(env["POSTGRES_USER"])
            password = str(env["POSTGRES_PASSWORD"])
            dbname = str(env["POSTGRES_DB"])
            hostport = None
            ports = svc.get("ports") or []
            if isinstance(ports, dict):
                hostport = int(str(list(ports.values())[0]).split(":", 1)[0])
            else:
                for p in ports:
                    sp = str(p)
                    if ":" in sp:
                        hostport = int(sp.split(":", 1)[0])
                        break
            if not (user and password and dbname and hostport and svc_name):
                raise ValueError("incomplete credentials in %s" % compose)
        except Exception as exc:
            failures.append("hidden '%s': fixture parse failed (%s)" % (name, exc))
            ok = False
            continue

        def sh(cmd, timeout=90):
            return subprocess.run(cmd, shell=True, capture_output=True,
                                  text=True, timeout=timeout)

        # provision role + database on the stack's published port, via the
        # unix socket (trust) as the bootstrap superuser.
        created = False
        for _ in range(4):
            sh('"%s" --if-exists -U postgres -p %d -c "DROP DATABASE IF EXISTS %s"'
               % (os.path.join(PGBIN, "dropdb"), hostport, dbname))
            r1 = subprocess.run(
                [PSQL, "-U", "postgres", "-p", str(hostport), "-d", "postgres",
                 "-tA", "-v", "ON_ERROR_STOP=1", "-q", "-c",
                 "DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '%s') "
                 "THEN CREATE ROLE %s LOGIN PASSWORD '%s'; ELSE ALTER ROLE %s LOGIN PASSWORD '%s'; "
                 "END IF; END $$;" % (user, user, password.replace("'", "''"), user, password.replace("'", "''"))],
                capture_output=True, text=True, timeout=60)
            r2 = subprocess.run([os.path.join(PGBIN, "createdb"), "-U", "postgres",
                                 "-p", str(hostport), "-O", user, dbname],
                                capture_output=True, text=True, timeout=60)
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
            r = subprocess.run([PSQL, "-U", "postgres", "-p", str(hostport), "-d", dbname,
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
        subprocess.run([PSQL, "-U", "postgres", "-p", str(hostport), "-d", dbname,
                        "-c", "GRANT SELECT ON beacons TO %s;" % user],
                       capture_output=True, text=True, timeout=60)

        if run_case(case_compose, exp, "hidden:%s" % name) != 0:
            ok = False

        subprocess.run([os.path.join(PGBIN, "dropdb"), "--if-exists", "-U", "postgres",
                        "-p", str(hostport), dbname],
                       capture_output=True, text=True, timeout=60)

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
