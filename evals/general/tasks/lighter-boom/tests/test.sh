#!/bin/bash
# Verifier for lighter-boom (upstream-clone debugging task on nltk/nltk).
#
# Requirements, in order:
#   0. Integrity of the environment outside the deliverable: /usr/local
#      (interpreter + site-packages), /app/src (allowing only the tokenizer
#      source file to differ) and /opt/golden are pinned to build-time
#      manifests stored under /tests/manifests; harbor re-uploads /tests from
#      the host at verify time, so the agent cannot forge them.
#   1. Provenance of /app/src: HEAD is still the pinned parent commit, the
#      only work-tree change is to nltk/tokenize/destructive.py, there are no
#      untracked files, and the upstream fix commit is NOT reachable in the
#      clone's object store.
#   2. The agent's own reproduction deliverable /app/reproduce.py must FAIL
#      when run against the pristine, unfixed tree (a real non-editable
#      install of the parent commit in /opt/venv) and must PASS when run
#      against (a) an overlay of that same tree whose only difference is the
#      agent's tokenizer source, and (b) the repaired /app/src itself.
#   3. The project's own regression test for this bug (extracted from the
#      fix commit at build time into /opt/golden) passes against the repaired
#      tree.
#   4. The project's own existing tokenizer suite stays green
#      (nltk/test/unit/test_tokenize.py, the full file).
#   5. Every hidden case under /tests/hidden passes; at least two of them.
#
# Reward is binary and written on every exit path (the trap covers crashes).
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier

python3 - <<'PY'
import os
import shutil
import subprocess
import sys

SRC = "/app/src"
PARENT_SHA = "c86229d218978628eb4e6e100ff266d2a939b7f0"
FIX_SHA = "1929bf9e365faa9e476b3abbccb72a74351d647e"
ALLOW = "nltk/tokenize/destructive.py"
GOLDEN = "/opt/golden/test_tokenize.py"
GOLDEN_NODE = "TestTokenize::test_word_tokenize_opening_single_quote_padding"
SUITE = "nltk/test/unit/test_tokenize.py"
REPRO = "/app/reproduce.py"
VENV_PY = "/opt/venv/bin/python"
HIDDEN = "/tests/hidden"
PYTHON = sys.executable


def run(cmd, cwd=None, env=None):
    return subprocess.run(cmd, cwd=cwd, env=env, capture_output=True, text=True)


failures = []

# --- 0) tamper / wrapper integrity (host-controlled manifests) -------------
MANIFEST_DIR = "/tests/manifests"
WALKER = "/tests/verify_walk.py"


def walk_check(kind, manifest):
    return subprocess.run(
        [PYTHON, WALKER, "check", kind, manifest], capture_output=True, text=True
    )


# 0a) interpreter + site-packages must be byte-identical to the build. This
# closes pip-install upgrades, planted sitecustomize/.pth hooks, a replaced
# python3, or a sourceless .pyc planted to fake a result.
usrm = os.path.join(MANIFEST_DIR, "usr_local.sha256")
if not os.path.isfile(usrm):
    failures.append(f"missing /usr/local manifest: {usrm}")
else:
    r = walk_check("usrlocal", usrm)
    if r.returncode != 0:
        failures.append(
            "interpreter or site-packages modified outside the fix:\n"
            + ((r.stdout or "").strip() or "(walker reported an error)")
            + "\n" + (r.stderr or "")[-800:]
        )

# 0b) the /app/src deliverable tree, except the one allowed fix file, must be
# byte-identical to the build (also catches files hidden via git exclude and
# ensures the real fix lives in the checkout's tokenizer source).
appm = os.path.join(MANIFEST_DIR, "app_src.sha256")
if not os.path.isfile(appm):
    failures.append(f"missing /app/src manifest: {appm}")
else:
    r = walk_check("appsrc", appm)
    if r.returncode != 0:
        failures.append(
            "the /app/src tree differs from the pinned checkout (only "
            "nltk/tokenize/destructive.py may change):\n"
            + ((r.stdout or "").strip() or "(walker reported an error)")
            + "\n" + (r.stderr or "")[-800:]
        )

# 0c) the project's own regression test (baked into /opt/golden at build
# time) must not have been replaced or edited.
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
                "/opt/golden/test_tokenize.py was modified; it must be left as "
                "the fix-commit regression test"
            )

# --- 1) provenance: revision, single-file diff, no strays, no fix commit ---
head = run(["git", "-C", SRC, "rev-parse", "HEAD"])
if head.returncode != 0 or head.stdout.strip() != PARENT_SHA:
    failures.append(
        f"checkout HEAD is {head.stdout.strip()!r}, expected {PARENT_SHA}: "
        "the agent must fix the bug in place, not change the revision"
    )

status = run(["git", "-C", SRC, "status", "--porcelain", "--untracked-files=all"])
wanted = " M nltk/tokenize/destructive.py"
if status.returncode != 0:
    failures.append("git status failed: " + (status.stderr or status.stdout))
elif status.stdout.splitlines() != [wanted]:
    failures.append(
        "working tree is not exactly one modified file (destructive.py):\n"
        + (status.stdout or "<clean tree>")
        + "\nuntracked or extra changes are not allowed"
    )

probe = run(["git", "-C", SRC, "cat-file", "-e", FIX_SHA])
if probe.returncode == 0:
    failures.append(
        "the upstream fix commit is reachable in the /app/src object store; "
        "the agent must derive the fix from the code, not replay the commit"
    )

# --- 2) the agent's own reproduction deliverable ---------------------------
if not os.path.isfile(REPRO):
    failures.append(f"missing deliverable {REPRO}")
else:
    # 2a) against the pristine, unfixed tree (real install of the parent
    # commit in a dedicated venv): MUST fail. The editable install's PEP 660
    # finder maps "nltk" to /app/src unconditionally, so the pre-fix run uses
    # a venv whose sys.path contains only its own site-packages copy.
    base = dict(os.environ)
    base.pop("PYTHONPATH", None)  # pre-fix run must not see any stray path
    pretree = run([VENV_PY, REPRO], cwd="/tmp", env=base)
    if pretree.returncode == 0:
        failures.append(
            "your reproduction did NOT fail against the original, unfixed "
            "code; a reproduction must demonstrate the bug (an assertion "
            "that describes the correct behavior fails on the buggy tree)"
        )

    # 2b) against an overlay of the pristine tree whose ONLY difference is
    # the agent's tokenizer source: MUST pass. This proves the fix really
    # lives in nltk/tokenize/destructive.py inside the checkout.
    overlay = "/tmp/overlay"
    if os.path.isdir(overlay):
        shutil.rmtree(overlay)
    venv_pkg = "/opt/venv/lib/python3.12/site-packages/nltk"
    if not os.path.isdir(venv_pkg):
        failures.append(f"pre-fix reference install missing: {venv_pkg}")
    else:
        shutil.copytree(venv_pkg, os.path.join(overlay, "nltk"))
        shutil.copy2(
            os.path.join(SRC, ALLOW),
            os.path.join(overlay, ALLOW),
        )
        for d in ("__pycache__",):
            cache = os.path.join(overlay, "nltk", d)
            if os.path.isdir(cache):
                shutil.rmtree(cache)
        env_overlay = dict(base)
        env_overlay["PYTHONPATH"] = overlay
        overlay_run = run([VENV_PY, REPRO], cwd="/tmp", env=env_overlay)
        if overlay_run.returncode != 0:
            tail = (overlay_run.stdout or "")[-4000:] + "\n" + (overlay_run.stderr or "")[-1200:]
            failures.append(
                "your reproduction FAILED against the repaired checkout"
                " (pristine tree + your tokenizer source):\n" + tail
            )

    # 2c) against the repaired /app/src tree through the checkout's own
    # editable install: MUST pass.
    env_src = dict(base)
    env_src["PYTHONPATH"] = SRC
    src_run = run([PYTHON, REPRO], cwd="/tmp", env=env_src)
    if src_run.returncode != 0:
        tail = (src_run.stdout or "")[-4000:] + "\n" + (src_run.stderr or "")[-1200:]
        failures.append(
            "your reproduction FAILED against the repaired /app/src:\n" + tail
        )

# --- 3) the project's own regression test for this bug -----------------------
golden_env = dict(os.environ)
golden_env["PYTHONPATH"] = SRC
golden = run(
    [PYTHON, "-m", "pytest", "-q", "-o", "addopts=", "-p", "no:cacheprovider",
     f"{GOLDEN}::{GOLDEN_NODE}"],
    cwd=SRC,
    env=golden_env,
)
if golden.returncode != 0:
    tail = (golden.stdout or "")[-5000:] + "\n" + (golden.stderr or "")[-1500:]
    failures.append("the project's regression test for this bug FAILED:\n" + tail)

# --- 4) the project's own existing tokenizer suite stays green ---------------
unit_env = dict(os.environ)
unit_env["PYTHONPATH"] = SRC
unit = run(
    [PYTHON, "-m", "pytest", "-q", "-p", "no:cacheprovider", SUITE],
    cwd=SRC,
    env=unit_env,
)
if unit.returncode != 0:
    tail = (unit.stdout or "")[-5000:] + "\n" + (unit.stderr or "")[-1500:]
    failures.append(
        "the project's existing tokenizer suite failed after the agent's "
        "change:\n" + tail
    )

# --- 5) authored hidden cases (>= 2, each must pass) --------------------------
hidden_env = dict(os.environ)
hidden_env["PYTHONPATH"] = SRC
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
            [PYTHON, "-m", "pytest", "-q", "-p", "no:cacheprovider", case_dir],
            cwd="/tmp/verify",
            env=hidden_env,
        )
        if result.returncode != 0:
            tail = (result.stdout or "")[-5000:] + "\n" + (result.stderr or "")[-1500:]
            failures.append(f"hidden case '{case}' FAILED:\n" + tail)

print("== lighter-boom verifier ==")
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