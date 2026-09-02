#!/bin/bash
# Verifier for larch-fathom (executes-deliverable).
# Executes /app/solve.py on the visible fixtures and on every hidden fixture,
# asserting: the answer.json contract; a live connection via DATABASE_URL;
# schema conformance; that the cleaned rows in the running database match an
# independent re-computation of the cleaning rules from the CSV; that the
# SQL-injection payload authenticates as 'administrator'; that the generated
# python bindings import and expose the service; and generic behavior on fresh
# and malformed hidden inputs. Writes reward to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
exec python3 - <<'PY'
import csv
import glob
import hashlib
import importlib
import json
import os
import re
import subprocess
import sys

SOL = "/app/solve.py"
AAP = "/app/answer.json"
VISEXP = "/tests/expected.json"
SEP = "\x1f"

failures = []


def fail(m):
    failures.append(m)


def read_url():
    p = "/app/database.env"
    if not os.path.exists(p):
        fail("missing /app/database.env (DATABASE_URL never exposed)")
        return None
    val = None
    for line in open(p):
        if line.startswith("export DATABASE_URL="):
            val = line.split("=", 1)[1].strip().strip('"').strip("'")
    if not val:
        fail("DATABASE_URL empty in /app/database.env")
    return val


def psql(url, query):
    r = subprocess.run(["psql", url, "-tA", "-F", SEP, "-c", query],
                       capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(r.stderr.strip())
    return [tuple(line.split(SEP)) for line in r.stdout.strip("\n").split("\n") if line]


def verb_rows(url, query):
    try:
        return psql(url, query)
    except Exception:
        return []


def parse_csv(path):
    with open(path, newline="") as fh:
        rdr = csv.DictReader(fh, fieldnames=["full_name", "email", "phone", "region"])
        rows = []
        for row in rdr:
            v = [row.get("full_name"), row.get("email"), row.get("phone"), row.get("region")]
            if v[0] is None and v[1:] == [None, None, None]:
                continue  # fully blank line
            if (v[0] or "").strip().lower() == "full_name":
                continue  # documented header row
            rows.append(v)
    return rows


def expected_cleaned(path):
    """Independently re-apply the documented cleaning rules to a CSV."""
    res = []
    seen = set()
    for full, em, ph, region in parse_csv(path):
        em = (em or "").strip().lower() if em else ""
        ph = re.sub(r"[^0-9]", "", ph or "")
        if (not em) and (not ph):
            continue  # row missing both contact fields
        key = (em, ph)
        if key in seen:
            continue  # duplicate pair; keep earliest only
        seen.add(key)
        res.append((full, em, ph, region or ""))
    return res


def digest(rows):
    body = "\n".join(SEP.join(tuple(r)) for r in rows)
    return hashlib.sha256(body.encode()).hexdigest()


def bindings_ok(outdir, mods):
    if len(mods) != 2:
        fail("modules must be exactly 2, got %r" % (mods,))
        return False
    if not os.path.exists(os.path.join(outdir, mods[0])) or \
       not os.path.exists(os.path.join(outdir, mods[1])):
        return False
    base = mods[0][:-len("_pb2.py")]
    try:
        sys.path.insert(0, outdir)
        pb = importlib.import_module(base + "_pb2")
        gr = importlib.import_module(base + "_pb2_grpc")
        getattr(pb, "DESCRIPTOR")
        svcs = [k for k in dir(gr) if k.endswith("Stub")]
        if not svcs:
            return False
        return True
    except Exception as e:
        fail("bindings import error: %r" % (e,))
        return False


def check_success(data_csv, proto, outdir, answer_json, label):
    r = subprocess.run([sys.executable, SOL, data_csv, proto, outdir, answer_json],
                       capture_output=True, text=True)
    if r.returncode != 0:
        fail("%s: solve.py failed: %s" % (label, r.stderr.strip()))
        return False
    if not os.path.exists(answer_json):
        fail("%s: answer not written" % label)
        return False
    ans = json.load(open(answer_json))
    url = read_url()
    if url is None:
        return False

    # schema conformance (independent of the oracle)
    cols = dict((n, t) for (n, t) in
                psql(url, "SELECT column_name, data_type FROM information_schema.columns "
                          "WHERE table_name='customers' AND table_schema='public' "
                          "ORDER BY ordinal_position;"))
    want = {"id": "integer", "full_name": "text", "email": "text",
            "phone": "text", "region": "text"}
    if cols != want:
        fail("%s: schema mismatch %r" % (label, cols))
        return False

    # cleaned rows match an independent recomputation, and survive dedupe
    exp = expected_cleaned(data_csv)
    db = verb_rows(url, "SELECT full_name, email, phone, region "
                        "FROM customers ORDER BY id;")
    if digest(db) != digest(exp):
        fail("%s: DB rows differ from independent recomputation" % label)
        return False
    if ans.get("cleaned") != len(exp):
        fail("%s: answer cleaned=%s want %d" % (label, ans.get("cleaned"), len(exp)))
        return False

    # auth bypass actually authenticates as administrator
    uname = ans.get("username")
    if not uname:
        fail("%s: answer has no injection username" % label)
        return False
    forged = "SELECT role FROM users WHERE username='%s' AND password='%s';" \
             % (uname, ans.get("password", ""))
    got = verb_rows(url, forged)
    if not got or got[0][0] != "administrator":
        fail("%s: supplied payload does not authenticate as administrator (%r)" % (label, got))
        return False
    if ans.get("target_role") != "administrator" or not ans.get("bypass_worked") \
       or ans.get("forged_role") != "administrator":
        fail("%s: answer auth fields wrong: %r" % (label, ans))
        return False
    admins = verb_rows(url, "SELECT role FROM users WHERE username='admin';")
    if not admins or admins[0][0] != "administrator":
        fail("%s: admin account/role missing" % label)
        return False

    # bindings generated and importable
    if not bindings_ok(outdir, ans.get("modules") or []):
        fail("%s: generated bindings missing/not importable" % label)
        return False
    return True


# ---------- 1) deliverable presence + static CLI contract ----------
if not os.path.exists(SOL):
    fail("missing deliverable /app/solve.py")
else:
    src = open(SOL).read()
    if "sys.argv" not in src:
        fail("solve.py never reads argv")
    for hard in ("/app/data/customers.csv", "/app/proto/ledger.proto"):
        if hard in src:
            fail("hard-coded path " + hard)

if not os.path.exists(AAP):
    fail("missing deliverable /app/answer.json")

# ---------- 2) visible case ----------
if os.path.exists(SOL) and os.path.exists(AAP) and os.path.exists(VISEXP):
    vis_exp = json.load(open(VISEXP))
    if check_success("/app/data/customers.csv", "/app/proto/ledger.proto",
                     "/app/generated", AAP, "visible"):
        # re-run the deliverable on the pristine visible fixture
        r = subprocess.run([sys.executable, SOL, "/app/data/customers.csv",
                            "/app/proto/ledger.proto", "/tmp/visgen", "/tmp/vis.json"],
                           capture_output=True, text=True)
        if r.returncode != 0:
            fail("visible rerun failed: " + r.stderr.strip())
        elif os.path.exists("/tmp/vis.json"):
            v2 = json.load(open("/tmp/vis.json"))
            if v2.get("cleaned") != vis_exp.get("cleaned") or \
               v2.get("total") != vis_exp.get("total") or \
               v2.get("schema") != vis_exp["schema"]:
                fail("visible rerun contradicted the expected facts")

# ---------- 3) hidden cases ----------
hidden = "/tests/hidden"
cases = sorted(n for n in os.listdir(hidden) if os.path.isdir(os.path.join(hidden, n)))
if len(cases) < 2:
    fail("expected >= 2 hidden cases, got %d" % len(cases))
for c in cases:
    d = os.path.join(hidden, c)
    if not os.path.exists(os.path.join(d, "expected.json")):
        fail("no expectation file for " + c)
        continue
    exp = json.load(open(os.path.join(d, "expected.json")))
    protos = glob.glob(os.path.join(d, "*.proto"))
    data = os.path.join(d, "customers.csv")
    if exp["mode"] == "success":
        if len(protos) != 1:
            fail("%s: expected exactly one proto" % c)
            continue
        if not check_success(data, protos[0],
                             os.path.join("/tmp", "hf_%s_gen" % c),
                             os.path.join("/tmp", "hf_%s.json" % c), c):
            fail("%s hidden case failed" % c)
    elif exp["mode"] == "error":
        if not protos:
            fail("%s: no proto for error case" % c)
            continue
        out = os.path.join("/tmp", "hf_%s_gen" % c)
        os.makedirs(out, exist_ok=True)
        r = subprocess.run([sys.executable, SOL, data, protos[0], out,
                            os.path.join("/tmp", "hf_%s.json" % c)],
                           capture_output=True, text=True)
        if r.returncode == 0:
            fail("%s: malformed proto did not stop the program" % c)
        if glob.glob(os.path.join(out, "*_pb2.py")) or \
           glob.glob(os.path.join(out, "*_pb2_grpc.py")):
            fail("%s: bindings written despite malformed proto" % c)
    else:
        fail("%s: unknown expectation mode %r" % (c, exp["mode"]))

# ---------- 4) SQL evidence persistence (C-dac7f784) ----------
for f, keys in [("/app/clean.sql", ["regexp_replace", "lower", "DELETE"]),
                ("/app/load.sql", ["INSERT INTO customers"])]:
    if not os.path.exists(f):
        fail("missing SQL evidence " + f)
    else:
        txt = open(f).read()
        for k in keys:
            if k not in txt:
                fail("%s lacks evidence %r" % (f, k))

# ---------- result ----------
if failures:
    print("FAILURES:")
    for m in failures:
        print("  - " + m)
    open("/logs/verifier/reward.txt", "w").write("0")
else:
    print("ALL PASS")
    open("/logs/verifier/reward.txt", "w").write("1")
sys.exit(0)
PY