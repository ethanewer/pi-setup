#!/bin/bash
# Verifier for forecastle-current (upstream-clone debugging task on httpx).
#
# Checks, in order:
#   1. Deliverable /app/reproduce.py exists and matches the output contract
#      in both directions (see 3/4).
#   2. Integrity manifest: the shipped tests/ tree (golden regression test,
#      conftest fixtures) and site-packages are byte-identical to build time.
#   3. The agent's reproduction is run against the pristine PRE-FIX library
#      (root-owned venv reference install) and must FAIL there (BUG, nonzero);
#   4. ... and against the repaired tree (/app/src editable install) it must
#      PASS there (OK, exit 0).
#   5. The project's own regression test for the bug plus the selected
#      timeout tests pass on the repaired tree.
#   6. The client suites pass on the repaired tree (nothing else broke).
#   7. Hidden cases under /tests/hidden exercise the same code path with
#      inputs the upstream test does not use (sync + async, request-level
#      timeout overrides, repeated sends).
#   8. The library used by the acceptance is defined inside /app/src.
#
# Reward is binary and written on every exit path (the trap covers crashes).
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier

python3 - <<'PY'
import hashlib
import json
import os
import subprocess
import sys

failures = []


def run(cmd, cwd=None, env=None, timeout=300):
    return subprocess.run(
        cmd, cwd=cwd, capture_output=True, text=True, env=env, timeout=timeout
    )


PYEXEC = 'path = {path!r}\nsrc = open(path, encoding="utf-8").read()\n' \
         'sys.path[:] = [p for p in sys.path if p not in ("", "/app")]\n' \
         'exec(compile(src, path, "exec"), {{"__name__": "__main__", "__file__": path}})\n'


def run_repro(interp):
    """Run /app/reproduce.py with a scrubbed sys.path so no shim under /app
    can shadow the interpreter's own httpx install."""
    wrapper = "import sys\n" + PYEXEC.format(path="/app/reproduce.py")
    return run([interp, "-c", wrapper], cwd="/tmp", timeout=60)


# --- 1) deliverable --------------------------------------------------------
if not os.path.isfile("/app/reproduce.py"):
    failures.append("missing deliverable /app/reproduce.py (the agent must author it)")
else:
    with open("/app/reproduce.py", encoding="utf-8") as fh:
        repro_src = fh.read()
    if len(repro_src) < 300:
        failures.append("/app/reproduce.py is too short to be a real reproduction")

# --- 2) integrity manifest ------------------------------------------------
def walk(root, exclude_dirs=("__pycache__",), exclude_rel=()):
    out = {}
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in exclude_dirs]
        for fn in sorted(filenames):
            p = os.path.join(dirpath, fn)
            if p.endswith(".pyc"):
                continue
            rel = os.path.relpath(p, root)
            if rel in exclude_rel:
                continue
            out[rel] = hashlib.sha256(
                open(p, "rb").read()
            ).hexdigest()
    return out


# Keys and roots must match the build-time manifest generator exactly. The
# src_tree entry pins every file under /app/src except httpx/_client.py (the
# one file the agent is meant to change): an added /app/src/conftest.py that
# skips or rewrites the shipped tests, or a sitecustomize.py/pytest.ini
# shim, shows up as drift here and fails the task.
TREE_SPECS = (
    ("tests_tree", "/app/src/tests", ("__pycache__",), ()),
    ("site_packages", "/usr/local/lib/python3.12/site-packages", ("__pycache__",), ()),
    ("src_tree", "/app/src", ("__pycache__", ".git", ".pytest_cache"), {"httpx/_client.py"}),
)

try:
    manifest = json.load(open("/opt/forecastle-manifest.json", encoding="utf-8"))
except Exception as exc:  # noqa: BLE001
    failures.append("cannot read /opt/forecastle-manifest.json: %r" % (exc,))
    manifest = {}

if manifest:
    for key, root, extra_dirs, extra_rel in TREE_SPECS:
        if not os.path.isdir(root):
            failures.append("missing tree %s" % root)
            continue
        current = walk(root, exclude_dirs=("__pycache__",) + extra_dirs,
                       exclude_rel=extra_rel)
        if current != manifest.get(key):
            changed = [p for p in sorted(set(current) | set(manifest.get(key, {})))
                       if current.get(p) != manifest.get(key, {}).get(p)]
            failures.append(
                "integrity drift under %s (%d file(s) changed/added/removed, "
                "first: %s): the shipped tests/ tree and installed packages "
                "must stay byte-identical" % (root, len(changed), changed[:3])
            )

# --- 3) reproduction vs the PRE-FIX reference library ----------------------
ref = run_repro("/opt/parent-venv/bin/python")
ref_out = (ref.stdout or "") + (ref.stderr or "")
if ref.returncode == 0:
    failures.append(
        "reproduction did NOT fail against the pristine pre-fix library "
        "(exit 0). An honest reproduction of the bug must show the timeout "
        "being ignored there."
    )
else:
    if "BUG" not in ref_out:
        failures.append(
            "reproduction failed against the pre-fix library but without the "
            "required 'BUG' marker line"
        )
    if "OK" in ref_out:
        failures.append(
            "reproduction printed the 'OK' marker while running against the "
            "pre-fix library"
        )

# --- 4) reproduction vs the repaired tree ----------------------------------
rep = run_repro(sys.executable)
rep_out = (rep.stdout or "") + (rep.stderr or "")
if rep.returncode != 0:
    failures.append(
        "reproduction failed against the agent's tree (exit %s): expected "
        "exit 0 with the timeout honoured after the fix\n--- output ---\n%s"
        % (rep.returncode, rep_out[-2000:])
    )
else:
    if "OK" not in rep_out:
        failures.append("reproduction exited 0 but without the required 'OK' marker line")

# --- 5) golden regression test + selected timeout tests --------------------
golden = run(
    [sys.executable, "-m", "pytest", "tests/test_timeouts.py", "-v",
     "-p", "no:cacheprovider", "-m", "not network",
     "-k", "read_timeout or pool_timeout or new_request_send_timeout", "-o", "addopts="],
    cwd="/app/src",
)
golden_out = (golden.stdout or "") + (golden.stderr or "")
if golden.returncode != 0:
    failures.append("timeout suite FAILED on the repaired tree:\n" + golden_out[-2500:])
else:
    if "test_async_client_new_request_send_timeout" not in golden_out:
        failures.append(
            "the project's regression test test_async_client_new_request_send_timeout "
            "did not run (or its name does not appear in the verbose report)"
        )

# --- 6) client suites ------------------------------------------------------
suite = run(
    [sys.executable, "-m", "pytest", "tests/client/test_client.py",
     "tests/client/test_async_client.py", "-q", "-p", "no:cacheprovider",
     "-m", "not network", "-o", "addopts="],
    cwd="/app/src",
)
if suite.returncode != 0:
    tail = (suite.stdout or "")[-4000:] + "\n" + (suite.stderr or "")[-1500:]
    failures.append("client suites FAILED on the repaired tree:\n" + tail)

# --- 7) hidden cases -------------------------------------------------------
hidden_root = "/tests/hidden"
if os.path.isdir(hidden_root):
    cases = sorted(os.listdir(hidden_root))
    if not cases:
        failures.append("no hidden cases present")
    for case in cases:
        case_dir = os.path.join(hidden_root, case)
        if not os.path.isdir(case_dir):
            continue
        test_files = sorted(
            os.path.join(case_dir, name)
            for name in os.listdir(case_dir)
            if name.startswith("test_") and name.endswith(".py")
        )
        if not test_files:
            failures.append("hidden case '%s' has no pytest files" % case)
            continue
        result = run(
            [sys.executable, "-m", "pytest", "-q", "-p", "no:cacheprovider", "-o", "addopts=",
             *test_files],
            cwd="/app/src",
            timeout=300,
        )
        if result.returncode != 0:
            tail = (result.stdout or "")[-4000:] + "\n" + (result.stderr or "")[-1500:]
            failures.append("hidden case '%s' FAILED:\n%s" % (case, tail))
else:
    failures.append("missing /tests/hidden directory")

# --- 8) library really comes from the /app/src clone -----------------------
probe = subprocess.run(
    [sys.executable, "-c", """
import inspect
import httpx
for name in ("Client", "AsyncClient"):
    src = inspect.getsourcefile(getattr(httpx, name).send)
    assert src is not None and src.startswith("/app/src/"), \\
        "%s.send defined outside the clone: %s" % (name, src)
print("httpx", httpx.__version__, "loaded from /app/src")
"""],
    capture_output=True, text=True,
)
if probe.returncode != 0:
    failures.append("library source check failed: " + (probe.stderr.strip() or probe.stdout.strip()))

# --- verdict ---------------------------------------------------------------
print("== forecastle-current verifier ==")
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