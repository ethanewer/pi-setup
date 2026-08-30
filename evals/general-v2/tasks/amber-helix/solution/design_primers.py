#!/usr/bin/env python3
"""kayak-qp -- site-directed mutagenesis primer designer.

Given a scene JSON describing a target template (a FASTA with one record seen
5'->3') and a locus to replace, designs a single forward + reverse primer pair
for site-directed mutagenesis.

* Forward primer (5'->3') = template sense base-pairing region immediately
  upstream of the locus (length ``anneal_length``) followed by the mutant
  sequence.  Its 3'-most bases encode the mutation; its annealing region binds
  the antisense strand just 5' of the locus.
* Reverse primer (5'->3') = the reverse complement of the sense region
  immediately downstream of the locus (length ``anneal_length``) followed by
  the reverse complement of the mutant.  It is shown 5'->3' and its 3'-most
  bases encode the mutation on the antisense strand.

Primer annealing regions are chosen with length in [anneal_length.min, max]
such that the melting temperature (Wallace rule: Tm = 2*(A+T) + 4*(C+G)),
computed over the annealing region, lies inside [tm.min, tm.max]; when several
lengths qualify, the one whose Tm is closest to ``tm_target`` is picked.

CLI:
    python3 design_primers.py --scene SCENE.json --out PRIMERS.json
"""
from __future__ import annotations

import argparse
import json
import sys
from typing import Optional

ACGT = set("ACGT")

COMP = {"A": "T", "T": "A", "C": "G", "G": "C"}


def reverse_complement(seq: str) -> str:
    return "".join(COMP[c] for c in reversed(seq))


def wallace_tm(seq: str) -> float:
    """Melting temperature of a DNA oligo (Wallace rule), degrees Celsius."""
    if not seq:
        return 0.0
    at = seq.count("A") + seq.count("T")
    gc = seq.count("G") + seq.count("C")
    return 2.0 * at + 4.0 * gc


def _read_template(path: str) -> str:
    """Return the first FASTA record's sequence, upper-cased, no whitespace."""
    seq_parts = []
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith(">"):
                if seq_parts:
                    break
                hdr = line
                continue
            seq_parts.append("".join(ch for ch in line if ch != " "))
        if not seq_parts and "hdr" in dir():
            raise ValueError("empty FASTA: no sequence record")
    return "".join(seq_parts).upper()


def design_primers(scene: dict) -> dict:
    tpl = scene.get("template", "")
    out = {
        "template_id": scene.get("template_id", ""),
        "gene": scene.get("gene", ""),
        "locus": dict(scene.get("locus", {})),
        "mutant": scene.get("mutant", ""),
        "anneal_length_bounds": dict(scene.get("anneal_length", {})),
        "tm_bounds": dict(scene.get("tm", {})),
        "error": None,
        "forward": None,
        "reverse": None,
    }

    try:
        seq = _read_template(tpl)
    except Exception as exc:
        out["error"] = "template-unreadable: %s" % exc
        return out

    nonstd = sorted({c for c in seq if c not in ACGT})
    if nonstd:
        out["error"] = "non-standard-nucleotide: %s" % "".join(nonstd)
        return out

    locus = scene.get("locus", {})
    start = int(locus.get("start", 0))
    end = int(locus.get("end", 0))
    mutant = scene.get("mutant", "").upper().strip()
    amin = int(scene.get("anneal_length", {}).get("min", 18))
    amax = int(scene.get("anneal_length", {}).get("max", 24))
    tmin = float(scene.get("tm", {}).get("min", 55.0))
    tmax = float(scene.get("tm", {}).get("max", 64.0))
    ttarget = float(scene.get("tm", {}).get("tm_target", 60.0))

    if not (1 <= start <= end <= len(seq)):
        out["error"] = "locus-out-of-range"
        return out
    if len(mutant) != (end - start + 1):
        out["error"] = "length-mismatch"
        return out
    if any(c not in ACGT for c in mutant):
        out["error"] = "mutant-nonstandard"
        return out
    if start - 1 < amin:
        out["error"] = "insufficient-upstream"
        return out
    if len(seq) - end < amin:
        out["error"] = "insufficient-downstream"
        return out

    # forward: upstream flank on the sense strand
    def choose_len(candidates):
        best, best_d = None, None
        for L, region_tm in candidates:
            if tmin <= region_tm <= tmax:
                d = abs(region_tm - ttarget)
                if best is None or d < best_d:
                    best, best_d = (L, region_tm), d
        return best

    f_cands = []
    for L in range(amin, amax + 1):
        region = seq[start - 1 - L: start - 1]
        f_cands.append((L, region, wallace_tm(region)))
    f_best = choose_len([(L, tm) for L, _, tm in f_cands])

    r_cands = []
    for L in range(amin, amax + 1):
        region = seq[end: end + L]          # sense strand downstream of locus
        rc_region = reverse_complement(region)
        r_cands.append((L, rc_region, wallace_tm(rc_region)))
    r_best = choose_len([(L, tm) for L, _, tm in r_cands])

    if f_best is None:
        out["error"] = "no-viable-tm-forward"
        return out
    if r_best is None:
        out["error"] = "no-viable-tm-reverse"
        return out

    fL, f_tm = f_best
    f_flank = seq[start - 1 - fL: start - 1]
    forward = f_flank + mutant

    rL, r_tm = r_best
    r_region = seq[end: end + rL]
    r_flank = reverse_complement(r_region)
    reverse_pr = r_flank + reverse_complement(mutant)

    out["forward"] = {
        "seq": forward,
        "orientation": "sense-matched",
        "anneal_length": fL,
        "anneal_region": f_flank,
        "tm": round(f_tm, 2),
    }
    out["reverse"] = {
        "seq": reverse_pr,
        "orientation": "antisense-matched",
        "anneal_length": rL,
        "anneal_region": r_flank,
        "tm": round(r_tm, 2),
    }
    return out


def main(argv: Optional[list] = None) -> int:
    ap = argparse.ArgumentParser(description="Design a mutagenesis primer pair.")
    ap.add_argument("--scene", required=True, help="path to scene JSON")
    ap.add_argument("--out", required=True, help="output primers JSON path")
    args = ap.parse_args(argv)

    try:
        with open(args.scene, "r", encoding="utf-8") as fh:
            scene = json.load(fh)
    except Exception as exc:
        print("error: %s" % exc, file=sys.stderr)
        return 1

    result = design_primers(scene)
    with open(args.out, "w", encoding="utf-8") as fh:
        json.dump(result, fh, indent=1)
    return 0


if __name__ == "__main__":
    sys.exit(main())