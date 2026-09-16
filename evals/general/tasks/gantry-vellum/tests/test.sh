#!/bin/bash
# Verifier for gantry-vellum.
#
# Drives the /app/enrichd service over four workloads (the visible fixture
# plus three hidden ones), feeding events one batch at a time and sampling
# the process family RSS from /proc between batches.  Every run must exit 0,
# emit exactly one enriched object per input event matching the enrichment
# contract, and show RSS growth between the first and second half of the run
# below the declared bound.  The shipped unit suite must stay green.
#
# Writes /logs/verifier/reward.txt = 1 (all checks pass) or 0 (any fail).
# The EXIT trap guarantees a reward file on every exit path.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

set -u
mkdir -p /logs/verifier

if [ ! -f /app/enrichd/enrichd/cache.py ]; then
  echo "missing deliverable /app/enrichd" >&2
  echo "0" > /logs/verifier/reward.txt
  exit 0
fi

python3 - <<'PY'
import json
import math
import os
import re
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path

APP = Path("/app/enrichd")
TESTROOT = Path("/tests")
BOUND_MB = 14.0          # max allowed median RSS growth, second half vs first half
BATCH = 40               # events written per pacing step
PACE = 1.0               # seconds between pacing steps (RSS sample after each)
MIN_SAMPLES = 10
CASE_TIMEOUT = 300.0     # wall-clock guard for one case
FLOAT_TOL = 1e-6
ENRICHED_FIELDS = ("client_key", "day", "segment",
                   "digest_mean", "digest_energy", "digest_l1")

failures = []


def fail(msg, case=None):
    failures.append(("[%s] %s" % (case, msg)) if case else msg)


def median(xs):
    s = sorted(xs)
    n = len(s)
    return (s[n // 2] + s[(n - 1) // 2]) / 2.0


def vm_rss_kb(pid):
    try:
        with open("/proc/%d/status" % pid, "r", encoding="utf-8") as fh:
            for line in fh:
                if line.startswith("VmRSS:"):
                    return int(line.split()[1])
    except (FileNotFoundError, ProcessLookupError, ValueError, OSError):
        pass
    return 0


def children_of(pid):
    kids = []
    try:
        entries = os.listdir("/proc")
    except OSError:
        return kids
    for name in entries:
        if not name.isdigit():
            continue
        try:
            with open("/proc/%s/status" % name, "r", encoding="utf-8") as fh:
                m = re.search(r"^PPid:\s+(\d+)", fh.read(), re.M)
        except (FileNotFoundError, OSError):
            continue
        if m and int(m.group(1)) == pid:
            kids.append(int(name))
    return kids


def tree_rss_kb(pid):
    """RSS of pid plus its whole descendant tree (summed)."""
    total = 0
    seen = set()
    stack = [pid]
    while stack:
        p = stack.pop()
        if p in seen:
            continue
        seen.add(p)
        total += vm_rss_kb(p)
        stack.extend(children_of(p))
    return total


def fields_ok(got, want, case):
    """Structural equality with float tolerance for the enrichment contract."""
    if sorted(got.keys()) != sorted(want.keys()):
        fail("%s: key set %s != expected %s" %
             (case, sorted(got.keys()), sorted(want.keys())))
        return
    for k, v in want.items():
        g = got.get(k)
        if g is None:
            fail("%s: missing key %r" % (case, k))
            continue
        if isinstance(v, float):
            if not math.isclose(g, v, rel_tol=1e-6, abs_tol=1e-9):
                fail("%s: %s=%r want %r" % (case, k, g, v))
        elif g != v:
            fail("%s: %s=%r want %r" % (case, k, g, v))


def run_case(name, workload_path, expected_path, workdir):
    wdir = Path(workdir) / name
    wdir.mkdir(parents=True, exist_ok=True)
    out_path = wdir / "out.jsonl"
    err_path = wdir / "stderr.log"

    try:
        events = [l for l in workload_path.read_text().splitlines() if l.strip()]
    except OSError as exc:
        fail("%s: cannot read workload: %s" % (name, exc))
        return
    try:
        expected = [json.loads(l) for l in expected_path.read_text().splitlines() if l.strip()]
    except OSError as exc:
        fail("%s: cannot read expectation: %s" % (name, exc))
        return
    if len(expected) != len(events):
        fail("%s: expectation has %d lines for %d events" % (name, len(expected), len(events)))
        return

    cmd = [sys.executable, "-m", "enrichd", "process",
           "--output", str(out_path), "--flush-every", "4"]
    null = open(os.devnull, "wb")
    errfh = open(err_path, "wb")
    try:
        proc = subprocess.Popen(cmd, cwd=str(APP), stdin=subprocess.PIPE,
                                stdout=null, stderr=errfh)
    except OSError as exc:
        fail("%s: cannot spawn service: %s" % (name, exc))
        return

    samples = []          # (elapsed_sec, rss_kb)
    start = time.monotonic()
    deadline = start + CASE_TIMEOUT
    sent = 0
    broken = False
    try:
        for i in range(0, len(events), BATCH):
            if time.monotonic() > deadline:
                fail("%s: pacing deadline passed (host too slow?)" % name)
                broken = True
                break
            chunk = events[i:i + BATCH]
            try:
                proc.stdin.write(("\n".join(chunk) + "\n").encode("utf-8"))
                proc.stdin.flush()
            except (BrokenPipeError, OSError):
                broken = True
                break
            sent += len(chunk)
            time.sleep(PACE)
            samples.append((time.monotonic() - start, tree_rss_kb(proc.pid)))
    finally:
        try:
            proc.stdin.close()
        except OSError:
            pass

    rc = None
    try:
        rc = proc.wait(timeout=120)
    except subprocess.TimeoutExpired:
        proc.kill()
        try:
            rc = proc.wait(timeout=30)
        except subprocess.TimeoutExpired:
            rc = -1
    finally:
        errfh.close()
        null.close()

    if broken:
        if len(events) > sent:
            fail("%s: input could not be fully delivered (sent %d/%d)" %
                 (name, sent, len(events)))
        return
    if rc != 0:
        tail = ""
        try:
            tail = err_path.read_text().splitlines()[-5:]
        except OSError:
            pass
        fail("%s: service exited rc=%r%s" % (name, rc,
             (" stderr: " + " | ".join(tail)) if tail else ""))
        return

    # --- output correctness -------------------------------------------------
    try:
        got_lines = [l for l in out_path.read_text().splitlines() if l.strip()]
    except OSError as exc:
        fail("%s: no output file: %s" % (name, exc))
        return
    if len(got_lines) != len(events):
        fail("%s: emitted %d lines for %d events" % (name, len(got_lines), len(events)))
        return
    for idx, (gl, el) in enumerate(zip(got_lines, expected)):
        try:
            got = json.loads(gl)
        except ValueError:
            fail("%s: line %d is not valid JSON" % (name, idx))
            continue
        fields_ok(got, el, name)

    # --- memory growth between the first and second half -------------------
    if len(samples) < MIN_SAMPLES:
        fail("%s: only %d RSS samples (need >= %d)" % (name, len(samples), MIN_SAMPLES))
        return
    mid = (samples[0][0] + samples[-1][0]) / 2.0
    first = [rss for t, rss in samples if t < mid]
    second = [rss for t, rss in samples if t >= mid]
    if not first or not second:
        fail("%s: RSS samples all on one side of the midpoint" % name)
        return
    m1, m2 = median(first) / 1024.0, median(second) / 1024.0
    growth = m2 - m1
    if growth > BOUND_MB:
        fail("%s: RSS growth first->second half %.1f MB exceeds bound %.1f MB "
             "(samples=%d median %.1f -> %.1f MB)" %
             (name, growth, BOUND_MB, len(samples), m1, m2))
    else:
        print("  [%s] RSS median %.1f -> %.1f MB (growth %.1f MB, samples %d): ok"
              % (name, m1, m2, growth, len(samples)))


def main():
    if not APP.is_dir():
        fail("deliverable /app/enrichd missing")
        write_reward(0)
        return
    if not (APP / "enrichd" / "cli.py").is_file():
        fail("/app/enrichd is not a working enrichd checkout")
        write_reward(0)
        return

    workdir = "/tmp/gantry-vellum-verify"
    shutil.rmtree(workdir, ignore_errors=True)
    os.makedirs(workdir)

    cases = [("visible",
              APP / "workloads" / "visible.jsonl",
              TESTROOT / "expected_visible.out.jsonl")]
    hidden = TESTROOT / "hidden"
    if hidden.is_dir():
        for d in sorted(hidden.iterdir()):
            if d.is_dir():
                cases.append((d.name,
                              d / "workload.jsonl",
                              d / "expected.out.jsonl"))
    else:
        fail("no hidden cases directory")
    if len(cases) < 3:
        fail("expected >= 3 workloads (visible + hidden)")

    print("gantry-vellum verifier: %d workloads against /app/enrichd" % len(cases))
    for name, wl, ex in cases:
        run_case(name, wl, ex, workdir)

    # --- the shipped unit suite must stay green -----------------------------
    r = subprocess.run([sys.executable, "-m", "unittest", "discover",
                        "-s", "tests", "-t", "."],
                       cwd=str(APP), capture_output=True, text=True, timeout=180)
    if r.returncode != 0:
        tail = (r.stderr or r.stdout).strip().splitlines()[-15:]
        fail("unit suite failed: " + " | ".join(tail))

    if failures:
        print("FAILURES: %d" % len(failures))
        for m in failures:
            print("  - " + m)
        write_reward(0)
    else:
        print("ALL PASS (%d workloads, unit suite green)" % len(cases))
        write_reward(1)


def write_reward(v):
    with open("/logs/verifier/reward.txt", "w", encoding="utf-8") as fh:
        fh.write(str(v))


if __name__ == "__main__":
    main()
PY