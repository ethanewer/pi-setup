#!/bin/bash
# Verifier for plimsoll-bell (upstream-clone real-issue debugging task on
# scipy/scipy).
#
# Requirements, in order:
#   0. Integrity: interpreter+site-packages and the /app/src deliverable tree
#      are pinned to build-time manifests stored under /tests (re-uploaded by
#      harbor at verify time, beyond the agent's reach); /opt/golden is pinned
#      to a fixed SHA-256; planted bytecode / hooks / wrappers are rejected
#      (checks 0d-0g).
#   1. Provenance of /app/src: HEAD is still the pinned parent commit, the
#      only work-tree change is (a non-empty subset of) the fix file
#      scipy/stats/_stats_py.py, there are no untracked files, and the
#      upstream fix commit is NOT reachable in the clone's object store
#      (git log --all shows exactly one commit).
#   2. The AGENT'S OWN reproduction deliverable /app/reproduce.py must pass
#      (exit 0, string statistic == callable statistic) against the repaired
#      tree, resolving scipy from /app/src (editable install), AND must fail
#      (nonzero, ndtr TypeError) against a pristine materialisation of the
#      parent commit (git archive + meson-python's own install plan + parent
#      bytes), with the editable finder disabled via MESONPY_EDITABLE_SKIP --
#      i.e. it genuinely reproduces the bug.
#   3. The project's own regression test for this bug (the fix-commit
#      TestKSTest.test_gh25448 extracted at build time into /opt/golden)
#      passes against the repaired tree.
#   4. A slice of the project's own existing unit suite stays green
#      (scipy/stats/tests/test_stats.py -k "TestKSTest or TestKSOneSample",
#      28 tests).
#   5. Every hidden case directory under /tests/hidden passes (each run from
#      a fresh random working directory); there must be at least two.
#
# Reward is binary and written on every exit path (the trap covers crashes).
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
# A root agent can write the bind-mounted logs dir during the trial; delete any
# pre-planted reward file so it can never win a crash path (the trap below only
# writes 0 when the file is absent, and the ending branches always rewrite it).
rm -f /logs/verifier/reward.txt

python3 -S - <<'PY'
import os
import secrets
import shutil
import subprocess
import sys
import tempfile

SRC = "/app/src"
PARENT_SHA = "0f7f9b2a3121102394c36e8d97bcd3ea7d5da1a1"
FIX_SHA = "0f0a3dd37f88ecd8c4d83a5913df56471274fefa"
BUILD_DIR = "/tmp/sci-build"
GOLDEN = "/opt/golden/test_gh25448.py"
REPRO = "/app/reproduce.py"
HIDDEN = "/tests/hidden"
MANIFEST_DIR = "/tests/manifests"
WALKER = "/tests/verify_walk.py"
MATERIALIZE = "/tests/materialize.py"
FIX_FILE = "scipy/stats/_stats_py.py"

SUB_PY = sys.executable
# Subprocess python for every agent-facing run: -s disables the user site, so
# a sitecustomize.py planted in /root/.local (the trial runs as root with
# HOME=/root) cannot monkeypatch scipy at import time. System site-packages
# (numpy, pytest, ...) remain available; the walker already runs with -S.
PYNOSITE = [sys.executable, "-s"]
PY_BIN_SHA256 = "0e6475dfda68a9b2d93501449fc47593ca169010e8f4881577b97463fd0c1263"  # filled in by the author after the build

failures = []


def run(cmd, cwd=None, env=None):
    return subprocess.run(cmd, cwd=cwd, env=env, capture_output=True, text=True)


def walk_check(kind, manifest):
    return subprocess.run(
        [SUB_PY, "-S", WALKER, "check", kind, manifest],
        capture_output=True, text=True,
    )


def parse_line(stdout: str, prefix: str):
    for line in (stdout or "").splitlines():
        if line.startswith(prefix):
            return line.split(":", 1)[1].strip()
    return None


# --- 0) tamper / wrapper integrity (host-controlled manifests) -------------
usrm = os.path.join(MANIFEST_DIR, "usr_local.sha256")
if not os.path.isfile(usrm):
    failures.append(f"missing /usr/local manifest: {usrm}")
else:
    r = walk_check("usrlocal", usrm)
    if r.returncode != 0:
        body = (r.stdout or "").strip()
        failures.append(
            "interpreter or site-packages modified outside the fix:\n"
            + (body or "(walker reported an error)")
            + "\n" + (r.stderr or "")[-800:]
        )

appm = os.path.join(MANIFEST_DIR, "app_src.sha256")
if not os.path.isfile(appm):
    failures.append(f"missing /app/src manifest: {appm}")
else:
    r = walk_check("appsrc", appm)
    if r.returncode != 0:
        body = (r.stdout or "").strip()
        failures.append(
            "the /app/src tree differs from the pinned checkout (only "
            + FIX_FILE + " may change):\n"
            + (body or "(walker reported an error)")
            + "\n" + (r.stderr or "")[-800:]
        )

if not os.path.isfile(GOLDEN):
    failures.append(f"missing golden test {GOLDEN}")
else:
    golden_expected = None
    gp = os.path.join(MANIFEST_DIR, "golden.sha256")
    if os.path.isfile(gp):
        with open(gp, "r", encoding="utf-8") as fh:
            line = fh.readline().strip()
        golden_expected = line.split()[0] if line else None
    if not golden_expected:
        failures.append(f"missing golden hash: {gp}")
    else:
        r = run(["sha256sum", GOLDEN])
        live_golden = r.stdout.split()[0] if r.returncode == 0 else None
        if live_golden != golden_expected:
            failures.append(
                "/opt/golden/test_gh25448.py was modified; it must be left as "
                "the fix-commit regression test"
            )

# 0d) the interpreter binary is the pinned one (inline hash, independent of
# the usrlocal manifest so a swapped python cannot hide behind a forked
# checker).
r = run(["sha256sum", "/usr/local/bin/python3"])
live_py = r.stdout.split()[0] if r.returncode == 0 else None
if live_py != PY_BIN_SHA256:
    failures.append(
        f"/usr/local/bin/python3 is not the pinned interpreter "
        f"(got {live_py}, want {PY_BIN_SHA256})"
    )

# 0e) /app holds only the checkout, the README and the agent's own
# reproduction -- no sitecustomize.py, no wrapper, no helper next to it.
if os.path.isdir("/app"):
    app_entries = sorted(os.listdir("/app"))
    app_expected = {"src", "README.md", "reproduce.py"}
    unexpected = [e for e in app_entries if e not in app_expected]
    if unexpected:
        failures.append(
            "unexpected entries in /app (no hooks or helpers allowed):\n"
            + "\n".join(unexpected)
        )

# 0f) no planted bytecode anywhere under the deliverable tree (a crafted
# __pycache__ .pyc can shadow source on import; PYTHONDONTWRITEBYTECODE=1 is
# baked into the image so an honest run never creates any).
pyc_hits = []
for dirpath, dirnames, filenames in os.walk(SRC):
    if os.path.basename(dirpath) == "__pycache__":
        pyc_hits.append(dirpath + "/")
    for fn in filenames:
        if fn.endswith((".pyc", ".pyo")):
            pyc_hits.append(os.path.join(dirpath, fn))
if pyc_hits:
    failures.append(
        "bytecode files under /app/src are not allowed:\n" + "\n".join(pyc_hits[:20])
    )

# 0g) no preload injection vector.
if os.path.exists("/etc/ld.so.preload"):
    failures.append("/etc/ld.so.preload must not exist")

# 0h) the whole /tests tree is pinned to the host bytes harbor re-uploads at
# verify time. The agent's container does not mount /tests, but a root agent
# can create extra files there before the upload (e.g. a conftest.py in a
# hidden-case directory that deselects the real tests); docker cp only
# overwrites same-named files. So any file under /tests that is not byte-
# identical to the host tree fails the task.
tsm = os.path.join(MANIFEST_DIR, "tests.sha256")
if not os.path.isfile(tsm):
    failures.append(f"missing /tests manifest: {tsm}")
else:
    r = walk_check("tests", tsm)
    if r.returncode != 0:
        body = (r.stdout or "").strip()
        failures.append(
            "/tests differs from the host tree (extra or modified files are "
            "not allowed):\n"
            + (body or "(walker reported an error)")
            + "\n" + (r.stderr or "")[-800:]
        )

# --- 1) provenance: revision, scoped diff, no strays, no fix commit --------
head = run(["git", "-C", SRC, "rev-parse", "HEAD"])
if head.returncode != 0 or head.stdout.strip() != PARENT_SHA:
    failures.append(
        f"checkout HEAD is {head.stdout.strip()!r}, expected {PARENT_SHA}: "
        "the agent must fix the bug in place, not change the revision"
    )

status = run(["git", "-C", SRC, "status", "--porcelain", "--untracked-files=all"])
modified = []
untracked = []
odd = []
if status.returncode != 0:
    failures.append("git status failed: " + (status.stderr or status.stdout))
else:
    for line in status.stdout.splitlines():
        if len(line) < 4:
            odd.append(line)
            continue
        code = line[:2]
        path = line[3:]
        if line.startswith("??"):
            untracked.append(path)
        elif code in (" M", "M ", "MM", "AM", "A "):
            modified.append(path)
        else:
            odd.append(line)
    if odd:
        failures.append("unexpected git status entries (staged? renamed?):\n" + "\n".join(odd))
    if len(untracked) > 4:
        untracked = untracked[:4] + ["..."]
    if untracked:
        failures.append("untracked files in the repository are not allowed:\n" + "\n".join(untracked))
    if not modified:
        failures.append("no source file was modified: the fix must live in the /app/src tree")
    else:
        if FIX_FILE not in modified:
            failures.append(
                FIX_FILE + " is not among the modified files; the string-null "
                "resolution lives there"
            )
        for path in modified:
            if path != FIX_FILE:
                failures.append(f"modified file outside the fix: {path}")

probe = run(["git", "-C", SRC, "cat-file", "-e", FIX_SHA])
if probe.returncode == 0:
    failures.append(
        "the upstream fix commit is reachable in the /app/src object store; "
        "the agent must derive the fix from the code, not replay the commit"
    )
ncommits = run(["git", "-C", SRC, "rev-list", "--all", "--count"])
if ncommits.returncode == 0 and ncommits.stdout.strip() != "1":
    failures.append(
        "the checkout exposes more than one commit; the pinned parent clone "
        "must stay a single-commit shallow clone"
    )

# --- 2) the AGENT'S OWN reproduction, both directions ----------------------
# The reproduction runs under the normal interpreter (scipy imports need
# numpy from site-packages); the editable finder resolves scipy to the
# repaired /app/src tree. For the pristine run the finder is disabled with
# MESONPY_EDITABLE_SKIP=<build dir>, so the checkout path on sys.path wins.
repro_env = dict(os.environ)
repro_env.pop("PYTHONPATH", None)
for k in ("PYTHONSTARTUP", "PYTHONHOME", "PYTHONUSERBASE", "PYTHONINSPECT"):
    repro_env.pop(k, None)

if not os.path.isfile(REPRO):
    failures.append(
        "missing deliverable /app/reproduce.py -- the agent must write its "
        "own failing reproduction"
    )
else:
    repaired = run(PYNOSITE + [REPRO, SRC], cwd="/tmp", env=repro_env)
    out = repaired.stdout or ""
    sp = parse_line(out, "SCIPY:")
    got = parse_line(out, "STRING_STATISTIC:")
    ref = parse_line(out, "CALLABLE_STATISTIC:")
    if repaired.returncode != 0:
        tail = out[-3000:] + "\n" + (repaired.stderr or "")[-1500:]
        failures.append(
            "the reproduction FAILED against the repaired tree (it must exit "
            "0 there):\n" + tail
        )
    if sp is None or not sp.startswith(SRC):
        failures.append(
            f"the reproduction did not import scipy from the checkout "
            f"(SCIPY line: {sp!r})"
        )
    if got is None or ref is None:
        failures.append(
            "the reproduction printed no CALLABLE_STATISTIC/STRING_STATISTIC "
            "values"
        )

    # Materialise a pristine copy of the parent commit into a fresh random
    # directory (never a guessable path) and run the SAME reproduction on it.
    pristine_dir = None
    try:
        pristine_dir = tempfile.mkdtemp(
            prefix="psb-" + secrets.token_hex(8) + "-", dir="/tmp"
        )
        mat = run(PYNOSITE + [MATERIALIZE, pristine_dir], cwd="/tmp")
        if mat.returncode != 0:
            failures.append(
                "could not materialise the pristine parent tree: "
                + ((mat.stderr or mat.stdout or "")[-800:])
            )
        else:
            p_env = dict(repro_env)
            p_env["MESONPY_EDITABLE_SKIP"] = BUILD_DIR
            buggy = run(PYNOSITE + [REPRO, pristine_dir], cwd="/tmp", env=p_env)
            out2 = buggy.stdout or ""
            err2 = buggy.stderr or ""
            if buggy.returncode == 0:
                failures.append(
                    "the reproduction PASSED against the pristine buggy tree; "
                    "it must fail there to genuinely reproduce the bug"
                )
            elif "ndtr" not in out2 + err2:
                failures.append(
                    "on the pristine buggy tree the reproduction did not show "
                    "the ndtr TypeError:\n" + ((out2 + "\n" + err2)[-2000:])
                )
    finally:
        if pristine_dir:
            shutil.rmtree(pristine_dir, ignore_errors=True)

# --- 3) the project's own regression test for this bug -----------------------
golden_env = dict(os.environ)
golden_env["PYTHONPATH"] = SRC
for k in ("PYTHONSTARTUP", "PYTHONHOME", "PYTHONUSERBASE"):
    golden_env.pop(k, None)
golden = run(
    PYNOSITE + ["-m", "pytest", "-q", "-o", "addopts=", "-o", "filterwarnings=ignore",
     "-p", "no:cacheprovider", GOLDEN],
    cwd="/tmp", env=golden_env,
)
if golden.returncode != 0:
    tail = (golden.stdout or "")[-5000:] + "\n" + (golden.stderr or "")[-1500:]
    failures.append("the project's regression test for this bug FAILED:\n" + tail)

# --- 4) the project's own existing unit slice stays green --------------------
exec_res = run(
    PYNOSITE + ["-m", "pytest", "-q", "-o", "addopts=", "-o", "filterwarnings=ignore",
     "-p", "no:cacheprovider", "scipy/stats/tests/test_stats.py",
     "-k", "TestKSTest or TestKSOneSample"],
    cwd=SRC, env=golden_env,
)
if exec_res.returncode != 0:
    tail = (exec_res.stdout or "")[-5000:] + "\n" + (exec_res.stderr or "")[-1500:]
    failures.append("the project's existing unit slice failed after the change:\n" + tail)

# --- 5) authored hidden cases (>= 2, each must pass) --------------------------
if not os.path.isdir(HIDDEN):
    failures.append("no hidden cases present")
else:
    cases = sorted(
        d for d in os.listdir(HIDDEN) if os.path.isdir(os.path.join(HIDDEN, d))
    )
    if len(cases) < 2:
        failures.append(f"expected at least 2 hidden cases, found {cases!r}")
    for case in cases:
        case_dir = os.path.join(HIDDEN, case)
        test_files = sorted(
            name for name in os.listdir(case_dir)
            if name.startswith("test_") and name.endswith(".py")
        )
        if not test_files:
            failures.append(f"hidden case '{case}' has no pytest files")
            continue
        workdir = tempfile.mkdtemp(prefix="psb-case-" + secrets.token_hex(6) + "-", dir="/tmp")
        result = run(
            PYNOSITE + ["-m", "pytest", "-q", "-o", "addopts=", "-o", "filterwarnings=ignore",
             "-p", "no:cacheprovider", case_dir],
            cwd=workdir, env=golden_env,
        )
        shutil.rmtree(workdir, ignore_errors=True)
        if result.returncode != 0:
            tail = (result.stdout or "")[-5000:] + "\n" + (result.stderr or "")[-1500:]
            failures.append(f"hidden case '{case}' FAILED:\n" + tail)

print("== plimsoll-bell verifier ==")
if failures:
    for item in failures:
        print("FAIL:", item)
    with open("/logs/verifier/reward.txt", "w", encoding="utf-8") as fh:
        fh.write("0\n")
    sys.exit(0)

print("all checks passed")
with open("/logs/verifier/reward.txt", "w", encoding="utf-8") as fh:
    fh.write("1\n")
sys.exit(0)
PY