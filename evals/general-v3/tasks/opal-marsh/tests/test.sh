#!/bin/bash
# Verifier for opal-marsh: checks the visible deliverable, ENFORCES the
# no-modify rule on /app/spec.json, and EXECUTES /app/gen_map.py on every
# hidden spec, independently re-validating the mapping, both caps and the
# report. Writes REWARD (0/1) to /logs/verifier/reward.txt. Never crashes on
# malformed agent output.
set -u

mkdir -p /logs/verifier
reward=0

PRISTINE_SPEC_SHA="7d5292c9e5526f8525522aefc81fc91f6294c9e2f590942e18f2ce79faa5b8b4"
export PRISTINE_SPEC_SHA

python3 - <<'PY'
import hashlib, json, os, re, subprocess, sys

SOLVE = "/app/gen_map.py"
failures = []


def fail(msg):
    failures.append(msg)


def build_expected(spec):
    bits, a, r = spec["bits"], spec["a"], spec["r"]
    n = 1 << bits
    def rotl(x, rr):
        rr %= bits
        return x if rr == 0 else ((x << rr) | (x >> (bits - rr))) & (n - 1)
    return [rotl(s ^ a, r) for s in range(n)]


def validate_map_file(path, spec):
    """Return (rows, nbytes) on success; append to failures on any problem."""
    bits = int(spec["bits"])
    cap_rows = int(spec["cap_rows"])
    cap_bytes = int(spec["cap_bytes"])
    n = 1 << bits
    w = (bits + 3) // 4
    expected = build_expected(spec)

    try:
        raw = open(path, "rb").read()
    except Exception as e:
        fail("map file %s unreadable: %r" % (path, e))
        return None
    nbytes = len(raw)
    if nbytes > cap_bytes:
        fail("map file is %d bytes > cap_bytes %d" % (nbytes, cap_bytes))
        return None
    try:
        text = raw.decode("utf-8")
    except Exception as e:
        fail("map file not utf-8: %r" % e)
        return None
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    else:
        fail("map file does not end with a newline")
        return None
    if not lines:
        fail("map file empty")
        return None
    header, body = lines[0], lines[1:]
    if header not in ("FULL", "SPARSE"):
        fail("bad header %r" % header)
        return None
    if len(body) > cap_rows:
        fail("%d mapping rows > cap_rows %d" % (len(body), cap_rows))
        return None

    # reconstruct the mapping encoded by the file
    m = None
    if header == "FULL":
        if len(body) != n:
            fail("FULL body has %d rows, expected %d" % (len(body), n))
            return None
        m = [None] * n
        for i, ln in enumerate(body):
            mm = re.fullmatch(r"([0-9a-f]{%d}),([0-9a-f]{%d})" % (w, w), ln)
            if not mm:
                fail("bad FULL row %d: %r" % (i, ln))
                return None
            if int(mm.group(1), 16) != i:
                fail("FULL row %d has src %s" % (i, mm.group(1)))
                return None
            m[i] = int(mm.group(2), 16)
    else:
        m = list(range(n))  # identity default
        last = -1
        for i, ln in enumerate(body):
            mm = re.fullmatch(r"([0-9a-f]{%d}),([0-9a-f]{%d})" % (w, w), ln)
            if not mm:
                fail("bad SPARSE row %d: %r" % (i, ln))
                return None
            s = int(mm.group(1), 16)
            if s <= last:
                fail("SPARSE srcs not strictly increasing at row %d" % i)
                return None
            last = s
            m[s] = int(mm.group(2), 16)

    for s in range(n):
        if m[s] != expected[s]:
            fail("mapping wrong at src %s: got %s want %s"
                 % (s, m[s], expected[s]))
            return None
    return len(body), nbytes


def validate_report(path, spec, rows, nbytes, header):
    try:
        with open(path) as fh:
            rep = json.load(fh)
    except Exception as e:
        fail("report %s unreadable: %r" % (path, e))
        return
    if not isinstance(rep, dict) or set(rep.keys()) != {"mode", "mapping_rows", "file_bytes"}:
        fail("report keys wrong: %r" % (rep if not isinstance(rep, dict) else sorted(rep.keys())))
        return
    if rep["mode"] != header:
        fail("report mode %r != file header %r" % (rep["mode"], header))
    if rep["mapping_rows"] != rows:
        fail("report mapping_rows %r != actual %d" % (rep["mapping_rows"], rows))
    if rep["file_bytes"] != nbytes:
        fail("report file_bytes %r != actual %d" % (rep["file_bytes"], nbytes))


def run_case(spec_path, tag):
    try:
        with open(spec_path) as fh:
            spec = json.load(fh)
    except Exception as e:
        fail("unreadable spec %s: %r" % (spec_path, e))
        return
    out = "/tmp/om_%s_map.txt" % tag
    rep = "/tmp/om_%s_report.json" % tag
    for p in (out, rep):
        if os.path.exists(p):
            os.remove(p)
    try:
        r = subprocess.run(
            [sys.executable, SOLVE, spec_path, out, "--report-out", rep],
            capture_output=True, text=True, timeout=180,
        )
    except Exception as e:
        fail("run crashed on %s: %r" % (spec_path, e))
        return

    bits = int(spec["bits"])
    n = 1 << bits
    w = (bits + 3) // 4
    expected = build_expected(spec)
    E = sum(1 for s in range(n) if expected[s] != s)
    full_rows, full_bytes = n, 5 + n * (2 * w + 2)
    sparse_rows, sparse_bytes = E, 7 + E * (2 * w + 2)
    feasible = (min(full_bytes, sparse_bytes) <= spec["cap_bytes"]
                and min(full_rows, sparse_rows) <= spec["cap_rows"])

    if not feasible:
        # refusal contract: non-zero exit, INFEASIBLE line, no output file
        if r.returncode == 0:
            fail("infeasible spec %s accepted (exit 0)" % spec_path)
            return
        if not any(ln.startswith("INFEASIBLE") for ln in r.stdout.splitlines()):
            fail("no INFEASIBLE line on stdout for %s" % spec_path)
            return
        if os.path.exists(out):
            fail("output file left behind for infeasible %s" % spec_path)
            return
        return

    if r.returncode != 0:
        fail("feasible spec %s rejected (exit %d): %s"
             % (spec_path, r.returncode, r.stdout[-200:]))
        return
    res = validate_map_file(out, spec)
    if res is None:
        return
    rows, nbytes = res
    header = open(out).readline().strip()
    validate_report(rep, spec, rows, nbytes, header)


# no-modify check on the visible spec
pristine = os.environ.get("PRISTINE_SPEC_SHA", "")
try:
    actual = hashlib.sha256(open("/app/spec.json", "rb").read()).hexdigest()
except Exception:
    actual = None
if actual != pristine:
    fail("visible spec modified or missing (no-modify rule)")

if not os.path.isfile(SOLVE):
    fail("missing /app/gen_map.py")
else:
    # visible case: re-run and validate, then validate the default artifacts
    if os.path.isfile("/app/spec.json"):
        run_case("/app/spec.json", "visible")
        if os.path.isfile("/app/calib_map.txt") and os.path.isfile("/app/map_report.json"):
            try:
                spec = json.load(open("/app/spec.json"))
                res = validate_map_file("/app/calib_map.txt", spec)
                if res is not None:
                    rows, nbytes = res
                    header = open("/app/calib_map.txt").readline().strip()
                    validate_report("/app/map_report.json", spec, rows, nbytes, header)
            except Exception as e:
                fail("visible artifact validation error: %r" % e)
        else:
            fail("missing /app/calib_map.txt or /app/map_report.json")
    else:
        fail("visible spec missing")

    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(os.listdir(hidden_dir))
        if not cases:
            fail("no hidden cases present")
        for c in cases:
            spec = os.path.join(hidden_dir, c, "spec.json")
            if not os.path.isfile(spec):
                fail("hidden case '%s' malformed" % c)
                continue
            run_case(spec, "h_" + c)
    else:
        fail("no hidden cases dir")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
