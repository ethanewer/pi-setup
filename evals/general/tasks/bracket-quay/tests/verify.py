"""Verifier for bracket-quay.

Checks the repaired deliverable in five groups:

1. shape: /app/quayside is a git repository with >= 28 commits, 27..42
   package modules and 6000..9500 package LOC;
2. postmortem: /app/postmortem.md exists and its "Introduced by commit
   <40-hex>" line names the commit that ACTUALLY introduced the regression
   (found with git pickaxe on the buggy marker) — and that introducing
   commit's diff really contains the marker;
3. fix: the buggy marker no longer occurs anywhere in the working tree;
4. suite: the shipped pytest suite (>= 60 tests, executed) plus the hidden
   tests mounted at /tests/hidden (copied to a scratch dir outside the
   agent's tree and run with the repo's pytest config disabled) all pass;
5. e2e: the CLI still builds the shipped example site \u2014 which contains the
   symbol-heavy headings from the report \u2014 and `check` reports no issues.

Exits 0 only if everything passes; prints a readable failure list first.
Write exactly '1'/'0' happens in tests/test.sh from the exit status.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

REPO = Path("/app/quayside")
MARKER = 'text = text.replace("&", "and")'
INTRO_RE = re.compile(r"^Introduced by commit ([0-9a-f]{40})$")

failures = []


def fail(msg):
    failures.append(msg)


def run(*args, cwd=str(REPO), env=None):
    return subprocess.run(args, capture_output=True, text=True, cwd=cwd,
                          env=env)


def git(*args, cwd=str(REPO)):
    return run("git", "-C", cwd, *args)


def count_lines(path):
    return sum(len(p.read_text(errors="replace").splitlines())
               for p in sorted(Path(path).rglob("*.py"))
               if "__pycache__" not in str(p))


def main() -> int:
    # ---- 1) shape --------------------------------------------------------
    if not (REPO / ".git").is_dir():
        fail("deliverable /app/quayside is not a git repository")
        return _finish(1)
    modules = [p for p in (REPO / "quaydoc").glob("*.py")]
    pkg_loc = count_lines(REPO / "quaydoc")
    if not (27 <= len(modules) <= 42):
        fail(f"package module count {len(modules)} outside 27..42")
    if not (6000 <= pkg_loc <= 9500):
        fail(f"package LOC {pkg_loc} outside 6000..9500")

    revs = git("rev-list", "--count", "HEAD")
    if revs.returncode == 0:
        commits = int(revs.stdout.strip() or "0")
        if commits < 28:
            fail(f"git history has {commits} commits (< 28)")
    else:
        fail("cannot read commit history")

    # ---- 2) postmortem + introducing commit -----------------------------
    pm = Path("/app/postmortem.md")
    if not pm.is_file():
        fail("deliverable /app/postmortem.md missing")
        return _finish(1)
    pm_text = pm.read_text(encoding="utf-8")
    match = None
    for line in pm_text.splitlines():
        m = INTRO_RE.match(line.strip())
        if m:
            match = m
            break
    if match is None:
        fail("postmortem has no 'Introduced by commit <40-hex>' line")
        return _finish(1)
    named = match.group(1)

    log = git("log", "--reverse", "-S", MARKER, "--format=%H",
              "--", "quaydoc/toc.py")
    hits = [line for line in log.stdout.splitlines() if line.strip()]
    if not hits:
        fail("pickaxe found no commit introducing the marker")
    else:
        # Earliest pickaxe hit is the commit that first changed the marker
        # count (0 -> 1).  If the agent later committed their own fix the
        # removal shows up as a second hit; hits[0] is still the introducer.
        introduced = hits[0]
        if named != introduced:
            fail(f"postmortem names {named[:12]} but the introducing "
                 f"commit is {introduced[:12]}")
        else:
            show = git("show", "--stat", named, "--format=%H",
                       "--", "quaydoc/toc.py")
            if named not in show.stdout:
                fail("named commit does not touch quaydoc/toc.py")
            diff = git("show", named, "--", "quaydoc/toc.py")
            if MARKER not in diff.stdout:
                fail("named commit's diff on toc.py lacks the marker "
                     "(wrong commit?)")
    verify = git("cat-file", "-e", named)
    if verify.returncode != 0:
        fail(f"postmortem names {named[:12]} which is not in history")

    # ---- 3) fix actually applied ----------------------------------------
    # The regressed marker must be gone from the entire delivered tree (the
    # verifier re-derives the introducing commit from git history, so the
    # marker has no reason to remain anywhere in the files).  Git objects are
    # exempt: history must keep the marker so the pickaxe still finds it.
    matched = []
    for root, _dirs, files in os.walk(str(REPO)):
        if "/.git/" in root + "/":
            continue
        for name in files:
            if name.endswith((".pyc", ".pyo")):
                continue
            path = os.path.join(root, name)
            try:
                with open(path, "rb") as fh:
                    data = fh.read()
            except OSError:
                continue
            if MARKER.encode("utf-8") in data:
                matched.append(os.path.relpath(path, str(REPO)))
    if matched:
        fail(f"marker still present in the working tree: {matched}")

    # ---- 4) suite + hidden tests ----------------------------------------
    n = _shipped_test_count()
    if n is not None and n < 60:
        fail(f"shipped test count {n} below 60")

    hidden_src = Path("/tests/hidden")
    if not hidden_src.is_dir() or not any(hidden_src.iterdir()):
        fail("/tests/hidden is missing at verify time")
    else:
        # Hidden tests are copied OUTSIDE the agent's tree and run with the
        # repository's pytest configuration disabled (-c /dev/null) and
        # quaydoc imported via PYTHONPATH, so the deliverable cannot dodge
        # them by editing pyproject.toml or planting a conftest.py inside
        # /app/quayside.  The shipped suite is run the same way; the report
        # contract forbids weakening tests, and the executed-passed count is
        # checked so a planted conftest that skips everything still fails.
        import tempfile
        hidden_dir = Path(tempfile.mkdtemp(prefix="quay-hid-", dir="/tmp"))
        try:
            added = 0
            for case in sorted(hidden_src.iterdir()):
                if not case.is_dir():
                    continue
                for test_file in sorted(case.glob("test_*.py")):
                    shutil.copyfile(test_file, hidden_dir / test_file.name)
                    added += 1
            if added < 2:
                fail(f"only {added} hidden test file(s) copied")
            else:
                env = dict(os.environ)
                env["PYTHONPATH"] = str(REPO)
                shipped = run(sys.executable, "-m", "pytest", "-q",
                              "-c", "/dev/null", "tests", cwd=str(REPO),
                              env=env)
                hidden = run(sys.executable, "-m", "pytest", "-q",
                             "-c", "/dev/null", str(hidden_dir),
                             cwd=str(REPO), env=env)
                if shipped.returncode != 0:
                    tail = (shipped.stdout or "")[-1500:]
                    fail("shipped pytest suite is not green:\n" + tail)
                elif _passed_count(shipped.stdout) < 60:
                    fail("shipped pytest run executed fewer than 60 tests "
                         f"({_passed_count(shipped.stdout)} passed)")
                if hidden.returncode != 0:
                    tail = (hidden.stdout or "")[-1500:]
                    fail("hidden pytest suite is not green:\n" + tail)
                elif _passed_count(hidden.stdout) < 30:
                    fail("hidden pytest run executed fewer than 30 tests "
                         f"({_passed_count(hidden.stdout)} passed)")
        finally:
            shutil.rmtree(hidden_dir, ignore_errors=True)

    # ---- 5) example e2e -------------------------------------------------
    example = REPO / "examples"
    if not (example / "quaydoc.toml").is_file():
        fail("shipped example site missing")
    else:
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            outdir = os.path.join(tmp, "site")
            build = run(sys.executable, "-m", "quaydoc.cli", "build",
                        str(example), "-o", outdir)
            if build.returncode != 0:
                fail("example build failed:\n" + build.stderr[-800:])
            else:
                check = run(sys.executable, "-m", "quaydoc.cli", "check",
                            outdir)
                if check.returncode != 0:
                    fail("example check reports issues:\n"
                         + check.stdout[-800:])

    return _finish(0 if not failures else 1)


def _shipped_test_count():
    collect = run(sys.executable, "-m", "pytest", "--collect-only", "-q",
                  "-c", "/dev/null", "tests")
    m = re.search(r"(\d+) tests? collected",
                  (collect.stdout or "") + (collect.stderr or ""))
    return int(m.group(1)) if m else None


_PASSED_RE = re.compile(r"(\d+) passed")


def _passed_count(output):
    """Tests actually executed and passed in a pytest -q run."""
    m = _PASSED_RE.search(output or "")
    return int(m.group(1)) if m else 0


def _finish(code):
    if failures:
        print("FAILURES:")
        for msg in failures:
            print("  - " + msg)
    else:
        print("ALL PASS: repository shape, postmortem commit, fix, suite "
              "and example build/check are all green")
    return code


if __name__ == "__main__":
    sys.exit(main())