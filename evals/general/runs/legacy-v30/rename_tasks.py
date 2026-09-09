#!/usr/bin/env python3
"""Rename the 23 new tasks to opaque two-word IDs and scrub provenance markers.
Run from evals/general. Uses git mv so history is preserved."""
import random, re, subprocess, sys
from pathlib import Path

ROOT = Path("/home/ee/pi-setup/evals/general")
TASKS = ROOT / "tasks"

NEW_TASKS = sorted(
    [p.name for p in TASKS.iterdir()
     if re.match(r"^(tb3|tl|ds)-", p.name) or p.name in ("cedar-summit", "flint-gate")]
)
assert len(NEW_TASKS) == 23, len(NEW_TASKS)

existing = {p.name for p in TASKS.iterdir() if p.is_dir()}
first = sorted({n.split("-")[0] for n in existing})
second = sorted({n.split("-", 1)[1] for n in existing if "-" in n})
rng = random.Random(31337)
names, tries = set(), 0
while len(names) < 23:
    tries += 1
    c = f"{rng.choice(first)}-{rng.choice(second)}"
    if c not in existing and c not in names:
        names.add(c)
NEW_NAMES = {old: new for old, new in zip(NEW_TASKS, sorted(names))}

def rewrite_text(p: Path, old: str, new: str):
    try:
        s = p.read_text()
    except UnicodeDecodeError:
        return False
    if old not in s:
        return False
    s = s.replace(old, new)
    # scrub family markers
    s = re.sub(r'^[ \t]*"?(?:deepswe|tblite)-skill"?,?[ \t]*\n', "", s, flags=re.M)
    # provenance sentences
    s = s.replace(
        "This task exercises the deepswe-skill family: test-harness internals in pure\n"
        "Python standard-library programming.\n\n", "")
    s = re.sub(r"^Skill family: tblite-skill \(systematic test-case generation\)\.\n+",
               "", s, flags=re.M)
    s = re.sub(r"(TBLite|tblite|deepswe)-skill competency", "competency", s)
    s = re.sub(r"(TBLite|tblite|deepswe)-skill", "", s)
    s = re.sub(r"  +", " ", s)
    # heading with bare old id -> title-cased new name (id already replaced above)
    title = " ".join(w.capitalize() for w in new.split("-"))
    s = re.sub(rf"^(#+ ){re.escape(new)}( [—:])", rf"\g<1>{title}\g<2>", s, flags=re.M)
    p.write_text(s)
    return True

for old, new in NEW_NAMES.items():
    print(f"{old} -> {new}")
    subprocess.run(["git", "mv", f"evals/general/tasks/{old}",
                    f"evals/general/tasks/{new}"],
                   cwd="/home/ee/pi-setup", check=True, capture_output=True)
    d = TASKS / new
    for f in sorted(d.rglob("*")):
        if f.is_file():
            rewrite_text(f, old, new)

print("RENAMES DONE")
