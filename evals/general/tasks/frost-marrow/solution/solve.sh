#!/bin/bash
# Real oracle for frost-marrow: write the forge.py program, then RUN it on the
# provided artifact directory to produce /app/answer.txt. Never reads /tests.
set -eu

FORGER="/app/forge.py"
ARTDIR="/app/artifacts"
OUT="/app/answer.txt"

# ---- 1. Write the deliverable program (this IS the work, not a canned answer).
cat > "$FORGER" <<'PY'
import os
import sys


def read_base(serial_path):
    with open(serial_path, "r", encoding="utf-8") as fh:
        for line in fh:
            text = line.strip()
            if not text:
                continue
            return int(text)  # raises ValueError if not an integer
    raise ValueError("serial.txt has no non-blank line")


def read_prices(pricebook_path):
    prices = {}
    with open(pricebook_path, "r", encoding="utf-8") as fh:
        for raw in fh:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            fields = line.split()
            if len(fields) < 2:
                continue
            label, price_tok = fields[0], fields[1]
            try:
                prices[label] = int(price_tok)
            except ValueError:
                continue
    return prices


def ledger_rows(ledger_path):
    with open(ledger_path, "r", encoding="utf-8") as fh:
        for raw in fh:
            line = raw.strip()
            if not line:
                continue
            fields = [f.strip() for f in line.split(",")]
            if len(fields) < 2:
                continue
            label = fields[0]
            if label == "label":
                continue  # header row
            try:
                qty = int(fields[1])
            except ValueError:
                continue
            yield label, qty


def derive(artifact_dir):
    total = read_base(os.path.join(artifact_dir, "serial.txt"))
    prices = read_prices(os.path.join(artifact_dir, "pricebook.tsv"))
    for label, qty in ledger_rows(os.path.join(artifact_dir, "ledger.csv")):
        if label not in prices:
            continue
        total += qty * prices[label]
    return "OK-%05d" % (total % 100000)


def main():
    if len(sys.argv) < 2:
        print("usage: forge.py <artifact_dir> [outfile]", file=sys.stderr)
        return 2
    artifact_dir = sys.argv[1]
    payload = derive(artifact_dir)
    out_path = sys.argv[2] if len(sys.argv) > 2 else "/app/answer.txt"
    print(payload)
    if out_path != "-":
        parent = os.path.dirname(os.path.abspath(out_path))
        os.makedirs(parent, exist_ok=True)
        with open(out_path, "w", encoding="utf-8") as fh:
            fh.write(payload + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
PY
chmod +x "$FORGER"

# ---- 2. Run the produced program on the provided artifacts (default outfile).
python3 "$FORGER" "$ARTDIR" "$OUT"

echo "solve.sh done -> $FORGER and $OUT"
cat "$OUT"
