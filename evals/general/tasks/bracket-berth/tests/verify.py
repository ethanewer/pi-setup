#!/usr/bin/env python3
"""bracket-berth verifier.

Gates, in order:

  1. Provenance of the /app/src checkout: HEAD is still the pinned parent
     revision, the upstream fix commit object is ABSENT from the clone's
     object store, and the working tree differs from upstream in exactly one
     file: httpx/_decoders.py (no other modifications, no untracked files).
     This is what makes the task an upstream task: the fix must live in the
     real checkout, and the agent must not have smuggled in or fetched the
     upstream fix.
  2. The golden regression test (tests/test_decoders.py at the upstream fix
     commit, extracted at image build time into /opt/golden/test_decoders.py)
     passes against the agent-repaired tree.  It includes the two upstream
     tests for this bug (empty zstd body -> b'', truncated zstd body ->
     DecodingError) plus every pre-existing decoder test.
  3. The project's own decoder suite in the tree (tests/test_decoders.py at
     the pinned revision) stays green -> the fix broke nothing else.
  4. Hidden cases: at least two authored cases exercising the same code path
     from inputs the upstream tests do not use (sync client round-trip,
     async client round-trip, zero-length streaming body), one pytest file
     per tests/hidden/<case>/ directory.
  5. The /app/fix-report.md deliverable exists, is substantive and localises
     the fix to the zstd decoding module in the clone.
  6. A fresh-interpreter probe re-checks the observable contract and that the
     ZStandardDecoder class is defined inside the /app/src clone (no
     site-packages monkeypatching).

Reward is binary; see test.sh. Every failure prints to stdout before the
verifier returns non-zero.
"""

import inspect
import os
import subprocess
import sys

SRC = "/app/src"
GOLDEN = "/opt/golden/test_decoders.py"
DELIVERABLE = "/app/fix-report.md"
PARENT_SHA = "189fc4bcbe5f314128775dec66a616ac9a31ad48"
FIX_SHA = "47f4a96ffaaaa07dca1614409549b5d7a6e7af49"
ONLY_ALLOWED_CHANGE = "httpx/_decoders.py"

failures: list[str] = []


def run(cmd, cwd=None):
    return subprocess.run(
        cmd, cwd=cwd, capture_output=True, text=True, timeout=300
    )


def check(ok: bool, message: str, detail: str = "") -> None:
    if not ok:
        if detail:
            message += "\n" + detail
        failures.append(message)


# ---------------------------------------------------------------------------
# 1) provenance
# ---------------------------------------------------------------------------
head = run(["git", "rev-parse", "HEAD"], cwd=SRC)
check(
    head.returncode == 0 and head.stdout.strip() == PARENT_SHA,
    f"FAIL [provenance] /app/src HEAD is not the pinned parent revision "
    f"(expected {PARENT_SHA})",
    head.stdout.strip() or head.stderr.strip(),
)

fix_present = run(["git", "cat-file", "-e", f"{FIX_SHA}^{{commit}}"], cwd=SRC)
check(
    fix_present.returncode != 0,
    "FAIL [provenance] the upstream fix commit is reachable in /app/src/.git — "
    "the task must not be solveable by reading the fix",
)

# The working tree must differ from the pinned revision in EXACTLY one file:
# httpx/_decoders.py. The baseline was recorded at image build time with the
# tree pristine and every bytecode cache deleted (see the Dockerfile), so any
# file the agent has since added - tracked, untracked, or hidden behind any
# gitignore/exclude rule - shows up as a new line here.
status = run(
    ["git", "status", "--porcelain", "--untracked-files=all", "--ignored"],
    cwd=SRC,
)
current = sorted(ln for ln in status.stdout.splitlines() if ln.strip())
baseline_path = "/opt/golden/git_status_baseline.txt"
if os.path.isfile(baseline_path):
    with open(baseline_path, encoding="utf-8") as fh:
        baseline = sorted(ln for ln in fh.read().splitlines() if ln.strip())
else:
    baseline = []
check(
    status.returncode == 0,
    "FAIL [provenance] git status failed in /app/src",
    (status.stdout or status.stderr)[-2000:],
)
missing = [ln for ln in baseline if ln not in current]
check(
    not missing,
    "FAIL [provenance] files present at build time disappeared from the "
    "checkout (destructive modification of the tree)",
    "\n".join(missing),
)
changed = [ln for ln in current if ln not in baseline]
check(
    len(changed) == 1
    and changed[0][:2] in (" M", "M ", "AM")
    and changed[0][3:] == ONLY_ALLOWED_CHANGE,
    "FAIL [provenance] the upstream working tree must differ from the pinned "
    "revision in exactly one file: httpx/_decoders.py (no added, ignored, or "
    "hidden files, no other modifications)",
    "\n".join(changed) if changed else "(working tree is pristine — nothing was fixed)",
)

# ---------------------------------------------------------------------------
# 2) golden regression test (upstream bytes extracted at build time)
# ---------------------------------------------------------------------------
golden = run(
    [sys.executable, "-m", "pytest", "-q", "-p", "no:cacheprovider", GOLDEN],
    cwd=SRC,
)
check(
    golden.returncode == 0,
    "FAIL [golden] the upstream regression test file from the fix commit does "
    "not pass against the repaired tree",
    (golden.stdout or golden.stderr or "")[-4000:],
)

# ---------------------------------------------------------------------------
# 3) the project's own decoder suite on the tree
# ---------------------------------------------------------------------------
upstream = run(
    [sys.executable, "-m", "pytest", "-q", "-p", "no:cacheprovider",
     "tests/test_decoders.py"],
    cwd=SRC,
)
check(
    upstream.returncode == 0,
    "FAIL [upstream] the project's own tests/test_decoders.py is no longer "
    "green",
    (upstream.stdout or upstream.stderr or "")[-4000:],
)

# ---------------------------------------------------------------------------
# 4) hidden cases (>= 2), one pytest module per tests/hidden/<case>/
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
                [sys.executable, "-m", "pytest", "-q", "-p", "no:cacheprovider",
                 test_file],
            )
            check(
                result.returncode == 0,
                f"FAIL [hidden] {os.path.basename(test_file)} did not pass",
                (result.stdout or result.stderr or "")[-4000:],
            )
    check(ran >= 2, "FAIL [hidden] fewer than two hidden test modules executed")

# ---------------------------------------------------------------------------
# 5) the deliverable report
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
    if "/app/src/httpx/_decoders.py" not in report:
        report_failures.append(
            "report does not name the fixed module by its full path"
        )
    if "zstd" not in report.lower() and "zstandard" not in report.lower():
        report_failures.append("report does not mention the zstd decoding machinery")
check(not report_failures, "FAIL [deliverable] /app/fix-report.md", "\n".join(report_failures))

# ---------------------------------------------------------------------------
# 6) fresh-interpreter probe of the observable contract + clone-local class
# ---------------------------------------------------------------------------
probe = run(
    [sys.executable, "-c", """
import asyncio
import inspect
import sys

import httpx

# The class the grading exercises must be defined inside the clone, and every
# method must be defined *in that same file*: a startup-hook wrapper that
# rebinds ZStandardDecoder.flush/decode to functions defined elsewhere (for
# example a sitecustomize.py dropped into /app/src) is caught here.
cls = httpx._decoders.ZStandardDecoder
src = inspect.getsourcefile(cls)
assert src is not None, "ZStandardDecoder has no source file"
assert src == "/app/src/httpx/_decoders.py", f"ZStandardDecoder defined outside the clone: {src}"
for method in ("__init__", "decode", "flush"):
    fn = getattr(cls, method, None)
    fsrc = inspect.getsourcefile(fn) if fn is not None else None
    assert fsrc == src, f"ZStandardDecoder.{method} redefined outside the decoder module: {fsrc}"

# The observable contract: the task's reproducer prints b'' and exits 0.
out = httpx.Response(200, headers=[(b"Content-Encoding", b"zstd")], content=b"").content
assert out == b"", out

# Non-empty zstd bodies still decode, truncated streams still raise.
import zstandard
body = b"payload"
compressed = zstandard.compress(body)
assert httpx.Response(200, headers=[(b"Content-Encoding", b"zstd")], content=compressed).content == body
try:
    httpx.Response(200, headers=[(b"Content-Encoding", b"zstd")], content=compressed[1:3]).content
except httpx.DecodingError:
    pass
else:
    raise AssertionError("truncated zstd stream did not raise DecodingError")

# A stream broken only in its TAIL (valid frame header, payload intact, the
# end-of-frame missing) is buffered silently by the zstd library and is
# detected solely at the decoder's flush() step. A "fix" that silences
# flush() (so the empty-body repro prints b'') would swallow this stream and
# return partial bytes, so it must raise here too.
tail_truncated = zstandard.compress(b"tail-truncated payload")[:-1]
try:
    httpx.Response(200, headers=[(b"Content-Encoding", b"zstd")], content=tail_truncated).content
except httpx.DecodingError:
    pass
else:
    raise AssertionError("tail-truncated zstd stream did not raise DecodingError")

# Zero-length zstd responses through a real client round-trip, sync and async.
def handler(request):
    return httpx.Response(200, headers={"Content-Encoding": "zstd"}, content=b"")

with httpx.Client(transport=httpx.MockTransport(handler)) as client:
    response = client.get("https://example.com/empty")
    assert response.read() == b""
    assert list(response.iter_bytes()) == []

async def ahandler(request):
    return httpx.Response(200, headers={"Content-Encoding": "zstd"}, content=b"")

async def main():
    async with httpx.AsyncClient(transport=httpx.MockTransport(ahandler)) as client:
        response = await client.get("https://example.com/empty")
        assert await response.aread() == b""
        assert [chunk async for chunk in response.aiter_bytes()] == []

asyncio.run(main())

print("probe ok")
"""],
)
check(probe.returncode == 0, "FAIL [probe] observable contract probe failed", (probe.stderr or probe.stdout)[-4000:])

# ---------------------------------------------------------------------------
print("== bracket-berth verifier ==")
if failures:
    for item in failures:
        print(item)
    print(f"FAILURES: {len(failures)}")
    sys.exit(1)
print("all checks passed")
sys.exit(0)