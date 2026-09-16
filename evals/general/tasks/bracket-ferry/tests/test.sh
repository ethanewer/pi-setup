#!/bin/bash
# Verifier for bracket-ferry (upstream-clone debugging task on pypa/pip).
#
# Requirements, in order:
#   1. Provenance of /app/src: HEAD is still the pinned parent commit, the
#      only work-tree change is to src/pip/_internal/commands/show.py, there
#      are no untracked files, and the upstream fix commit is NOT reachable
#      in the clone's object store (so it cannot have been replayed with
#      `git show`/`git cherry-pick`).
#   2. The project's own regression test for this bug (extracted from the fix
#      commit at build time into /opt/golden/test_command_show.py) passes
#      against the repaired tree.
#   3. A slice of the project's own existing unit suite stays green
#      (tests/unit/test_commands.py, tests/unit/metadata/test_metadata.py).
#   4. Every hidden case directory under /tests/hidden passes; there must be
#      at least two of them.
#
# Reward is binary and written on every exit path (the trap covers crashes).
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier

python3 - <<'PY'
import os
import subprocess
import sys

SRC = "/app/src"
PARENT_SHA = "b98096615dc25fb9438f87bacfa446589d34e97d"
FIX_SHA = "4ab145f7b7e3c4e4617cbff3743fde7dff802ebd"
GOLDEN = "/opt/golden/test_command_show.py"
HIDDEN = "/tests/hidden"
PYTHON = sys.executable

failures = []


# --- 0) tamper / wrapper integrity (host-controlled manifests) -------------
# /usr/local (interpreter + site-packages) and /app/src (deliverable tree) are
# pinned to build-time manifests, and /opt/golden to a fixed hash. Every
# manifest and this verifier live in /tests, which harbor re-uploads from the
# host at verify time, so an agent cannot forge them. This closes the
# "wrapper that intercepts the call" class: a planted sitecustomize.py, a
# replaced python3, a .pth hook, a sourceless .pyc, a helper file hidden with
# git exclude, or any change outside the single fix file now fails.
MANIFEST_DIR = "/tests/manifests"
WALKER = "/tests/verify_walk.py"


def run(cmd, cwd=None, env=None):
    return subprocess.run(
        cmd, cwd=cwd, env=env, capture_output=True, text=True
    )


def _walk_check(kind, manifest):
    return subprocess.run(
        [PYTHON, WALKER, "check", kind, manifest],
        capture_output=True, text=True,
    )


# 0a) interpreter + site-packages must be byte-identical to the build.
usrm = os.path.join(MANIFEST_DIR, "usr_local.sha256")
if not os.path.isfile(usrm):
    failures.append(f"missing /usr/local manifest: {usrm}")
else:
    r = _walk_check("usrlocal", usrm)
    if r.returncode != 0:
        body = (r.stdout or "").strip()
        failures.append(
            "interpreter or site-packages modified outside the fix:\n"
            + (body or "(walker reported an error)")
            + "\n" + (r.stderr or "")[-800:]
        )

# 0b) the /app/src deliverable tree, except the one allowed fix file, must be
# byte-identical to the build (also catches files hidden via git exclude and
# ensures the fix really lives in the checkout's show.py).
appm = os.path.join(MANIFEST_DIR, "app_src.sha256")
if not os.path.isfile(appm):
    failures.append(f"missing /app/src manifest: {appm}")
else:
    r = _walk_check("appsrc", appm)
    if r.returncode != 0:
        body = (r.stdout or "").strip()
        failures.append(
            "the /app/src tree differs from the pinned checkout (only "
            "src/pip/_internal/commands/show.py may change):\n"
            + (body or "(walker reported an error)")
            + "\n" + (r.stderr or "")[-800:]
        )

# 0c) the project's own regression test (baked into /opt/golden at build time)
# must not have been replaced.
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
                "/opt/golden/test_command_show.py was modified; it must be "
                "left as the fix-commit regression test"
            )


# --- 1) provenance: revision, single-file diff, no strays, no fix commit ---
head = run(["git", "-C", SRC, "rev-parse", "HEAD"])
if head.returncode != 0 or head.stdout.strip() != PARENT_SHA:
    failures.append(
        f"checkout HEAD is {head.stdout.strip()!r}, expected {PARENT_SHA}: "
        "the agent must fix the bug in place, not change the revision"
    )

status = run(["git", "-C", SRC, "status", "--porcelain", "--untracked-files=all"])
wanted = " M src/pip/_internal/commands/show.py"
if status.returncode != 0:
    failures.append("git status failed: " + (status.stderr or status.stdout))
elif status.stdout.splitlines() != [wanted]:
    failures.append(
        "working tree is not exactly one modified file (show.py):\n"
        + (status.stdout or "<clean tree>")
        + "\nuntracked or extra changes are not allowed"
    )

probe = run(["git", "-C", SRC, "cat-file", "-e", FIX_SHA])
if probe.returncode == 0:
    failures.append(
        "the upstream fix commit is reachable in the /app/src object store; "
        "the agent must derive the fix from the code, not replay the commit"
    )

# --- 2) the project's own regression test for this bug -----------------------
golden_env = dict(os.environ)
golden_env["PYTHONPATH"] = SRC + "/src"
golden = run(
    [
        PYTHON, "-m", "pytest", "-q", "-o", "addopts=",
        "-p", "no:cacheprovider", GOLDEN,
    ],
    cwd=SRC,
    env=golden_env,
)
if golden.returncode != 0:
    tail = (golden.stdout or "")[-5000:] + "\n" + (golden.stderr or "")[-1500:]
    failures.append("the project's regression test for this bug FAILED:\n" + tail)

# --- 3) the project's own existing unit slice stays green --------------------
unit_env = dict(os.environ)
unit_env["PYTHONPATH"] = SRC + "/src"
unit = run(
    [
        PYTHON, "-m", "pytest", "-q", "-p", "no:cacheprovider",
        "tests/unit/test_commands.py",
        "tests/unit/metadata/test_metadata.py",
    ],
    cwd=SRC,
    env=unit_env,
)
if unit.returncode != 0:
    tail = (unit.stdout or "")[-5000:] + "\n" + (unit.stderr or "")[-1500:]
    failures.append(
        "the project's existing unit slice failed after the agent's change:\n"
        + tail
    )

# --- 4) authored hidden cases (>= 2, each must pass) --------------------------
hidden_env = dict(os.environ)
hidden_env["PYTHONPATH"] = SRC + "/src"
os.makedirs("/tmp/verify", exist_ok=True)
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
        result = run(
            [
                PYTHON, "-m", "pytest", "-q", "-p", "no:cacheprovider",
                case_dir,
            ],
            cwd="/tmp/verify",
            env=hidden_env,
        )
        if result.returncode != 0:
            tail = (result.stdout or "")[-5000:] + "\n" + (result.stderr or "")[-1500:]
            failures.append(f"hidden case '{case}' FAILED:\n" + tail)

print("== bracket-ferry verifier ==")
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