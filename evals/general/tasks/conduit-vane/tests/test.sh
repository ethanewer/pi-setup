#!/usr/bin/env bash
# Verifier for conduit-vane (executes-deliverable).
#
# Exercises the deliverable, /app/workspace/, four ways, in order:
#
#   1. `cargo build --workspace`  must exit 0 (offline; the workspace has no
#      third-party dependencies);
#   2. `cargo test --workspace`   must exit 0 (the shipped test suite stays
#      green after the change);
#   3. sources may not contain the token `unsafe` (no unsafe anywhere);
#   4. three downstream consumer crates (a semver sentinel, the fob station
#      SDK, and a resilience probe) must compile against the workspace's
#      public API — the sentinel against the pre-change API, the other two
#      against the new resume capability — and pass their behavioral checks
#      on every hidden fixture capture.
#
# Writes reward 1 only when every check passes; any failure prints a readable
# list first and writes 0.
# Guarantee a reward on every exit path.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier

if [ ! -d /app/workspace ]; then
  echo "missing deliverable /app/workspace" >&2
  echo "0" > /logs/verifier/reward.txt
  exit 0
fi

export CARGO_NET_OFF=true
export CARGO_BUILD_JOBS=1
export HOME=/root

python3 - <<'PY'
import os
import shutil
import subprocess
import sys

WORKSPACE = "/app/workspace/"
failures = []


def fail(msg):
    failures.append(msg)


def run(cmd, cwd=None, env=None, timeout=1500):
    e = dict(os.environ)
    e["CARGO_NET_OFF"] = "true"
    e["CARGO_BUILD_JOBS"] = "1"
    e["HOME"] = "/root"
    if env:
        e.update(env)
    try:
        r = subprocess.run(cmd, cwd=cwd, env=e, capture_output=True, text=True,
                           timeout=timeout)
        return r
    except subprocess.TimeoutExpired:
        fail("timeout running: " + " ".join(cmd))
        return None


def tail_output(r, n=30):
    if r is None:
        return ""
    out = (r.stdout or "") + (r.stderr or "")
    lines = out.strip().splitlines()
    return "\n".join(lines[-n:])


# ---- 1 & 2. workspace build + test ------------------------------------
r = run(["cargo", "build", "--workspace", "--offline"], cwd=WORKSPACE)
if r is None:
    pass
elif r.returncode != 0:
    fail("cargo build --workspace failed:\n" + tail_output(r))

r = run(["cargo", "test", "--workspace", "--offline"], cwd=WORKSPACE)
if r is None:
    pass
elif r.returncode != 0:
    fail("cargo test --workspace failed:\n" + tail_output(r))

# ---- 3. no unsafe token anywhere in workspace sources ------------------
SOURCE_EXTENSIONS = (".rs", ".toml", ".md", ".txt")
hits = []
for root, dirs, files in os.walk(WORKSPACE):
    if "target" in root.split(os.sep):
        continue
    if ".git" in root.split(os.sep):
        continue
    for fn in files:
        if not fn.endswith(SOURCE_EXTENSIONS):
            continue
        path = os.path.join(root, fn)
        try:
            with open(path, "r", errors="replace") as fh:
                for i, line in enumerate(fh, 1):
                    if "unsafe" in line:
                        hits.append("%s:%d" % (path[len(WORKSPACE) + 1:], i))
        except OSError:
            continue
if hits:
    fail("unexpected token 'unsafe' in workspace sources:\n  "
         + "\n  ".join(hits[:20]))

# ---- 3b. repository shape: real git history + shipped volume -----------
def count_rs_loc(root_dir):
    total = 0
    for root, dirs, files in os.walk(root_dir):
        if "target" in root.split(os.sep) or ".git" in root.split(os.sep):
            continue
        for fn in files:
            if fn.endswith(".rs"):
                path = os.path.join(root, fn)
                try:
                    with open(path, "r", errors="replace") as fh:
                        total += sum(1 for _ in fh)
                except OSError:
                    continue
    return total

r = subprocess.run(["git", "log", "--oneline"], cwd=WORKSPACE,
                   capture_output=True, text=True)
commits = len([l for l in (r.stdout or "").splitlines() if l.strip()])
if commits < 8:
    fail("workspace git history has only %d commits" % commits)
rs_loc = count_rs_loc(WORKSPACE)
if rs_loc < 3800:
    fail("workspace ships only %d lines of Rust source (expected >= 3800)"
         % rs_loc)

# ---- 4. downstream consumers -------------------------------------------
HIDDEN = "/tests/hidden"
CONSUMERS = os.path.join(HIDDEN, "consumers")
if not os.path.isdir(CONSUMERS):
    fail("no hidden consumers directory")
    sys.exit(0)

base = "/tmp/vcons"
shutil.rmtree(base, ignore_errors=True)
os.makedirs(base)

# copy the agent's (possibly modified) library crates once
for crate in ("veldt-core", "veldt-measure", "veldt-transport"):
    src = os.path.join(WORKSPACE, "crates", crate)
    dst = os.path.join(base, "deps", crate)
    if not os.path.isdir(src):
        fail("workspace is missing crate %s" % crate)
        continue
    shutil.copytree(src, dst,
                    ignore=shutil.ignore_patterns("target", ".git", "*.o"))

for name in ("sentinel", "station", "resilience"):
    src_dir = os.path.join(CONSUMERS, name)
    dst_dir = os.path.join(base, name)
    if not os.path.isdir(src_dir):
        fail("hidden consumer '%s' missing from /tests" % name)
        continue
    shutil.copytree(src_dir, dst_dir,
                    ignore=shutil.ignore_patterns("target", ".git"))
    r = run(["cargo", "build", "--offline"], cwd=dst_dir, timeout=1500)
    if r is None:
        continue
    if r.returncode != 0:
        fail("consumer '%s' does not compile:\n%s" % (name, tail_output(r)))
        continue

# the semver sentinel is behavioral too: it asserts the pre-change API is
# behaviorally intact (checksums, conversions, framing, sessions).
sentinel_bin = os.path.join(base, "sentinel", "target", "debug", "sentinel")
r = run([sentinel_bin], cwd=base, timeout=120)
if r is None:
    pass
elif r.returncode != 0:
    fail("sentinel run failed:\n" + tail_output(r))
elif "SENTINEL OK" not in (r.stdout or ""):
    fail("sentinel did not print its pass marker")

cases = sorted(
    n for n in os.listdir(HIDDEN)
    if os.path.isdir(os.path.join(HIDDEN, n)) and n != "consumers")
if len(cases) < 2:
    fail("expected at least two hidden fixture cases, found %d" % len(cases))

for case in cases:
    capture = os.path.join(HIDDEN, case, "capture.bin")
    if not os.path.exists(capture):
        fail("hidden case %s has no capture.bin" % case)
        continue
    for name, args in (("station", []), ("resilience", [])):
        binary = os.path.join(base, name, "target", "debug", name)
        if not os.path.exists(binary):
            fail("consumer '%s' binary was not produced" % name)
            continue
        r = run([binary, capture], cwd=base, timeout=300)
        if r is None:
            continue
        if r.returncode != 0:
            fail("consumer '%s' failed on %s:\n%s" % (name, case,
                                                      tail_output(r)))
            continue
        out = (r.stdout or "").strip()
        marker = "STATION OK" if name == "station" else "RESILIENCE OK"
        if marker not in out:
            fail("consumer '%s' on %s did not print its pass marker"
                 % (name, case))

if failures:
    print("FAILURES:")
    for m in failures:
        print("  - " + m)
    open("/logs/verifier/reward.txt", "w").write("0")
    sys.exit(0)

print("ALL PASS (workspace builds, tests green, no unsafe, consumers ok)")
open("/logs/verifier/reward.txt", "w").write("1")
sys.exit(0)
PY