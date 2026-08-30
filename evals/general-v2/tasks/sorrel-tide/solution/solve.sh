#!/bin/bash
# Oracle for sorrel-tide: author the reusable solver, then RUN it on the visible
# generator to produce /app/candidates.txt and /app/answer.json. Never reads /tests.
set -eu

# ---- 1. The solver (this IS the work) --------------------------------------
cat > /app/solve.py <<'PY'
#!/usr/bin/env python3
"""Loomis relay vault recovery solver.

Usage:
    python3 solve.py <generator.py> <candidates_out.txt> <answer_out.json>

Enumerates every well-formed keycard emitted on the active duty roster, writes
each one to the candidates file (ascending serial order), then selects the
unique candidate whose SHA-256 digest residue matches the vault pin.
"""
import hashlib
import importlib.util
import json
import sys


def load_generator(path):
    spec = importlib.util.spec_from_file_location("relay_keycard_gen", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    if len(sys.argv) != 4:
        print("usage: solve.py <generator.py> <candidates_out> <answer_out>",
              file=sys.stderr)
        return 2
    gen_path, cand_out, ans_out = sys.argv[1], sys.argv[2], sys.argv[3]
    gen = load_generator(gen_path)

    # Part 1: enumerate candidates — rostered serials only, exact format.
    entries = []  # (serial, token)
    for serial in range(gen.SERIAL_HI):
        if not gen.activated(serial):
            continue
        token = gen.emit_keycard(serial)
        if gen.is_well_formed(token):
            entries.append((serial, token))
    entries.sort(key=lambda e: e[0])

    with open(cand_out, "w", encoding="utf-8") as fh:
        for _serial, token in entries:
            fh.write(token + "\n")

    # Part 2: unique SHA-256 residue match selects the vault keycard.
    matches = []
    for serial, token in entries:
        digest = hashlib.sha256(token.encode("utf-8")).hexdigest()
        if int(digest, 16) % gen.VAULT_MODULUS == gen.VAULT_PIN:
            matches.append((serial, token))
    if len(matches) != 1:
        print("expected exactly one residue match, got %d" % len(matches),
              file=sys.stderr)
        return 1
    active_serial, keycard = matches[0]

    answer = {
        "keycard": keycard,
        "active_serial": int(active_serial),
        "candidate_count": len(entries),
        "pin": int(gen.VAULT_PIN),
        "modulus": int(gen.VAULT_MODULUS),
    }
    with open(ans_out, "w", encoding="utf-8") as fh:
        json.dump(answer, fh, indent=2)
    print("SOLVE_OK candidates=%d active_serial=%d" % (len(entries), active_serial))
    return 0


if __name__ == "__main__":
    sys.exit(main())
PY

chmod +x /app/solve.py

# ---- 2. Produce the visible deliverables by actually running ----------------
python3 /app/solve.py /app/keycard_gen.py /app/candidates.txt /app/answer.json

echo "solve.sh done"
ls -l /app/solve.py /app/candidates.txt /app/answer.json
