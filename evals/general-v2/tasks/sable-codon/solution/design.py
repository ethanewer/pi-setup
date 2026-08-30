#!/usr/bin/env python3
"""Sable Codon — site-directed mutagenesis primer designer (QuikChange-style).

python3 design.py --scene SCENE.json --out OUT.json

The scene names a template FASTA record, a 1-based inclusive sense-strand
locus [start, end] whose wild-type bases are replaced by `insert` (which may
be shorter, equal, or longer; end == start-1 denotes a pure insertion), and
the anneal-length / Tm / GC constraints for the two mutagenic primers.

Forward primer (5'->3')  = up(L_f) + insert + down(R_f)
Reverse primer (5'->3')  = rc( up(L_r) + insert + down(R_r) )
                         = rc(down(R_r)) + rc(insert) + rc(up(L_r))

Wallace Tm over the ENTIRE primer:  Tm = 2*(A+T) + 4*(G+C).
"""
import argparse
import json
import sys

STRICT_ACGT = set("ACGT")


class DesignError(Exception):
    def __init__(self, token):
        super().__init__(token)
        self.token = token


def rc(s):
    return s.translate(str.maketrans("ACGT", "TGCA"))[::-1]


def parse_fasta(path):
    """Return list of (id, seq); id = first whitespace token after '>'."""
    try:
        with open(path, "r", encoding="utf-8") as fh:
            text = fh.read()
    except OSError:
        raise DesignError("template-unreadable")
    records = []
    cur_id = None
    chunks = []
    saw_any = False
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        if line.startswith(">"):
            if cur_id is not None:
                records.append((cur_id, "".join(chunks)))
            cur_id = line[1:].split()[0] if len(line) > 1 else ""
            chunks = []
            saw_any = True
        else:
            if cur_id is None:
                # sequence data before any header
                raise DesignError("template-unreadable")
            chunks.append(line)
    if cur_id is not None:
        records.append((cur_id, "".join(chunks)))
    if not saw_any or not records:
        raise DesignError("template-unreadable")
    return records


def check_bases(seq, err):
    up = seq.upper()
    for ch in up:
        if ch not in STRICT_ACGT:
            raise DesignError(err)
    return up


def wallace(seq):
    at = sum(1 for c in seq if c in "AT")
    gc = sum(1 for c in seq if c in "GC")
    return 2 * at + 4 * gc


def gc_percent(seq):
    gc = sum(1 for c in seq if c in "GC")
    return 100.0 * gc / len(seq)


def pick(upstream, downstream, insert, anneal, tm, gc):
    """Pick (L, R) minimising (|Tm-target|, L+R, L) over viable candidates."""
    best = None
    for lf in range(anneal["min"], anneal["max"] + 1):
        if lf > len(upstream):
            break
        for lr in range(anneal["min"], anneal["max"] + 1):
            if lr > len(downstream):
                break
            seq = upstream[len(upstream) - lf :] + insert + downstream[:lr]
            t = wallace(seq)
            g = gc_percent(seq)
            if not (tm["min"] <= t <= tm["max"]):
                continue
            if not (gc["min"] <= g <= gc["max"]):
                continue
            key = (abs(t - tm["target"]), lf + lr, lf)
            if best is None or key < best[0]:
                best = (key, lf, lr, seq, t, g)
    return best


def design(scene):
    anneal = scene["anneal"]
    tm = scene["tm"]
    gc = scene["gc"]
    for box in (anneal, tm, gc):
        if "min" not in box or "max" not in box:
            raise DesignError("scene-invalid")
    if "target" not in tm:
        raise DesignError("scene-invalid")

    start = scene["locus"]["start"]
    end = scene["locus"]["end"]
    insert = scene["insert"]
    template_id = scene["template_id"]

    records = parse_fasta(scene["template"])
    seq = None
    for rid, rseq in records:
        if rid == template_id:
            seq = rseq
            break
    if seq is None:
        raise DesignError("template-id-not-found")
    seq = check_bases(seq, "non-standard-nucleotide")
    insert = check_bases(insert, "insert-nonstandard")

    if not (start >= 1 and end >= start - 1 and end <= len(seq)):
        raise DesignError("locus-out-of-range")
    if start - 1 < anneal["min"]:
        raise DesignError("insufficient-upstream")
    if len(seq) - end < anneal["min"]:
        raise DesignError("insufficient-downstream")

    up = seq[: start - 1]
    down = seq[end:]

    fwd = pick(up, down, insert, anneal, tm, gc)
    if fwd is None:
        raise DesignError("no-viable-design-forward")
    rev = pick(up, down, insert, anneal, tm, gc)
    if rev is None:
        raise DesignError("no-viable-design-reverse")

    _, lf, lr, fseq, ftm, fgc = fwd
    _, lf2, lr2, rseq, rtm, rgc = rev
    forward = {
        "seq": fseq,
        "upstream_len": lf,
        "downstream_len": lr,
        "tm": float(ftm),
        "gc_percent": round(fgc, 1),
    }
    reverse = {
        "seq": rc(rseq),
        "upstream_len": lf2,
        "downstream_len": lr2,
        "tm": float(rtm),
        "gc_percent": round(rgc, 1),
    }
    return forward, reverse


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--scene", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    try:
        with open(args.scene, "r", encoding="utf-8") as fh:
            scene = json.load(fh)
    except Exception:
        print("error: scene file missing or unreadable", file=sys.stderr)
        sys.exit(2)

    need = ["template", "template_id", "locus", "insert", "anneal", "tm", "gc"]
    if not isinstance(scene, dict) or any(k not in scene for k in need):
        print("error: scene missing required fields", file=sys.stderr)
        sys.exit(2)

    base = {
        "template_id": scene["template_id"],
        "locus": scene["locus"],
        "insert": scene["insert"],
        "anneal_bounds": scene["anneal"],
        "tm_bounds": scene["tm"],
        "gc_bounds": scene["gc"],
    }

    try:
        forward, reverse = design(scene)
        base["error"] = None
        base["forward"] = forward
        base["reverse"] = reverse
    except DesignError as e:
        base["error"] = e.token
        base["forward"] = None
        base["reverse"] = None

    with open(args.out, "w", encoding="utf-8") as fh:
        json.dump(base, fh, indent=2)
        fh.write("\n")


if __name__ == "__main__":
    main()
