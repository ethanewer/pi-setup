#!/bin/bash
# flint-mantle oracle: writes the real implementation and runs it on the
# visible inputs. Never reads the verifier tree.
set -eu

cat > /app/solve.py <<'PYEOF'
#!/usr/bin/env python3
"""Deterministic construct assembler + Golden-Gate primer designer."""
import hashlib
import json
import sys

ARM = "GGTCTCN"
TM_LO, TM_HI = 50, 72
BODY_MIN, BODY_MAX = 15, 28
MAX_HOMO = 4
COMPLEMENT = {"A": "T", "T": "A", "G": "C", "C": "G"}


def die(msg):
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(1)


def load_json(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError) as e:
        die(f"cannot read {path}: {e}")


def tm(body):
    return 2 * (body.count("A") + body.count("T")) + 4 * (body.count("G") + body.count("C"))


def rc(seq):
    return "".join(COMPLEMENT[b] for b in reversed(seq))


def homo_ok(seq):
    run = 1
    for i in range(1, len(seq)):
        run = run + 1 if seq[i] == seq[i - 1] else 1
        if run > MAX_HOMO:
            return False
    return True


def body_ok(body):
    return TM_LO <= tm(body) <= TM_HI and homo_ok(body) and body[-1] in "GC"


def pick_body(seq):
    for m in range(BODY_MIN, BODY_MAX + 1):
        if len(seq) < m:
            break
        if body_ok(seq[:m]):
            return seq[:m]
    return None


def main():
    if len(sys.argv) != 6:
        die("usage: solve.py CONSTRUCT_JSON CODONS_JSON NAME ANSWER_OUT FASTA_OUT")
    construct = load_json(sys.argv[1])
    codons = load_json(sys.argv[2])
    name = sys.argv[3]
    answer_out, fasta_out = sys.argv[4], sys.argv[5]

    for key in ("domains", "linkers", "order"):
        if key not in construct:
            die(f"construct missing key {key}")
    domains, linkers, order = (construct["domains"], construct["linkers"],
                               construct["order"])

    protein_parts = []
    for part in order:
        if part in domains:
            protein_parts.append(domains[part])
        elif part in linkers:
            protein_parts.append(linkers[part])
        else:
            die(f"unknown part in order: {part}")
    protein = "".join(protein_parts)

    dna_parts = []
    for aa in protein:
        if aa not in codons:
            die(f"amino acid {aa!r} absent from codon table")
        dna_parts.append(codons[aa])
    dna = "".join(dna_parts)

    lines = [f">construct|{name}|len={len(protein)}"]
    lines.extend(dna[i:i + 60] for i in range(0, len(dna), 60))
    fasta = "\n".join(lines) + "\n"
    with open(fasta_out, "w", encoding="utf-8") as f:
        f.write(fasta)

    fwd = pick_body(dna)
    rev = pick_body(rc(dna))
    if fwd is None or rev is None:
        die("no primer body satisfies the constraints")

    answer = {
        "protein": protein,
        "dna": dna,
        "gc_content": round((dna.count("G") + dna.count("C")) / len(dna), 4),
        "fasta_sha256": hashlib.sha256(fasta.encode("utf-8")).hexdigest(),
        "primers": [
            {"name": "F", "seq": ARM + fwd, "tm": tm(fwd), "body_len": len(fwd)},
            {"name": "R", "seq": ARM + rev, "tm": tm(rev), "body_len": len(rev)},
        ],
    }
    with open(answer_out, "w", encoding="utf-8") as f:
        json.dump(answer, f, indent=2, sort_keys=True)
        f.write("\n")


if __name__ == "__main__":
    main()
PYEOF
chmod +x /app/solve.py

python3 /app/solve.py /app/construct.json /app/codons.json visible \
  /app/answer.json /app/constructs.fasta
