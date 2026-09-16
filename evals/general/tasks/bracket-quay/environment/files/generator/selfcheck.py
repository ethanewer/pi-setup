#!/usr/bin/env python3
"""Build-time self-check for the bracket-quay fixture.

Runs inside the generated repository (/app/quayside) after the corpus has
been committed, and proves the properties the task depends on BEFORE the
image is shipped:

1. shape contract: module count, package LOC, commit count, shipped test
   count,
2. the hidden-style checks are RED on the pristine (regressed) tree,
3. the canonical repair (removing the two special-cased replacements in
   toc.AnchorMap.anchor_for, restoring the shared slugifier's semantics)
   turns them GREEN, and leaves the shipped suite green too,
4. git history attributes the regression to exactly one commit (the
   "friendlier anchor ids" commit).

Phase 3 mutates quaydoc/toc.py, then restores it, so the delivered tree is
exactly the regressed final state (git checkout of the HEAD blob).
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

REPO = Path("/app/quayside")
SELFCHECK = Path("/app/generator/selfcheck")
MARKER = 'text = text.replace("&", "and")'

BUGGY_BLOCK = '''        text = str(title)
        text = text.replace("&", "and")
        text = text.replace(":", "")
        slug = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
        slug = re.sub(r"-{2,}", "-", slug)
        return slug or "section"
'''
FIXED_BLOCK = '''        text = str(title)
        slug = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
        slug = re.sub(r"-{2,}", "-", slug)
        return slug or "section"
'''


def run(*args, cwd=None):
    return subprocess.run(args, capture_output=True, text=True, cwd=cwd)


def example_check():
    """Build examples/ and run quaydoc check; return 0 iff check is clean."""
    import tempfile
    with tempfile.TemporaryDirectory() as tmp:
        outdir = os.path.join(tmp, "site")
        build = run(sys.executable, "-m", "quaydoc.cli", "build",
                    str(REPO / "examples"), "-o", outdir, cwd=str(REPO))
        if build.returncode != 0:
            return 1
        check = run(sys.executable, "-m", "quaydoc.cli", "check", outdir,
                    cwd=str(REPO))
        return check.returncode


def count_py_lines(path):
    return sum(len(p.read_text(errors="replace").splitlines())
               for p in sorted(Path(path).rglob("*.py"))
               if "__pycache__" not in str(p))


def main() -> int:
    problems = []

    # ---- 1) shape contract ----------------------------------------------
    modules = [p for p in (REPO / "quaydoc").glob("*.py")]
    pkg_loc = count_py_lines(REPO / "quaydoc")
    total_loc = count_py_lines(REPO)
    revs = run("git", "-C", str(REPO), "rev-list", "--count", "HEAD")
    commits = int(revs.stdout.strip() or "0")

    if not (27 <= len(modules) <= 42):
        problems.append(f"package module count {len(modules)} outside 27..42")
    if not (6000 <= pkg_loc <= 9500):
        problems.append(f"package LOC {pkg_loc} outside 6000..9500")
    if total_loc < 6500:
        problems.append(f"total repo Python LOC {total_loc} below 6500")
    if commits < 28:
        problems.append(f"commit count {commits} below 28")

    collect = run(sys.executable, "-m", "pytest", "--collect-only", "-q",
                  "tests", cwd=str(REPO))
    m = re.search(r"(\d+) tests? collected",
                  (collect.stdout or "") + (collect.stderr or ""))
    n_tests = int(m.group(1)) if m else 0
    if n_tests < 60:
        problems.append(f"shipped test count {n_tests} below 60")

    # ---- 2) regression attribution --------------------------------------
    log = run("git", "-C", str(REPO), "log", "--reverse", "-S", MARKER,
              "--format=%H", "--", "quaydoc/toc.py")
    lines = [l for l in log.stdout.splitlines() if l.strip()]
    if len(lines) != 1:
        problems.append(f"expected 1 introducing commit, found {lines}")
    else:
        subject = run("git", "-C", str(REPO), "log", "-1", "--format=%s",
                      lines[0])
        if "friendlier anchor" not in subject.stdout:
            problems.append(f"unexpected introducing commit subject: "
                            f"{subject.stdout.strip()!r}")
        # and no other tracked file may carry the marker
        grep = run("git", "-C", str(REPO), "grep", "-n", "-F", MARKER)
        if grep.returncode == 0:
            hit = grep.stdout.strip().splitlines()
            allow = [h for h in hit if h.startswith("quaydoc/toc.py:")]
            if len(hit) != 1 or not allow:
                problems.append(f"marker present in: {hit}")

    # ---- 3) red on pristine ---------------------------------------------
    shutil.rmtree(REPO / "tests_selfcheck", ignore_errors=True)
    (REPO / "tests_selfcheck").mkdir()
    for name in sorted(os.listdir(SELFCHECK)):
        if name.endswith(".py"):
            shutil.copyfile(SELFCHECK / name, REPO / "tests_selfcheck" / name)

    red = run(sys.executable, "-m", "pytest", "-q", "tests", "tests_selfcheck",
              cwd=str(REPO))
    if red.returncode == 0:
        problems.append("pristine tree passes hidden-style checks "
                        "(expected red)")
    elif "tests_selfcheck" not in (red.stdout + red.stderr):
        problems.append("pristine failures do not mention selfcheck tests")

    # the shipped example site carries the trigger headings from the bug
    # report: its build+check must FAIL on the pristine (regressed) tree
    if example_check() == 0:
        problems.append("example build+check is clean on the pristine "
                        "tree (expected broken fragments)")

    # ---- 4) green after the canonical repair ----------------------------
    toc = (REPO / "quaydoc/toc.py").read_text(encoding="utf-8")
    if toc.count(BUGGY_BLOCK) != 1:
        problems.append(f"buggy block appears {toc.count(BUGGY_BLOCK)} times")
    else:
        (REPO / "quaydoc/toc.py").write_text(
            toc.replace(BUGGY_BLOCK, FIXED_BLOCK), encoding="utf-8")
        green = run(sys.executable, "-m", "pytest", "-q", "tests",
                    "tests_selfcheck", cwd=str(REPO))
        if green.returncode != 0:
            problems.append("repaired tree fails shipped+selfcheck tests; "
                            "output tail: " + green.stdout[-600:])
        if example_check() != 0:
            problems.append("example build+check fails after the canonical "
                            "repair")
        # restore the pristine regressed state
        reset = run("git", "-C", str(REPO), "checkout", "--", "quaydoc/toc.py")
        if reset.returncode != 0:
            problems.append("could not restore toc.py from git")

    shutil.rmtree(REPO / "tests_selfcheck", ignore_errors=True)
    shutil.rmtree(REPO / ".pytest_cache", ignore_errors=True)

    if problems:
        print("SELFCHECK FAILURES:")
        for p in problems:
            print("  -", p)
        return 1
    print(f"selfcheck ok: modules={len(modules)} pkg_loc={pkg_loc} "
          f"total_loc={total_loc} commits={commits} tests={n_tests}")
    return 0


if __name__ == "__main__":
    sys.exit(main())