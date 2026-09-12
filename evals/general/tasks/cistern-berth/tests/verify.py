#!/usr/bin/env python3
"""cistern-berth verifier.

Gates, in order:

  1. Provenance of the /app/src checkout: HEAD is still the pinned parent
     revision, the upstream fix commit object is ABSENT from the clone's
     object store, and the working tree differs from upstream in exactly one
     file -- aiohttp/web_request.py (no other modifications, no untracked
     files). This is what makes the task an upstream task: the fix must live
     in the real checkout, and the agent must not have smuggled in or
     fetched the upstream fix. A provenance failure aborts here so the nop
     run (pristine tree) scores 0 quickly instead of stalling on hangs.
  2. Site hygiene: no sitecustomize.py / usercustomize.py may exist anywhere
     an interpreter picks up by default. A root agent can otherwise make a
     no-op source edit pass provenance, then intercept every behavior check
     through a planted module-level wrapper while the real bug stays in the
     source. Only byte-level identity between /app/src and what runs is
     trusted; this gate removes the wrapper class of attacks.
  3. The golden regression test (test_single_forwarded_header_trailing_bad
     _value from tests/test_web_request.py at the upstream fix commit,
     extracted at image build time into /opt/golden/test_web_request.py)
     must be byte-identical to what the fix commit shipped (SHA-256 pinned
     below) and must pass against the agent-repaired tree. The hash pin
     blocks "rewrite the golden test instead of fixing the source".
  4. The project's own forwarded parsing suite on the tree
     (tests/test_web_request.py -k forwarded at the pinned revision) stays
     green -> the fix broke nothing else.
  5. Hidden cases: at least two authored cases exercising the same code path
     from inputs the upstream regression test does not use (trailing empty
     elements / no-space tails / quoted values containing ';' / runs of
     empty elements; multiple Forwarded header lines on one request), one
     pytest module per tests/hidden/<case>/. These files are mounted fresh
     at verifier time and cannot be edited by the agent.
  6. The /app/fix-report.md deliverable exists, is substantive and localises
     the fault to the Forwarded parsing step inside the clone.
  7. A fresh-interpreter probe of the observable contract run in an isolated
     interpreter: `python3 -S /tests/contract_probe.py` with
     PYTHONPATH=/app/src:<site-packages>. -S disables site initialisation,
     so any sitecustomize/usercustomize/.pth wrapper is inert and the only
     importable aiohttp is the real source tree at /app/src. The probe
     (whose bytes live under /tests and cannot be tampered with) asserts the
     task reproducer terminates and parses 'Forwarded: ; a' to an empty
     dict, the hidden-case inputs terminate with the expected results, and
     the aiohttp.web_request module it exercised is defined inside the
     /app/src clone. This is the load-bearing gate against wrappers: to
     pass it the actual bytes of aiohttp/web_request.py in the clone must
     parse these headers correctly.

Reward is binary; see test.sh. Every failure prints to stdout before the
verifier returns non-zero.
"""

import hashlib
import os
import subprocess
import sys

SRC = "/app/src"
GOLDEN = "/opt/golden/test_web_request.py"
DELIVERABLE = "/app/fix-report.md"
CONTRACT_PROBE = "/tests/contract_probe.py"
PARENT_SHA = "956f140095b21a88e11def934d42de85cc0b2b6b"
FIX_SHA = "b2b2bce03c17521dc454cdd4a6e19ab0a08bce6b"
ONLY_ALLOWED_CHANGE = "aiohttp/web_request.py"
# SHA-256 of tests/test_web_request.py at the fix commit, extracted by the
# Dockerfile at build time into /opt/golden/test_web_request.py.
GOLDEN_SHA256 = "fd594fdd9e56ff5cbb579d359498ba4d413c5ca642e82711c52a1fe360543fec"

failures: list[str] = []


def run(cmd, cwd=None, timeout=300, env=None):
    try:
        return subprocess.run(
            cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout, env=env
        )
    except subprocess.TimeoutExpired as exc:
        # Turn a wall-clock timeout (e.g. a mis-fix that still hangs) into a
        # first-class failure instead of a verifier crash.
        out = exc.stdout or b"" if isinstance(exc.stdout, bytes) else (exc.stdout or "")
        err = exc.stderr or b"" if isinstance(exc.stderr, bytes) else (exc.stderr or "")
        if isinstance(out, bytes):
            out = out.decode("utf-8", "replace")
        if isinstance(err, bytes):
            err = err.decode("utf-8", "replace")
        result = subprocess.CompletedProcess(cmd, 124, out, err)
        result.timed_out = True  # type: ignore[attr-defined]
        return result


def check(ok: bool, message: str, detail: str = "") -> None:
    if not ok:
        if detail:
            message += "\n" + detail
        failures.append(message)


PYTEST = [
    sys.executable, "-m", "pytest", "-q", "-p", "no:cacheprovider",
    "--rootdir=/app/src",
]

# ---------------------------------------------------------------------------
# 1) provenance (aborts on failure so the buggy/nop cases never stall)
# ---------------------------------------------------------------------------
head = run(["git", "rev-parse", "HEAD"], cwd=SRC)
if head.returncode != 0 or head.stdout.strip() != PARENT_SHA:
    print(
        f"FAIL [provenance] /app/src HEAD is not the pinned parent revision "
        f"(expected {PARENT_SHA}): {head.stdout.strip() or head.stderr.strip()!r}"
    )
    sys.exit(1)

fix_present = run(["git", "cat-file", "-e", f"{FIX_SHA}^{{commit}}"], cwd=SRC)
if fix_present.returncode == 0:
    print(
        "FAIL [provenance] the upstream fix commit is reachable in "
        "/app/src/.git -- the task must not be solveable by reading the fix"
    )
    sys.exit(1)

status = run(["git", "status", "--porcelain", "--untracked-files=all"], cwd=SRC)
lines = [ln for ln in status.stdout.splitlines() if ln.strip()]
is_expected_change = (
    len(lines) == 1
    and lines[0][:2] in (" M", "M ", "MM")
    and lines[0][3:] == ONLY_ALLOWED_CHANGE
)
if not is_expected_change:
    print(
        "FAIL [provenance] the upstream working tree must differ from the "
        f"pinned revision in exactly one file: {ONLY_ALLOWED_CHANGE}"
    )
    print("\n".join(lines) if lines else "(working tree is pristine -- nothing was fixed)")
    sys.exit(1)

# ---------------------------------------------------------------------------
# 2) site hygiene: a wrapper planted in site-packages / user site must not
#    be importable by default. A correct tree never has these files.
# ---------------------------------------------------------------------------
WRAPPERS = ("sitecustomize", "usercustomize")
suspects: list[str] = []
for mod in WRAPPERS:
    # -S prevents automatic loading; instead ask a NORMAL interpreter
    # whether site machinery would find a module of that name anywhere.
    r = run(
        [sys.executable, "-c",
         f"import importlib.util; s = importlib.util.find_spec('{mod}');"
         f"print(s.origin if s else '')"],
        cwd=SRC, timeout=30,
    )
    origin = (r.stdout or "").strip()
    if r.returncode != 0:
        # A module that crashes on import is still a planted wrapper; fail
        # closed rather than letting the check subprocess die silently.
        suspects.append(f"{mod}: probe interpreter failed (rc={r.returncode}"
                        f", stderr={r.stderr.strip()[:100]!r})")
    elif origin:
        suspects.append(f"{mod} at {origin}")
if suspects:
    print("FAIL [site] a Python site-module wrapper is present and would be loaded by "
          "default; the task must not be solved by intercepting imports:\n    "
          + "\n    ".join(suspects))
    sys.exit(1)
# Note: .pth-based wrappers are deliberately NOT scanned for -- the image
# ships legitimate executable .pth files (the pip editable-install finder, the
# coverage process hook), and flagging them would false-fail honest trees.
# Instead, gate 7 runs the contract probe with `python3 -S`, where site
# initialisation is off, no .pth is ever processed, and imports resolve only
# via PYTHONPATH=/app/src first: a .pth wrapper is inert there by construction.

# ---------------------------------------------------------------------------
# 3) golden regression test (upstream bytes extracted at build time)
# ---------------------------------------------------------------------------
try:
    with open(GOLDEN, "rb") as fh:
        golden_bytes = fh.read()
    golden_digest = hashlib.sha256(golden_bytes).hexdigest()
except OSError as exc:
    golden_digest = ""
    check(False, f"FAIL [golden] cannot read {GOLDEN}: {exc!r}")
check(
    golden_digest == GOLDEN_SHA256,
    "FAIL [golden] /opt/golden/test_web_request.py is not byte-identical to "
    f"the file the upstream fix commit shipped (expected sha256 {GOLDEN_SHA256}, "
    f"got {golden_digest or '<unreadable>'}); rewriting the golden test does "
    "not fix the bug",
)
if golden_digest == GOLDEN_SHA256:
    golden = run(
        PYTEST + ["-p", "timeout", "--timeout=15",
                  f"{GOLDEN}::test_single_forwarded_header_trailing_bad_value"],
        cwd=SRC,
    )
    check(
        golden.returncode == 0,
        "FAIL [golden] the upstream regression test from the fix commit does "
        "not pass against the repaired tree",
        (golden.stdout or golden.stderr or "")[-4000:],
    )

# ---------------------------------------------------------------------------
# 4) the project's own forwarded suite on the tree
# ---------------------------------------------------------------------------
upstream = run(
    PYTEST + ["-p", "timeout", "--timeout=120",
              "tests/test_web_request.py", "-k", "forwarded"],
    cwd=SRC,
)
check(
    upstream.returncode == 0,
    "FAIL [upstream] the project's own tests/test_web_request.py forwarded "
    "tests are no longer green",
    (upstream.stdout or upstream.stderr or "")[-4000:],
)

# ---------------------------------------------------------------------------
# 5) hidden cases (>= 2), one pytest module per tests/hidden/<case>/
# ---------------------------------------------------------------------------
hidden_root = "/tests/hidden"
if not os.path.isdir(hidden_root):
    failures.append("FAIL [hidden] no hidden case directory at /tests/hidden")
else:
    cases = sorted(
        name for name in os.listdir(hidden_root)
        if os.path.isdir(os.path.join(hidden_root, name))
    )
    check(len(cases) >= 2, "FAIL [hidden] need at least two hidden cases", repr(cases))
    ran = 0
    for case in cases:
        case_dir = os.path.join(hidden_root, case)
        test_files = sorted(
            os.path.join(case_dir, name)
            for name in os.listdir(case_dir)
            if name.startswith("test_") and name.endswith(".py")
        )
        check(bool(test_files), f"FAIL [hidden] case {case!r} has no test_*.py file")
        for test_file in test_files:
            ran += 1
            result = run(
                PYTEST + ["-p", "timeout", "--timeout=15", test_file],
                cwd=SRC,
            )
            check(
                result.returncode == 0,
                f"FAIL [hidden] {os.path.basename(test_file)} did not pass",
                (result.stdout or result.stderr or "")[-4000:],
            )
    check(ran >= 2, "FAIL [hidden] fewer than two hidden test modules executed")

# ---------------------------------------------------------------------------
# 6) the deliverable report
# ---------------------------------------------------------------------------
report_failures: list[str] = []
if not os.path.isfile(DELIVERABLE):
    report_failures.append(f"missing deliverable {DELIVERABLE}")
else:
    try:
        report = open(DELIVERABLE, encoding="utf-8").read()
    except OSError as exc:
        report_failures.append(f"unreadable deliverable: {exc!r}")
        report = ""
    if len(report) < 200:
        report_failures.append("report is too short to be a real fix report")
    if "/app/src/aiohttp/web_request.py" not in report:
        report_failures.append("report does not name the fixed module by its full path")
    if "forwarded" not in report.lower():
        report_failures.append("report does not mention the Forwarded parsing")
check(not report_failures, "FAIL [deliverable] /app/fix-report.md", "\n".join(report_failures))

# ---------------------------------------------------------------------------
# 7) isolated fresh-interpreter probe of the observable contract. Runs under
#    `python3 -S` with PYTHONPATH=/app/src:<site-packages>: site initialisation
#    is off, so planted sitecustomize/usercustomize/.pth wrappers never load,
#    and the only place `import aiohttp` can resolve is the real /app/src
#    clone. This gate reads the actual bytes of the clone, so behaviour
#    cannot be faked from outside the tree. A mis-fix that still hangs is
#    killed by the subprocess timeout.
# ---------------------------------------------------------------------------
site_packages = os.path.join(os.path.dirname(os.__file__), "site-packages")
probe_env = dict(os.environ)
probe_env["PYTHONPATH"] = os.pathsep.join([SRC, site_packages])
probe = run(
    [sys.executable, "-S", CONTRACT_PROBE],
    cwd=SRC,
    timeout=60,
    env=probe_env,
)
probe_detail = (probe.stdout or probe.stderr or "")[-4000:]
if getattr(probe, "timed_out", False):
    probe_detail = "probe process was killed after 60s because it hung -- a repaired " \
        "tree must terminate on every tested header under the isolated interpreter"
check(
    probe.returncode == 0,
    "FAIL [probe] the observable contract does not hold for the actual source "
    "tree imported in an isolated interpreter (task reproducer and hidden-case "
    "headers must parse and never hang; a site-module wrapper cannot make this "
    "pass -- the clone's own bytes are what run)",
    probe_detail,
)

# ---------------------------------------------------------------------------
print("== cistern-berth verifier ==")
if failures:
    for item in failures:
        print(item)
    print(f"FAILURES: {len(failures)}")
    sys.exit(1)
print("all checks passed")
sys.exit(0)