#!/bin/bash
# Real oracle for umber-prism: write the screening program, then RUN it on the
# visible fixtures to produce /app/ranked.jsonl and /app/screen_report.json.
# Never reads /tests.
set -eu

SOLVER="/app/screen.py"

# ---- 1. Write the deliverable program (this IS the work, not a canned answer).
cat > "$SOLVER" <<'PY'
#!/usr/bin/env python3
"""UmberPrism molar-mass proximity screening."""
import argparse
import json

SEP = "\u00b7"  # hydrate dot


def parse_formula(s, masses):
    """Parse a chemical formula; returns nothing, raises ValueError if invalid."""
    if not isinstance(s, str) or s == "":
        raise ValueError("not a string")
    for ch in s:
        if ch in " \t\r\n":
            raise ValueError("whitespace")
    total = {}

    def add(d, mult):
        for k, v in d.items():
            total[k] = total.get(k, 0) + v * mult

    def parse_part(part):
        def read_digits(i):
            j = i
            while j < len(part) and part[j].isdigit():
                j += 1
            return (int(part[i:j]) if j > i else 1), j

        def rec(i):
            d = {}
            while i < len(part):
                c = part[i]
                if c == "(":
                    sub, i2 = rec(i + 1)
                    if i2 >= len(part) or part[i2] != ")":
                        raise ValueError("unbalanced")
                    mult, i3 = read_digits(i2 + 1)
                    for k, v in sub.items():
                        d[k] = d.get(k, 0) + v * mult
                    i = i3
                elif c == ")":
                    return d, i
                elif c.isupper():
                    j = i + 1
                    while j < len(part) and part[j].islower():
                        j += 1
                    sym = part[i:j]
                    if sym not in masses:
                        raise ValueError("unknown element " + sym)
                    n, j2 = read_digits(j)
                    d[sym] = d.get(sym, 0) + n
                    i = j2
                else:
                    raise ValueError("bad char " + c)
            return d, i

        d, i = rec(0)
        if i != len(part):
            raise ValueError("trailing )")
        return d

    for part in s.split(SEP):
        # a part may start with a leading integer multiplier (hydrate notation:
        # CuSO4*5H2O -> part "5H2O" means 5 x (H2O))
        j = 0
        while j < len(part) and part[j].isdigit():
            j += 1
        mult = int(part[:j]) if j > 0 else 1
        rest = part[j:]
        if rest == "":
            raise ValueError("bare multiplier")
        for sub in rest.split("."):
            sub_j = 0
            while sub_j < len(sub) and sub[sub_j].isdigit():
                sub_j += 1
            sub_mult = int(sub[:sub_j]) if sub_j > 0 else 1
            sub_rest = sub[sub_j:]
            if sub_rest == "":
                raise ValueError("bare multiplier")
            add(parse_part(sub_rest), mult * sub_mult)
    return total


def molar_mass(formula, masses):
    d = parse_formula(formula, masses)
    return sum(masses[e] * n for e, n in d.items())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--compounds", required=True)
    ap.add_argument("--masses", required=True)
    ap.add_argument("--screen", required=True)
    ap.add_argument("--output-jsonl", required=True)
    ap.add_argument("--report", required=True)
    args = ap.parse_args()

    with open(args.masses) as f:
        masses = json.load(f)
    with open(args.screen) as f:
        sc = json.load(f)
    target = float(sc["target"])
    tolerance = float(sc["tolerance"])

    candidates = 0
    parsed = 0
    kept = []
    with open(args.compounds) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            candidates += 1
            try:
                row = json.loads(line)
            except Exception:
                continue
            try:
                mw = molar_mass(row.get("formula"), masses)
            except Exception:
                continue
            parsed += 1
            distance = round(abs(mw - target), 4)
            if distance <= tolerance:
                dnorm = round(distance / tolerance, 6) if tolerance > 0 else 0.0
                kept.append({
                    "id": row["id"],
                    "formula": row["formula"],
                    "molar_mass": round(mw, 4),
                    "distance": distance,
                    "dnorm": dnorm,
                    "score": round(1 - dnorm, 6),
                })
    kept.sort(key=lambda r: (r["distance"], str(r["id"])))
    report = {
        "candidates": candidates,
        "parsed": parsed,
        "kept": len(kept),
        "skipped": candidates - parsed,
        "target": target,
        "tolerance": tolerance,
    }
    with open(args.output_jsonl, "w") as f:
        for r in kept:
            f.write(json.dumps(r) + "\n")
    with open(args.report, "w") as f:
        json.dump(report, f, indent=2, sort_keys=True)


if __name__ == "__main__":
    main()
PY

chmod +x "$SOLVER"

# 2. Run the produced program on the visible fixtures to generate outputs.
python3 "$SOLVER" \
  --compounds /app/compounds.jsonl \
  --masses /app/atomic_masses.json \
  --screen /app/screen.json \
  --output-jsonl /app/ranked.jsonl \
  --report /app/screen_report.json

echo "solve.sh done -> $SOLVER /app/ranked.jsonl /app/screen_report.json"
ls -l "$SOLVER" /app/ranked.jsonl /app/screen_report.json
