#!/bin/bash
# Real oracle for hollow-vane: write the payload.py deliverable, then RUN it on
# the visible clue set to produce /app/answer.txt. Never reads /tests.
set -eu

SOLVER="/app/payload.py"
OUT="/app/answer.txt"

# ---- 1. Write the deliverable derivation program (this IS the work).
cat > "$SOLVER" <<'PY'
import os
import re
import sys
from datetime import datetime

ENTRY_RE = re.compile(r"^entry-(\d+)\.txt$")
OPS = {"add", "sub", "mul", "xor"}


def parse_kv_line(line):
    line = line.strip()
    if not line or line.startswith("#"):
        return None
    if "=" not in line:
        return None
    key, _, val = line.partition("=")
    return key.strip(), val.strip()


def load_seed(root):
    path = os.path.join(root, "seed.env")
    try:
        with open(path, "r", encoding="utf-8") as fh:
            lines = fh.readlines()
    except OSError:
        return 0
    for raw in lines:
        kv = parse_kv_line(raw)
        if kv is None:
            continue
        key, val = kv
        if key == "SEED":
            try:
                return int(val)
            except ValueError:
                return 0
    return 0


def load_cutoff(root):
    path = os.path.join(root, "cutoff.txt")
    try:
        with open(path, "r", encoding="utf-8") as fh:
            for raw in fh:
                tok = raw.strip()
                if not tok:
                    continue
                return datetime.strptime(tok, "%Y-%m-%d").date()
    except (OSError, ValueError):
        pass
    return None


def parse_entry(path):
    fields = {}
    with open(path, "r", encoding="utf-8") as fh:
        for raw in fh:
            line = raw.strip()
            if not line or ":" not in line:
                continue
            key, _, val = line.partition(":")
            fields[key.strip().lower()] = val.strip()
    if "date" not in fields or "op" not in fields or "value" not in fields:
        return None
    try:
        date = datetime.strptime(fields["date"], "%Y-%m-%d").date()
        value = int(fields["value"])
    except ValueError:
        return None
    op = fields["op"]
    if op not in OPS:
        return None
    return date, op, value


def derive(root):
    value = load_seed(root)
    cutoff = load_cutoff(root)

    journal = os.path.join(root, "journal")
    entries = []
    if os.path.isdir(journal):
        for name in os.listdir(journal):
            m = ENTRY_RE.match(name)
            if not m:
                continue
            parsed = parse_entry(os.path.join(journal, name))
            if parsed is None:
                continue
            entries.append((int(m.group(1)), parsed))
    entries.sort(key=lambda item: item[0])

    for _n, (date, op, operand) in entries:
        if cutoff is not None and date < cutoff:
            continue
        if op == "add":
            value = value + operand
        elif op == "sub":
            value = value - operand
        elif op == "mul":
            value = value * operand
        elif op == "xor":
            value = value ^ operand
    return value


def main():
    root = sys.argv[1]
    payload = derive(root)
    text = str(payload) + "\n"
    print(text, end="")
    out = sys.argv[2] if len(sys.argv) > 2 else "/app/answer.txt"
    if out != "-":
        parent = os.path.dirname(out)
        if parent:
            os.makedirs(parent, exist_ok=True)
        with open(out, "w", encoding="utf-8") as fh:
            fh.write(text)


if __name__ == "__main__":
    main()
PY

chmod +x "$SOLVER"

# ---- 2. Run the produced program on the visible clue set.
python3 "$SOLVER" /app/clues "$OUT"

echo "solve.sh done -> $SOLVER and $OUT"
ls -l "$SOLVER" "$OUT"