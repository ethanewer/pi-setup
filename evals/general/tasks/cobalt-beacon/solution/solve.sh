#!/bin/bash
# Oracle for cobalt-beacon: author /app/solve.py (the real deliverable), then
# run it on the visible fixtures to produce /app/answer.json. Never reads /tests.
set -eu

SOLVER="/app/solve.py"

# ---- 1. Write the deliverable program (this IS the work).
cat > "$SOLVER" <<'PY'
import hashlib
import importlib.util
import json
import sys


def load_generator(path):
    spec = importlib.util.spec_from_file_location("beacon_gen", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def load_target(path):
    n = None
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            if line.startswith("letters="):
                n = int(line.split("=", 1)[1].strip())
    if n is None:
        raise ValueError("target file has no letters= line")
    return n


def letter_count(code):
    digest = hashlib.sha1(code.encode("utf-8")).hexdigest()
    return sum(1 for ch in digest if ch in "abcdef")


def main():
    gen_path, target_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
    gen = load_generator(gen_path)
    target = load_target(target_path)

    matches = []
    for seed in range(int(gen.SEED_LO), int(gen.SEED_HI)):
        code = gen.beacon_code(seed)
        if letter_count(code) == target:
            matches.append(code)

    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(
            {"target": target, "matches": matches, "match_count": len(matches)},
            fh,
            indent=2,
        )


if __name__ == "__main__":
    main()
PY

chmod +x "$SOLVER"

# ---- 2. Run the program on the visible fixtures to produce /app/answer.json.
python3 "$SOLVER" /app/beacon_gen.py /app/beacon.target /app/answer.json

echo "solve.sh done -> $SOLVER and /app/answer.json"
ls -l "$SOLVER" /app/answer.json
