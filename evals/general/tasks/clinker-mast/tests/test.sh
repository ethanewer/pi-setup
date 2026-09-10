#!/bin/bash
# Verifier for clinker-mast (upstream-clone library-feature task).
#
# Requirements, in order:
#   1. HTTPX's own relevant test modules stay green on the (agent-modified)
#      checkout: tests/test_exported_members.py, tests/client/test_event_hooks.py,
#      tests/client/test_client.py.
#   2. Every hidden case directory under /tests/hidden runs its pytest files
#      (the feature's retry semantics, its interaction with the transport
#      stack, and the no-public-API-changed snapshot check).
#   3. The exported surface must expose httpx.RetryTransport and
#      httpx.AsyncRetryTransport through the installed package.
#   4. The /app/feature.md deliverable exists, is substantive, names the
#      classes and points at the changed checkout (/app/src).
#
# Reward is binary and written on every exit path (the trap covers crashes).
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier

python3 - <<'PY'
import json
import os
import subprocess
import sys

failures = []

# --- 1) the upstream modules the feature must not break -------------------
upstream = subprocess.run(
    [
        sys.executable, "-m", "pytest", "-q", "-p", "no:cacheprovider",
        "tests/test_exported_members.py",
        "tests/client/test_event_hooks.py",
        "tests/client/test_client.py",
    ],
    cwd="/app/src",
    capture_output=True,
    text=True,
)
if upstream.returncode != 0:
    tail = (upstream.stdout or "")[-5000:] + "\n" + (upstream.stderr or "")[-1500:]
    failures.append("upstream httpx test modules failed after the agent's change:\n" + tail)

# --- 2) hidden cases --------------------------------------------------------
hidden = "/tests/hidden"
if os.path.isdir(hidden):
    cases = sorted(os.listdir(hidden))
    if not cases:
        failures.append("no hidden cases present")
    for case in cases:
        case_dir = os.path.join(hidden, case)
        if not os.path.isdir(case_dir):
            continue
        test_files = sorted(
            os.path.join(case_dir, name)
            for name in os.listdir(case_dir)
            if name.startswith("test_") and name.endswith(".py")
        )
        if not test_files:
            failures.append(f"hidden case '{case}' has no pytest files")
            continue
        result = subprocess.run(
            [
                sys.executable, "-m", "pytest", "-q", "-p", "no:cacheprovider",
                *test_files,
            ],
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            tail = (result.stdout or "")[-5000:] + "\n" + (result.stderr or "")[-1500:]
            failures.append(f"hidden case '{case}' FAILED:\n" + tail)

# --- 3) exported surface of the installed package ---------------------------
# Tightened: the feature classes must be DEFINED inside the pinned checkout at
# /app/src, not injected at interpreter startup from site-packages. A lazy
# agent could drop a sitecustomize.py/.pth into site-packages that monkeypatches
# httpx and never touch the upstream tree; inspect.getsourcefile pins the
# definition to the clone, which is what makes this an upstream task.
export_probe = subprocess.run(
    [sys.executable, "-c", """
import inspect
import sys
import httpx

for name in ("RetryTransport", "AsyncRetryTransport"):
    cls = getattr(httpx, name, None)
    assert isinstance(cls, type), f"{name} is not a class"
    assert name in httpx.__all__, f"{name} missing from httpx.__all__"
    src = inspect.getsourcefile(cls)
    assert src is not None, f"{name} has no source file (dynamically constructed?)"
    assert src.startswith("/app/src/"), f"{name} defined outside the clone: {src}"
print("export surface + clone-local definition ok")
"""],
    capture_output=True,
    text=True,
)
if export_probe.returncode != 0:
    failures.append(
        "installed package does not expose the feature from the /app/src clone: "
        + (export_probe.stderr.strip() or export_probe.stdout.strip())
    )

# --- 4) deliverable /app/feature.md ------------------------------------------
feature = "/app/feature.md"
if not os.path.isfile(feature):
    failures.append("missing deliverable /app/feature.md")
else:
    try:
        with open(feature, encoding="utf-8") as fh:
            text = fh.read()
    except Exception as exc:  # noqa: BLE001
        failures.append("unreadable /app/feature.md: " + repr(exc))
        text = ""
    if "RetryTransport" not in text:
        failures.append("/app/feature.md does not describe httpx.RetryTransport")
    if "AsyncRetryTransport" not in text:
        failures.append("/app/feature.md does not describe httpx.AsyncRetryTransport")
    if "/app/src" not in text:
        failures.append("/app/feature.md does not point at the changed checkout (/app/src)")
    if len(text) < 400:
        failures.append("/app/feature.md is too short to be a real feature document")

print("== clinker-mast verifier ==")
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