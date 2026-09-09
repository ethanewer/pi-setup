#!/usr/bin/env python3
"""Surgical marker/id rewrite for the 23 renamed tasks. Byte-preserving."""
import re, sys
from pathlib import Path

os_root = Path("/home/ee/pi-setup/evals/general")
mapping = [l.split() for l in open("/tmp/origmap.txt")]
changed = []

def edit(f: Path, fn):
    b = f.read_bytes()
    try:
        s = b.decode("utf-8")
    except UnicodeDecodeError:
        return
    o = fn(s)
    if o != s:
        f.write_bytes(o.encode("utf-8"))
        changed.append(str(f))

for orig, new in mapping:
    d = os_root / "tasks" / new
    assert (d / "task.toml").is_file(), d
    title = " ".join(w.capitalize() for w in new.split("-"))

    for f in sorted(d.rglob("*")):
        if f.is_file():
            edit(f, lambda s, _o=orig, _n=new: s.replace(_o, _n))

    edit(d / "task.toml",
         lambda s: re.sub(r'^[ \t]*"(?:deepswe|tblite)-skill",[ \t]*\n', "", s, flags=re.M))

    def ins_fix(s, _n=new, _t=title):
        s = re.sub(rf"^(#+) {re.escape(_n)}( [—:])", rf"\1 {_t}\2", s, flags=re.M)
        s = s.replace(
            "This task exercises the deepswe-skill family: test-harness internals in pure\n"
            "Python standard-library programming.\n\n", "")
        s = re.sub(r"^Skill family: tblite-skill \(systematic test-case generation\)\.\n", "",
                   s, flags=re.M)
        s = s.replace("exercises the tblite-skill competency of",
                      "exercises the competency of")
        return s
    edit(d / "instruction.md", ins_fix)

    edit(d / "difficulty.json",
         lambda s: re.sub(r"\((?:tblite|deepswe)-skill family\) ", "", s))
    edit(d / "difficulty.json",
         lambda s: s.replace("deepswe-skill (test-harness internals): ", ""))
    edit(d / "difficulty.json",
         lambda s: re.sub(r"(?:TBLite|tblite|deepswe)-skill", "", s))

print("files changed:", len(changed))
