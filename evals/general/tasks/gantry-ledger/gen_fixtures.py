#!/usr/bin/env python3
"""Authoring-time generator for the gantry-ledger fixtures.

Regenerates the visible record set, the two shipped prompt versions, and the
three hidden record sets from the simulated-extractor core in
environment/files/_lib.py, then VALIDATES that the shipped prompts produce
exactly the documented baseline metrics on every set before writing anything.

Usage (from the task directory):
  python3 gen_fixtures.py            # regenerate + validate everything
  python3 gen_fixtures.py --check    # validate only (no writes)

This script is a task-authoring tool; it is not mounted into trial containers.
"""
import argparse
import json
import random
import re
import sys
from pathlib import Path

TASK = Path(__file__).resolve().parent
LIB = TASK / "environment" / "files" / "_lib.py"
sys.path.insert(0, str(LIB.parent))
import _lib  # noqa: E402  (the same module that is marshalled into the image)

N = 200
REF_CLEAN = 120      # ref verbatim
REF_COSMETIC = 74    # lowercase + inserted separators; canonical repair fixes
REF_DESTRUCTIVE = 6  # char dropped + adjacent swap; unrecoverable
CAR_EXPLICIT = 120   # Carrier line names the carrier
CAR_RESOLVED = 42    # no Carrier line; frag is the gold carrier's code
CAR_TRAP = 18        # no Carrier line; frag is another carrier's code
CAR_UNKNOWN = 20     # no Carrier line; frag is not a code; gold is UNKNOWN

NON_CODES = ["QZ", "RX", "WJ", "PK", "YH", "VU", "ZL", "TF", "NG",
             "BQ", "OV", "MC", "PT", "LR", "KS", "FM"]

V1_TEMPLATE = """# Prompt v1 - extract
Extract the shipment record fields into JSON with keys date, amount, ref,
carrier. Write each value exactly as it appears in the record text.
"""

V2_TEMPLATE = """# Prompt v2 - canonical + completion

You are a shipment record extractor. From the record text produce JSON with
exactly the keys date, amount, ref, carrier.

Normalize every value to canonical form: dates as ISO-8601 (YYYY-MM-DD), refs
as uppercase alphanumeric strings with all separators removed, amounts as
numbers with two decimal places.

When the Carrier line is missing, complete the carrier from the forwarding
code using the appendix: treat the appendix as authoritative; if the code is
not listed, use your best judgment.

Appendix: forwarding code -> carrier
{rows}
"""


def v2_prompt():
    rows = "\n".join("  %s -> %s" % (c, n) for c, n in _lib.CARRIERS)
    return V2_TEMPLATE.format(rows=rows)


def gen_ref_raw(rng, kind, gold_ref):
    """Text form of a ref for the given kind (gold_ref is the canonical form)."""
    if kind == "clean":
        return gold_ref
    if kind == "cosmetic":
        raw = gold_ref.lower()
        parts, pos = [], 0
        for idx in range(1, len(raw)):
            if rng.random() < 0.5:
                parts.append(raw[pos:idx] + rng.choice(["-", ".", " "]))
                pos = idx
        parts.append(raw[pos:])
        return "".join(parts)
    raw = gen_ref_raw(rng, "cosmetic", gold_ref)
    # drop one alphanumeric character (a dropped separator would repair away);
    # the 8-character lowercase stream can never repair back to the 9-char gold
    chars = list(re.sub(r"[^a-z0-9]", "", raw))
    del chars[rng.randrange(len(chars))]
    return "".join(chars)


def gen_ref(rng):
    letters = "ABCDEFGHJKLMNPQRSTUVWXYZ"
    return ("".join(rng.choice(letters) for _ in range(2))
            + "".join(rng.choice("0123456789") for _ in range(5))
            + "".join(rng.choice(letters) for _ in range(2)))


def gen_record(rng, tag, i, ref_kind, car_kind):
    gold_ref = gen_ref(rng)
    awbn = gen_ref_raw(rng, ref_kind, gold_ref)
    gold_iso = "%d-%02d-%02d" % (rng.randrange(2020, 2026),
                                 rng.randrange(1, 13), rng.randrange(1, 29))
    if rng.random() < 0.5:
        m, d = int(gold_iso[5:7]), int(gold_iso[8:10])
        date = "%d/%02d/%s" % (m, d, gold_iso[0:4])
    else:
        date = gold_iso
    dollars = rng.randrange(10, 9999)
    cents = rng.randrange(100)
    amount = "USD %s,%03d.%02d" % (dollars // 1000, dollars % 1000, cents)
    gold_amount = "%d.%02d" % (dollars, cents)

    if car_kind == "explicit":
        car_name = rng.choice([n for _, n in _lib.CARRIERS])
        carrier_gold = car_name
        car_line = "Carrier: %s" % car_name
    elif car_kind in ("resolved", "trap"):
        codes = [c for c, _ in _lib.CARRIERS]
        names = [n for _, n in _lib.CARRIERS]
        i1 = rng.randrange(len(codes))
        carrier_gold = names[i1]
        if car_kind == "trap":
            i2 = rng.randrange(len(codes) - 1)
            i2 = i2 + 1 if i2 >= i1 else i2
        else:
            i2 = i1
        car_line = "Fwd code: %s" % codes[i2]
    else:
        carrier_gold = _lib.UNKNOWN
        car_line = "Fwd code: %s" % rng.choice(NON_CODES)
    text = "\n".join(["SHIPMENT ID %s-%04d" % (tag, i + 1),
                      "AWBN: %s" % awbn,
                      "Date: %s" % date,
                      "Amount: %s" % amount,
                      car_line])
    return {"id": "SHIPMENT-%04d" % (i + 1),
            "text": text,
            "gold": {"ref": gold_ref, "date": gold_iso,
                     "amount": gold_amount, "carrier": carrier_gold}}


def gen_records(seed, tag):
    rng = random.Random(seed)
    ref_kinds = (["clean"] * REF_CLEAN + ["cosmetic"] * REF_COSMETIC +
                 ["destructive"] * REF_DESTRUCTIVE)
    rng.shuffle(ref_kinds)
    car_pool = (["explicit"] * CAR_EXPLICIT + ["resolved"] * CAR_RESOLVED +
                ["trap"] * CAR_TRAP + ["unknown"] * CAR_UNKNOWN)
    rng.shuffle(car_pool)
    return [gen_record(rng, tag, i, ref_kinds[i], car_pool[i])
            for i in range(N)]


def metrics(prompt, recs):
    good_ref = fab = 0
    for r in recs:
        out = _lib.extract(prompt, r["text"])
        if out.get("ref") == r["gold"]["ref"]:
            good_ref += 1
        c = out.get("carrier")
        if c != _lib.UNKNOWN and c != r["gold"]["carrier"]:
            fab += 1
    return good_ref / len(recs), fab / len(recs)


def check(prompt, recs, exp_ref, exp_fab, label):
    refa, fab = metrics(prompt, recs)
    ok = abs(refa - exp_ref) < 1e-9 and abs(fab - exp_fab) < 1e-9
    print("  [%s] ref_acc=%.4f fab=%.4f (want %.4f/%.4f) %s" %
          (label, refa, fab, exp_ref, exp_fab, "OK" if ok else "MISMATCH"))
    return ok


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()

    data_dir = TASK / "environment" / "files" / "data"
    prompt_dir = TASK / "environment" / "files" / "prompts"
    hidden_dir = TASK / "tests" / "hidden"

    v1 = V1_TEMPLATE
    v2 = v2_prompt()

    if not args.check:
        prompt_dir.mkdir(parents=True, exist_ok=True)
        (prompt_dir / "v1.txt").write_text(v1)
        (prompt_dir / "v2.txt").write_text(v2)
        sets = [("visible", 1017, data_dir / "records.jsonl", "V"),
                ("case-1", 2017, hidden_dir / "case-1" / "records.jsonl", "H1"),
                ("case-2", 3017, hidden_dir / "case-2" / "records.jsonl", "H2"),
                ("case-3", 4017, hidden_dir / "case-3" / "records.jsonl", "H3")]
        for name, seed, out, tag in sets:
            recs = gen_records(seed, tag)
            out.parent.mkdir(parents=True, exist_ok=True)
            with open(out, "w") as fh:
                for r in recs:
                    fh.write(json.dumps(r) + "\n")
            print("wrote %s: %d records -> %s" % (name, len(recs), out))

    # ---- validate every generated set against the shipped prompts ----
    print("baseline expectation: v1 ref 0.600 fab 0.000 | v2 ref 0.970 fab 0.190")
    allok = True
    v1 = prompt_dir / "v1.txt"
    v2f = prompt_dir / "v2.txt"
    v3f = TASK / "solution" / "v3.txt"
    sets = [("V", data_dir / "records.jsonl"),
            ("H1", hidden_dir / "case-1" / "records.jsonl"),
            ("H2", hidden_dir / "case-2" / "records.jsonl"),
            ("H3", hidden_dir / "case-3" / "records.jsonl")]
    if v1.exists() and v2f.exists():
        for name, path in sets:
            if not path.exists():
                print("  missing %s" % path)
                allok = False
                continue
            recs = [json.loads(l) for l in open(path) if l.strip()]
            print("set %s (%d records)" % (name, len(recs)))
            allok &= check(v1.read_text(), recs, 0.60, 0.00, "v1")
            allok &= check(v2f.read_text(), recs, 0.97, 0.19, "v2")
            if v3f.exists():
                allok &= check(v3f.read_text(), recs, 0.97, 0.00, "v3")
            else:
                print("  (solution/v3.txt not present; v3 skipped)")
        pars = _lib.parse_appendix(v2f.read_text())
        okp = pars == dict(_lib.CARRIERS)
        print("appendix parse from v2 text: %d rows, exact match=%s"
              % (len(pars), okp))
        okn = bool(_lib._NORM_RE.search(v2f.read_text())) \
            and not bool(_lib._NORM_RE.search(v1.read_text()))
        okg = _lib._guess_on(v2f.read_text()) \
            and not _lib._guess_on(v1.read_text())
        print("norm trait: v2 only=%s ; guess trait: v2 only=%s" % (okn, okg))
        allok &= okp and okn and okg
    else:
        print("prompts not generated yet; run without --check first")
        allok = False

    print("VALIDATION %s" % ("PASS" if allok else "FAIL"))
    return 0 if allok else 1


if __name__ == "__main__":
    sys.exit(main())