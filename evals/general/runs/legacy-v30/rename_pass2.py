#!/usr/bin/env python3
"""Second-pass rename: current (badly named) new tasks -> proper two-word IDs."""
import random, subprocess
from pathlib import Path

ROOT = Path("/home/ee/pi-setup/evals/general")
TASKS = ROOT / "tasks"

CURRENT = [
 "arid-skill-ppm-image-comparison","brine-item-038-main",
 "brine-skill-redcode","coral-skill-finite-differences","echo-item-016-main",
 "elm-skill-black-box-neural-network-queries","ember-lint-forge",
 "flint-skill-cifar-10",
 "kelp-skill-fluorescent-proteins","lunar-skill-hugging-face-revision-pinning",
 "mica-skill-fixed-format-records",
 "mica-skill-semaphores-concurrency-limits","mist-item-008-main",
 "nectar-item-033-hard","raven-skill-http-headers","reed-item-032-main",
 "tern-skill-postfix","topaz-item-025-hard",
]
# already good names kept as-is: amber-engine, frost-link, fume-wheel,
# meadow-mural, rust-orchid
assert all((TASKS / c).is_dir() for c in CURRENT), "current names missing"

existing = {p.name for p in TASKS.iterdir() if p.is_dir()}
twoword = [n for n in existing if n.count("-") == 1]
first = sorted({n.split("-")[0] for n in twoword})
second = sorted({n.split("-")[1] for n in twoword})
rng = random.Random(424242)
names = set()
while len(names) < len(CURRENT):
    c = f"{rng.choice(first)}-{rng.choice(second)}"
    if c not in existing and c not in names:
        names.add(c)
MAPPING = dict(zip(CURRENT, sorted(names)))

for old, new in MAPPING.items():
    print(f"{old} -> {new}")
    subprocess.run(["git", "mv", f"evals/general/tasks/{old}",
                    f"evals/general/tasks/{new}"],
                   cwd="/home/ee/pi-setup", check=True, capture_output=True)
    d = TASKS / new
    bad_title = " ".join(w.capitalize() for w in old.split("-"))
    good_title = " ".join(w.capitalize() for w in new.split("-"))
    for f in sorted(d.rglob("*")):
        if f.is_file():
            try:
                s = f.read_text()
            except UnicodeDecodeError:
                continue
            if old in s or bad_title in s:
                f.write_text(s.replace(old, new).replace(bad_title, good_title))
print("PASS2 DONE")
