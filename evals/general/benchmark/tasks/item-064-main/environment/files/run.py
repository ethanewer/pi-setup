#!/usr/bin/env python3
"""Pipeline driver for item-064. FIXED — do not modify this file.

Reads /app/records.txt and /app/rules.json, classifies each record through
engine.py, attaches legal moves (via /app/moves.legal_moves) to every record
classified as a *valid* FEN, and writes /app/output.json.
"""

import json

from engine import substitute, classify


def main():
    with open("/app/rules.json") as f:
        rules = json.load(f)
    with open("/app/records.txt", encoding="utf-8") as f:
        records = [line.rstrip("\n") for line in f if line.strip()]

    out = []
    subs = rules.get("substitution", [])
    clsr = rules.get("classification", [])

    for line in records:
        canon = substitute(line, subs)
        cl = classify(canon, clsr)
        entry = {
            "text": line,
            "canonical": canon,
            "kind": cl["kind"],
            "verdict": cl["verdict"],
        }
        if cl["kind"] == "fen" and cl["verdict"] == "valid":
            try:
                from moves import legal_moves
                entry["moves"] = legal_moves(line)
            except Exception as exc:  # pragma: no cover
                entry["moves"] = ["ERROR"]
                entry["moves_error"] = repr(exc)
        out.append(entry)

    with open("/app/output.json", "w") as f:
        json.dump(out, f, indent=2)


if __name__ == "__main__":
    main()