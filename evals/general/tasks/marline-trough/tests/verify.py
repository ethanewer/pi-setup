#!/usr/bin/env python3
"""marline-trough verifier.

Three gates on the deliverable /app/fluxline (entrypoint
/app/fluxline/lib/pipeline.js):

  1. STATIC  — the pipeline must consume its NDJSON input as a stream
     (node:fs createReadStream -> node:readline createInterface) and write
     output incrementally (createWriteStream). Neither lib/pipeline.js nor
     lib/transform.js may load the whole file (readFile/readFileSync) or
     materialize every line (toArray).

  2. CORRECTNESS — the pipeline must reproduce, on every input, the exact
     transformation semantics documented in the fixture README: integer
     raw*scale normalization, drop rules applied to normalized values, emit
     key selection/order. The expected output is computed independently in
     Python here; output lines are compared JSON-value by JSON-value in
     order.

  3. RESOURCE — peak RSS is read from /proc/<pid>/status (VmHWM) both
     while the pipeline runs and once more after it exits (the un-reaped
     child keeps its final VmHWM); the post-exit read is authoritative.
     No process-accounting net is used: getrusage(RUSAGE_CHILDREN)
     reports the pages the forked child inherited from this verifier
     process before execve, so on large reference sets it records the
     verifier's own RSS, not the pipeline's. The declared ceiling is
     192 MiB (196608 KiB). The shipped build buffers the whole input and
     breaches it on large workloads; that is the regression this task
     fixes.

Runs are on the visible sample plus every directory under /tests/hidden
(each contains params.json for tests/gen.py plus config.json). Exits 0 iff
every check passes; test.sh maps the exit code to the binary reward.
"""
import json
import os
import shutil
import subprocess
import sys
import time

HIDDEN = "/tests/hidden"
GEN = "/tests/gen.py"
PIPELINE = "/app/fluxline/lib/pipeline.js"
REPO = "/app/fluxline"
CEILING_KIB = 196608  # 192 MiB, the documented working-set budget
RUN_TIMEOUT = 240.0

fails = []


def fail(msg):
    fails.append(msg)


# --------------------------------------------------------------------------
# 1. static stream-API gate
# --------------------------------------------------------------------------
def static_checks():
    for rel in ("lib/pipeline.js", "lib/transform.js"):
        path = os.path.join(REPO, rel)
        if not os.path.isfile(path):
            fail("missing %s (the deliverable pipeline must live there)" % rel)
            continue
        src = open(path, encoding="utf-8", errors="replace").read()
        for banned in ("readFile", "readFileSync", "toArray"):
            if banned in src:
                fail("%s uses %r (whole-file read / line materialization forbidden)" %
                     (rel, banned))
    pipe_src = open(os.path.join(REPO, "lib/pipeline.js"),
                    encoding="utf-8", errors="replace").read()
    for needed in ("createReadStream", "createInterface", "createWriteStream"):
        if needed not in pipe_src:
            fail("lib/pipeline.js no longer uses %s (streaming I/O removed)" % needed)


# --------------------------------------------------------------------------
# 2. independent Python reference of the documented transform semantics
# --------------------------------------------------------------------------
def reference_rows(input_path, cfg):
    scales = cfg["scales"]
    drops = cfg.get("drops", []) or []
    emit = cfg["emit"]
    rows = []
    with open(input_path, encoding="utf-8", errors="replace") as fh:
        for raw in fh:
            text = raw.strip()
            if text == "":
                continue
            try:
                rec = json.loads(text)
            except ValueError:
                continue
            if not isinstance(rec, dict):
                continue
            sensor = rec.get("sensor")
            if not isinstance(sensor, str):
                continue
            scale = scales.get(sensor)
            if scale is None:
                continue  # unknown sensor
            rv = rec.get("raw")
            if isinstance(rv, bool) or not isinstance(rv, (int, float)):
                continue
            value = rv * scale
            dropped = False
            for rule in drops:
                if rule.get("sensor") != sensor:
                    continue
                if rule.get("below") is not None and value < rule["below"]:
                    dropped = True
                    break
                if rule.get("above") is not None and value > rule["above"]:
                    dropped = True
                    break
            if dropped:
                continue
            row = {}
            ok = True
            for key in emit:
                if key == "value":
                    row[key] = value
                elif key in rec:
                    row[key] = rec[key]
                else:
                    ok = False
                    break
            if ok:
                rows.append(row)
    return rows


def parse_output(path):
    rows = []
    with open(path, encoding="utf-8", errors="replace") as fh:
        for i, raw in enumerate(fh, 1):
            text = raw.strip()
            if text == "":
                continue
            try:
                rows.append(json.loads(text))
            except ValueError:
                fail("output line %d is not valid JSON: %r" % (i, text[:80]))
                rows.append(None)
    return rows


# --------------------------------------------------------------------------
# 3. run + RSS sampling
# --------------------------------------------------------------------------
def read_vmhwm(pid):
    """Peak resident set (KiB) of a live or zombie process, or 0 if gone."""
    try:
        st = open("/proc/%d/status" % pid, encoding="ascii").read()
    except OSError:
        return 0
    for line in st.splitlines():
        if line.startswith("VmHWM:") and line[6:].strip():
            return int(line.split()[1])
    return 0


def run_pipeline(in_path, cfg_path, out_path, label):
    t0 = time.time()
    proc = subprocess.Popen(
        ["node", PIPELINE, in_path, cfg_path, out_path],
        cwd=REPO, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    peak = 0
    while True:
        peak = max(peak, read_vmhwm(proc.pid))
        if proc.poll() is not None:
            break
        if time.time() - t0 > RUN_TIMEOUT:
            proc.kill()
            proc.wait()
            fail("%s: timed out after %ds and was killed" % (label, RUN_TIMEOUT))
            return None, 0
        time.sleep(0.02)
    # The child exited but is not yet reaped, so it still exists as a zombie
    # and /proc/<pid>/status keeps its final VmHWM. That read is the exact
    # peak; the in-loop samples are only a fallback if /proc disappeared.
    peak = max(peak, read_vmhwm(proc.pid))
    try:
        rc = proc.wait(timeout=30)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()
        fail("%s: timed out after %ds and was killed" % (label, RUN_TIMEOUT))
        return None, 0
    return rc, peak


def check_case(label, in_path, cfg_path, out_path):
    if not os.path.isfile(cfg_path):
        fail("%s: config missing (%s)" % (label, cfg_path))
        return
    with open(cfg_path, encoding="utf-8") as fh:
        cfg = json.load(fh)
    try:
        expected = reference_rows(in_path, cfg)
    except Exception as exc:  # noqa: BLE001 - verifier must fail loud, not raise
        fail("%s: reference computation failed: %r" % (label, exc))
        return
    rc, peak = run_pipeline(in_path, cfg_path, out_path, label)
    if rc is None:
        return
    if rc != 0:
        fail("%s: pipeline exit code %d (expected 0)" % (label, rc))
        return
    if not os.path.isfile(out_path):
        fail("%s: no output file produced at %s" % (label, out_path))
        return
    if peak > CEILING_KIB:
        fail("%s: peak RSS %d KiB (%.1f MiB) exceeds the 192 MiB ceiling" %
             (label, peak, peak / 1024.0))
    got = parse_output(out_path)
    if got != expected:
        n = min(len(got), len(expected))
        first_bad = -1
        for i in range(n):
            if got[i] != expected[i]:
                first_bad = i
                break
        fail("%s: output mismatch: %d records got vs %d expected%s" %
             (label, len(got), len(expected),
              "" if first_bad < 0 else
              " (first divergence at line %d)" % (first_bad + 1)))
    else:
        print("ok   %s: %d records, peak RSS %d KiB" % (label, len(got), peak))


# --------------------------------------------------------------------------
def main() -> int:
    static_checks()

    work = "/tmp/marline-verify"
    shutil.rmtree(work, ignore_errors=True)
    os.makedirs(work, exist_ok=True)

    # visible case: the shipped sample
    sample_in = os.path.join(REPO, "data", "sample.ndjson")
    sample_cfg = os.path.join(REPO, "data", "sample.config.json")
    if not (os.path.isfile(sample_in) and os.path.isfile(sample_cfg)):
        fail("shipped sample fixture data/sample.ndjson or sample.config.json missing")
    else:
        check_case("visible", sample_in, sample_cfg,
                   os.path.join(work, "visible-out.ndjson"))

    # hidden cases: each dir = params.json + config.json
    if not os.path.isdir(HIDDEN):
        fail("no hidden cases mounted at " + HIDDEN)
    else:
        cases = sorted(n for n in os.listdir(HIDDEN)
                       if os.path.isdir(os.path.join(HIDDEN, n)))
        if len(cases) < 2:
            fail("expected at least 2 hidden cases, found %d" % len(cases))
        for case in cases:
            cdir = os.path.join(HIDDEN, case)
            params = os.path.join(cdir, "params.json")
            cfgp = os.path.join(cdir, "config.json")
            if not (os.path.isfile(params) and os.path.isfile(cfgp)):
                fail("%s: missing params.json or config.json" % case)
                continue
            cwork = os.path.join(work, case)
            os.makedirs(cwork, exist_ok=True)
            inp = os.path.join(cwork, "input.ndjson")
            r = subprocess.run([sys.executable, GEN, params, inp],
                               capture_output=True, text=True)
            if r.returncode != 0:
                fail("%s: input generation failed: %s" % (case, r.stderr.strip()))
                continue
            check_case(case, inp, cfgp, os.path.join(cwork, "out.ndjson"))

    if fails:
        print("FAILURES:")
        for m in fails:
            print("  - " + m)
        return 1
    print("ALL PASS (streaming static gate, correctness, RSS ceiling)")
    return 0


if __name__ == "__main__":
    sys.exit(main())