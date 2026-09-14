#!/usr/bin/env python3
"""Materialise the pristine parent scipy tree into a target directory.

Used by both the oracle (solve.sh) and the verifier (test.sh) so the two
sides cannot drift. The result is a self-contained scipy package:

  * tracked tree comes from `git archive HEAD` (the parent commit);
  * compiled extensions, generated files (__config__.py, version.py) and the
    vendored subprojects (array_api_compat / array_api_extra) come from
    meson-python's own install plan (/tmp/sci-build/meson-info/
    intro-install_plan.json) -- the exact mapping the editable loader uses at
    runtime;
  * every tracked .py under scipy/ is then overwritten with the parent
    commit's bytes, so the pure-Python sources are exactly the buggy parent's
    even if the checked-out tree was later fixed.

Imports against the materialised tree are made with the editable finder
disabled (MESONPY_EDITABLE_SKIP=/tmp/sci-build), so plain sys.path ordering
selects this tree.
"""
import json
import os
import shutil
import subprocess
import sys

SRC = "/app/src"
PLAN = "/tmp/sci-build/meson-info/intro-install_plan.json"


def main() -> int:
    target = sys.argv[1]
    proc = subprocess.run(["git", "-C", SRC, "archive", "HEAD"], check=True, capture_output=True)
    subprocess.run(["tar", "-xf", "-", "-C", target], input=proc.stdout, check=True)

    plan = json.load(open(PLAN))
    copied = 0
    for section in plan.values():
        for src, meta in section.items():
            dst = meta["destination"]
            if not dst.startswith("{py_") or "/scipy/" not in dst:
                continue
            rel = dst.split("/scipy/", 1)[1]
            out = os.path.join(target, "scipy", rel)
            os.makedirs(os.path.dirname(out) or target, exist_ok=True)
            if os.path.isdir(src):
                shutil.copytree(src, out, dirs_exist_ok=True)
            else:
                shutil.copy(src, out)
            copied += 1

    ls = subprocess.run(
        ["git", "-C", SRC, "ls-tree", "-r", "--name-only", "HEAD", "scipy/"],
        capture_output=True, text=True, check=True,
    )
    n = 0
    for rel in ls.stdout.splitlines():
        if not rel.endswith(".py"):
            continue
        blob = subprocess.run(["git", "-C", SRC, "show", f"HEAD:{rel}"],
                              check=True, capture_output=True).stdout
        with open(os.path.join(target, rel), "wb") as f:
            f.write(blob)
        n += 1
    print(f"materialised {copied} plan entries + {n} parent .py files into {target}")
    return 0


if __name__ == "__main__":
    sys.exit(main())