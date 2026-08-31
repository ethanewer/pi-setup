#!/bin/bash
# Oracle for zinc-meridian: write the screening program, then RUN it on the
# visible fixtures to produce /app/formulary.json. Never reads /tests.
set -eu

SOLVER="/app/screen.py"
OUT="/app/formulary.json"

cat > "$SOLVER" <<'PY'
#!/usr/bin/env python3
"""Formulary screening: rank compounds by proximity of a computed descriptor
(molecular weight, from parsed formulas and an atomic-mass lookup) to a target.
"""
import argparse
import json
import os
import re


def parse_formula(formula):
    """Parse a molecular formula into {element: count}.

    Grammar (deterministic):
      formula := term ('.' term)*
      term    := INT? group+            (INT = leading multiplier of the term)
      group   := ELEMENT INT? | '(' formula-fragment ')' INT?
    Raises ValueError on any syntax error or unknown element symbol.
    """
    masses = parse_formula.masses
    total = {}
    for term in formula.split("."):
        term = term.strip()
        if not term:
            raise ValueError("empty term")
        multiplier = 1
        m = re.match(r"^(\d+)(.*)$", term)
        if m:
            multiplier = int(m.group(1))
            if multiplier < 1:
                raise ValueError("bad multiplier")
            term = m.group(2)
        counts = _parse_term(term, masses)
        for el, n in counts.items():
            total[el] = total.get(el, 0) + n * multiplier
    return total


def _parse_term(term, masses):
    counts = {}
    i = 0
    n = len(term)
    while i < n:
        ch = term[i]
        if ch == "(":
            depth = 1
            j = i + 1
            while j < n and depth:
                if term[j] == "(":
                    depth += 1
                elif term[j] == ")":
                    depth -= 1
                j += 1
            if depth:
                raise ValueError("unbalanced parentheses")
            inner = _parse_term(term[i + 1:j - 1], masses)
            m = re.match(r"^(\d+)", term[j:])
            mult = int(m.group(1)) if m else 1
            if m and mult < 1:
                raise ValueError("bad group multiplier")
            for el, k in inner.items():
                counts[el] = counts.get(el, 0) + k * mult
            i = j + (len(m.group(1)) if m else 0)
        elif ch.isupper():
            m = re.match(r"^([A-Z][a-z]?)(\d*)", term[i:])
            if not m:
                raise ValueError("bad element at %d" % i)
            el, cnt = m.group(1), m.group(2)
            if el not in masses:
                raise ValueError("unknown element %r" % el)
            counts[el] = counts.get(el, 0) + (int(cnt) if cnt else 1)
            i += len(m.group(0))
        else:
            raise ValueError("unexpected character %r" % ch)
    if not counts:
        raise ValueError("empty term")
    return counts


def molecular_weight(counts, masses):
    return round(sum(masses[el] * k for el, k in counts.items()), 4)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--compounds", default="/app/compounds.json")
    ap.add_argument("--masses", default="/app/atomic_masses.json")
    ap.add_argument("--target", default="/app/target.json")
    ap.add_argument("--output", default="/app/formulary.json")
    args = ap.parse_args()

    with open(args.masses, encoding="utf-8") as fh:
        masses = json.load(fh)
    parse_formula.masses = masses
    with open(args.target, encoding="utf-8") as fh:
        tgt = json.load(fh)
    descriptor = tgt["descriptor"]
    target = float(tgt["target"])
    tolerance = float(tgt["tolerance"])

    with open(args.compounds, encoding="utf-8") as fh:
        compounds = json.load(fh)

    matches = []
    rejected = []
    parsed = 0
    for row in compounds:
        cid = str(row.get("id", ""))
        formula = row.get("formula")
        if not isinstance(formula, str):
            rejected.append(cid)
            continue
        try:
            counts = parse_formula(formula)
        except ValueError:
            rejected.append(cid)
            continue
        parsed += 1
        if descriptor != "molecular_weight":
            raise ValueError("unsupported descriptor %r" % descriptor)
        mw = molecular_weight(counts, masses)
        dist = round(abs(mw - target), 4)
        if dist <= tolerance:
            matches.append({
                "id": cid,
                "name": row.get("name", ""),
                "formula": formula,
                "molecular_weight": mw,
                "distance": dist,
                "score": round(1.0 / (1.0 + dist), 6),
            })

    matches.sort(key=lambda m: (m["distance"], m["id"]))

    result = {
        "descriptor": descriptor,
        "target": target,
        "tolerance": tolerance,
        "matches": matches,
        "report": {
            "rows_in": len(compounds),
            "rows_parsed": parsed,
            "rows_rejected": len(rejected),
            "rejected_ids": sorted(rejected),
            "matched": len(matches),
        },
    }

    out_dir = os.path.dirname(os.path.abspath(args.output))
    os.makedirs(out_dir, exist_ok=True)
    with open(args.output, "w", encoding="utf-8") as fh:
        json.dump(result, fh, indent=2)


if __name__ == "__main__":
    main()
PY

chmod +x "$SOLVER"

python3 "$SOLVER"

echo "solve.sh done -> $SOLVER and $OUT"
ls -l "$SOLVER" "$OUT"
