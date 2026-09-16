#!/bin/bash
# Verifier for nock-meridian (upstream-clone real-issue debugging task on
# pypa/pip).
#
# Requirements, in order:
#   0. Integrity: interpreter+site-packages and the /app/src deliverable tree
#      are pinned to build-time manifests stored under /tests (re-uploaded by
#      harbor at verify time, so beyond the agent's reach); /opt/golden is
#      pinned to a fixed SHA-256. The verifier itself runs on an isolated
#      interpreter (python3 -S: no site-packages, no sitecustomize), every
#      subprocess python is invoked with explicit paths, and planted
#      bytecode / wrappers / hooks are rejected (see checks 0d-0f). Blocks
#      sitecustomize/.pth/interpreter wrappers, sourceless .pyc plants,
#      git-exclude-hidden helpers, /app-level hooks and golden-test edits.
#   1. Provenance of /app/src: HEAD is still the pinned parent commit, the
#      only work-tree changes are a non-empty subset of the three allowed
#      fix files (and link.py must be among them), there are no untracked
#      files, and the upstream fix commit is NOT reachable in the clone's
#      object store.
#   2. The AGENT'S OWN reproduction deliverable /app/reproduce.py must pass
#      (exit 0, single-component name) against the repaired tree AND must
#      fail (nonzero, corrupted '/'-containing name) against a pristine copy
#      of the parent commit materialised with `git archive` into a fresh
#      random directory -- i.e. it genuinely reproduces the bug.
#   3. The project's own regression test for this bug (the fix-commit
#      tests/unit/test_link.py extracted at build time into /opt/golden)
#      passes against the repaired tree.
#   4. A slice of the project's own existing unit suite stays green
#      (tests/unit/test_link.py + tests/unit/test_operations_prepare.py).
#   5. Every hidden case directory under /tests/hidden passes (each run from
#      a fresh random working directory); there must be at least two.
#
# Reward is binary and written on every exit path (the trap covers crashes).
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier

python3 -S - <<'PY'
import os
import posixpath
import secrets
import shutil
import subprocess
import sys
import tempfile

SRC = "/app/src"
PARENT_SHA = "ba52753ecf1803e5b6b5dfb2782835266a71c470"
FIX_SHA = "10dfb6b9005484578b386f64b9f36982e3dc6679"
GOLDEN = "/opt/golden/test_link.py"
GOLDEN_DIR = "/opt/golden"
REPRO = "/app/reproduce.py"
HIDDEN = "/tests/hidden"
MANIFEST_DIR = "/tests/manifests"
WALKER = "/tests/verify_walk.py"

# All tools whose verdict the checks below rely on are invoked by absolute
# path, so a planted directory earlier on PATH (or a swapped wrapper) can
# never shadow them. The walker pins /usr/local and site-packages; the core
# binaries live in /usr/bin and are resolved explicitly.
GIT_BIN = "/usr/bin/git"
SHA_BIN = "/usr/bin/sha256sum"
TAR_BIN = "/usr/bin/tar"

# Absolute interpreter path. The verifier heredoc runs under `python3 -S`;
# subprocesses that need the installed library set (pytest) run WITHOUT the
# -S flag but with a controlled cwd and PYTHONPATH, so any planted
# sitecustomize is unreachable from them too.
SUB_PY = sys.executable
PY_BIN_SHA256 = "0e6475dfda68a9b2d93501449fc47593ca169010e8f4881577b97463fd0c1263"

ALLOWED_FILES = {
    "src/pip/_internal/models/link.py",
    "src/pip/_internal/network/download.py",
    "src/pip/_internal/operations/prepare.py",
}

failures = []


def run(cmd, cwd=None, env=None):
    return subprocess.run(cmd, cwd=cwd, env=env, capture_output=True, text=True)


def walk_check(kind, manifest):
    return subprocess.run(
        [SUB_PY, "-S", WALKER, "check", kind, manifest],
        capture_output=True, text=True,
    )


def parse_filename(stdout: str):
    for line in (stdout or "").splitlines():
        if line.startswith("FILENAME:"):
            return line.split(":", 1)[1].strip()
    return None


def single_component(name: str) -> bool:
    if not name:
        return False
    if "/" in name:
        return False
    if posixpath.basename(name) != name:
        return False
    return name not in (".", "..")


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
            "the /app/src tree differs from the pinned checkout (only the "
            "three fix files may change):\n"
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
        r = run([SHA_BIN, GOLDEN])
        live_golden = r.stdout.split()[0] if r.returncode == 0 else None
        if live_golden != golden_expected:
            failures.append(
                "/opt/golden/test_link.py was modified; it must be left as "
                "the fix-commit regression test"
            )

# 0d2) the GOLDEN directory is exactly the single pinned regression test and
# nothing else. pytest loads a conftest.py from the directory of the test file
# it collects, so a file the agent plants next to the golden test (the trial
# runs as root and /opt is writable) could fake a pass on an unfixed tree.
# The directory must contain exactly test_link.py, and no conftest.py may be
# loadable from any ancestor directory of it.
if os.path.isdir(GOLDEN_DIR):
    entries = sorted(os.listdir(GOLDEN_DIR))
    if entries != ["test_link.py"]:
        failures.append(
            "/opt/golden contains entries other than test_link.py (no planted "
            "conftest or helpers are allowed there):\n" + "\n".join(entries)
        )
else:
    failures.append(f"missing golden directory {GOLDEN_DIR}")
for p in ("/conftest.py", "/opt/conftest.py", "/opt/golden/conftest.py"):
    if os.path.exists(p):
        failures.append(f"planted pytest conftest must not exist: {p}")

# 0d) the interpreter binary is the pinned one (inline hash, independent of
# the usrlocal manifest so a swapped python cannot hide behind a forked
# checker).
r = run([SHA_BIN, "/usr/local/bin/python3"])
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

# --- 1) provenance: revision, scoped diff, no strays, no fix commit --------
head = run([GIT_BIN, "-C", SRC, "rev-parse", "HEAD"])
if head.returncode != 0 or head.stdout.strip() != PARENT_SHA:
    failures.append(
        f"checkout HEAD is {head.stdout.strip()!r}, expected {PARENT_SHA}: "
        "the agent must fix the bug in place, not change the revision"
    )

status = run([GIT_BIN, "-C", SRC, "status", "--porcelain", "--untracked-files=all"])
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
        if "src/pip/_internal/models/link.py" not in modified:
            failures.append(
                "src/pip/_internal/models/link.py is not among the modified "
                "files; the URL-name derivation lives there"
            )
        for path in modified:
            if path not in ALLOWED_FILES:
                failures.append(f"modified file outside the fix: {path}")

probe = run([GIT_BIN, "-C", SRC, "cat-file", "-e", FIX_SHA])
if probe.returncode == 0:
    failures.append(
        "the upstream fix commit is reachable in the /app/src object store; "
        "the agent must derive the fix from the code, not replay the commit"
    )

# --- 2) the AGENT'S OWN reproduction, both directions ----------------------
# The reproduction runs under `python3 -S` (no sitecustomize/site-packages can
# hook it) and is passed the checkout path; it may only use the standard
# library plus the checkout's own source, which is all -S provides.
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
    repaired = run([SUB_PY, "-S", REPRO, SRC], cwd="/tmp", env=repro_env)
    out = repaired.stdout or ""
    name = parse_filename(out)
    if repaired.returncode != 0:
        tail = out[-3000:] + "\n" + (repaired.stderr or "")[-1500:]
        failures.append(
            "the reproduction FAILED against the repaired tree (it must exit "
            "0 there):\n" + tail
        )
    elif name is None:
        failures.append("the reproduction printed no 'FILENAME: <name>' line")
    elif not single_component(name):
        failures.append(
            f"repaired-tree file name {name!r} is not a single path component"
        )

    # Materialise a pristine copy of the parent commit into a fresh random
    # directory (never a guessable path) and run the SAME reproduction on it.
    pristine_dir = None
    archive = subprocess.run(
        [GIT_BIN, "-C", SRC, "archive", PARENT_SHA], capture_output=True
    )
    if archive.returncode != 0:
        failures.append(
            "could not materialise the pristine parent commit from the clone: "
            + (archive.stderr or archive.stdout or b"").decode(errors="replace")[-500:]
        )
    else:
        pristine_dir = tempfile.mkdtemp(
            prefix="nm-" + secrets.token_hex(8) + "-", dir="/tmp"
        )
        untar = subprocess.run(
            [TAR_BIN, "-xf", "-", "-C", pristine_dir],
            input=archive.stdout, capture_output=True,
        )
        if untar.returncode != 0:
            failures.append("extracting the pristine tree failed")
        else:
            buggy = run([SUB_PY, "-S", REPRO, pristine_dir], cwd="/tmp", env=repro_env)
            out2 = buggy.stdout or ""
            name2 = parse_filename(out2)
            if buggy.returncode == 0:
                failures.append(
                    "the reproduction PASSED against the pristine buggy tree; "
                    "it must fail there to genuinely reproduce the bug"
                )
            elif name2 is None or "/" not in name2:
                failures.append(
                    "on the pristine buggy tree the reproduction did not show "
                    "the corrupted (path-separator) file name:\n"
                    + ((out2 or "(no output)")[-3000:])
                )
    if pristine_dir:
        shutil.rmtree(pristine_dir, ignore_errors=True)

# --- 3) the project's own regression test for this bug -----------------------
# --confcutdir=/opt/golden means pytest refuses to load conftest.py from any
# ancestor of /opt/golden; combined with the 0d2 directory check, the golden
# run can only ever load the single pinned test file. cwd is a neutral dir so
# no agent-controlled cwd metadata leaks into collection.
golden_env = dict(os.environ)
golden_env["PYTHONPATH"] = SRC + "/src"
for k in ("PYTHONSTARTUP", "PYTHONHOME", "PYTHONUSERBASE"):
    golden_env.pop(k, None)
golden = run(
    [SUB_PY, "-m", "pytest", "-q", "-o", "addopts=", "-p", "no:cacheprovider",
     "--confcutdir", GOLDEN_DIR, GOLDEN],
    cwd="/tmp", env=golden_env,
)
if golden.returncode != 0:
    tail = (golden.stdout or "")[-5000:] + "\n" + (golden.stderr or "")[-1500:]
    failures.append("the project's regression test for this bug FAILED:\n" + tail)

# --- 4) the project's own existing unit slice stays green --------------------
exec_res = run(
    [SUB_PY, "-m", "pytest", "-q", "-o", "addopts=", "-p", "no:cacheprovider",
     "--confcutdir", SRC,
     "tests/unit/test_link.py", "tests/unit/test_operations_prepare.py"],
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
        # Fresh random working directory per case: nothing an agent left in a
        # guessable /tmp location can be picked up as conftest or fixtures.
        workdir = tempfile.mkdtemp(prefix="nm-case-" + secrets.token_hex(6) + "-", dir="/tmp")
        result = run(
            [SUB_PY, "-m", "pytest", "-q", "-o", "addopts=", "-p", "no:cacheprovider",
             "--confcutdir", case_dir, case_dir],
            cwd=workdir, env=golden_env,
        )
        shutil.rmtree(workdir, ignore_errors=True)
        if result.returncode != 0:
            tail = (result.stdout or "")[-5000:] + "\n" + (result.stderr or "")[-1500:]
            failures.append(f"hidden case '{case}' FAILED:\n" + tail)

print("== nock-meridian verifier ==")
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