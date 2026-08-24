#!/usr/bin/env python3
"""item-064-main verifier: recompute expected classification + legal moves with
an independent reference ruleset, and reward /app/output.json against it.

Writes a reward 0..1 to /logs/verifier/reward.txt.
"""
import json
import sys

sys.path.insert(0, "/app")
from engine import substitute, classify  # noqa: E402
import chess  # noqa: E402

REWARD = "/logs/verifier/reward.txt"


def build_reference():
    rules = json.load(open("/tests/reference_rules.json"))
    records = [ln.rstrip("\n") for ln in open("/app/records.txt", encoding="utf-8")
               if ln.strip()]
    ref = []
    subs = rules.get("substitution", [])
    clsr = rules.get("classification", [])
    for line in records:
        canon = substitute(line, subs)
        cl = classify(canon, clsr)
        e = {"text": line, "canonical": canon, "kind": cl["kind"],
             "verdict": cl["verdict"]}
        if cl["kind"] == "fen" and cl["verdict"] == "valid":
            try:
                e["moves"] = sorted(str(m) for m in chess.Board(line).legal_moves)
            except Exception as exc:
                e["moves_error"] = repr(exc)
        ref.append(e)
    return ref


def main():
    try:
        ref = build_reference()
        got = json.load(open("/app/output.json"))
    except Exception as exc:
        open(REWARD, "w").write("0.0")
        print("verifier exception building reference:", repr(exc), file=sys.stderr)
        return

    if not isinstance(got, list) or len(got) != len(ref):
        open(REWARD, "w").write("0.0")
        print("length mismatch", len(got) if isinstance(got, list) else None, len(ref),
              file=sys.stderr)
        return

    correct = 0
    for re_, go in zip(ref, got):
        ok = True
        for key in ("text", "canonical", "kind", "verdict"):
            if re_.get(key) != go.get(key):
                ok = False
        if ok:
            rm = re_.get("moves")
            gm = go.get("moves")
            if "moves" in re_ :
                if not isinstance(gm, list) or sorted(gm) != rm:
                    ok = False
        if ok:
            correct += 1
    frac = correct / len(ref)
    reward = round(frac, 3)
    open(REWARD, "w").write(repr(reward))
    print(f"record accuracy {correct}/{len(ref)} -> reward {reward}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())