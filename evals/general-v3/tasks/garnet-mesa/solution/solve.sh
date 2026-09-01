#!/bin/bash
# Oracle for garnet-mesa: write the allocate.py program, then RUN it on the
# visible fixtures to produce /app/allocation.json. Never reads /tests.
set -eu

SOLVER="/app/allocate.py"
OUT="/app/allocation.json"

cat > "$SOLVER" <<'PY'
#!/usr/bin/env python3
"""Garnet Mesa cultivar ledger sweep.

python3 allocate.py <input_dir> <output_json>
"""
import base64
import json
import pickle
import sys

SOURCE_FILES = [
    ("stores.pkl", "stores.pkl"),
    ("trellis.b64", "trellis.b64"),
    ("almanac.txt", "almanac.txt"),
]


def usable(c):
    return (
        isinstance(c, dict)
        and isinstance(c.get("water"), str)
        and isinstance(c.get("shade"), str)
    )


def load_pickle(path):
    with open(path, "rb") as fh:
        obj = pickle.load(fh)
    if not isinstance(obj, dict):
        return {}
    out = {}
    for k, v in obj.items():
        if isinstance(k, str) and usable(v):
            out[k.strip()] = v
    return out


def load_b64(path):
    with open(path, "r", encoding="utf-8") as fh:
        blob = "".join(line.strip() for line in fh if line.strip())
    payload = base64.b64decode(blob, validate=True)
    obj = json.loads(payload.decode("utf-8"))
    if not isinstance(obj, dict):
        return {}
    out = {}
    for k, v in obj.items():
        if isinstance(k, str) and usable(v):
            out[k.strip()] = v
    return out


def load_almanac(path):
    out = {}
    with open(path, "r", encoding="utf-8") as fh:
        for raw in fh:
            line = raw.strip()
            if not line:
                continue
            parts = line.split("|")
            if len(parts) != 3:
                continue
            cid, water, shade = (p.strip() for p in parts)
            if not cid:
                continue
            if cid not in out:
                out[cid] = {"water": water, "shade": shade}
    return out


LOADERS = {
    "stores.pkl": load_pickle,
    "trellis.b64": load_b64,
    "almanac.txt": load_almanac,
}


def load_roster(path):
    rows = []
    with open(path, "r", encoding="utf-8") as fh:
        lines = [ln.rstrip("\n") for ln in fh]
    data = [ln for ln in lines if ln.strip()]
    if not data:
        return rows
    for ln in data[1:]:  # skip header
        fields = ln.split("\t")
        if len(fields) != 4:
            continue
        cid, plot, family, sown = (f.strip() for f in fields)
        if not cid:
            continue
        rows.append(
            {"cultivar_id": cid, "plot": plot, "family": family, "sown": sown}
        )
    return rows


def main():
    input_dir, out_path = sys.argv[1], sys.argv[2]

    ledger = {}
    for fname, _label in SOURCE_FILES:
        path = "%s/ledger/%s" % (input_dir, fname)
        table = {}
        try:
            table = LOADERS[fname](path)
        except Exception:
            table = {}
        ledger[fname] = table

    allocations = []
    sources_used = set()
    unassigned = []
    for row in load_roster("%s/roster.tsv" % input_dir):
        cid = row["cultivar_id"]
        hit = None
        for fname, _label in SOURCE_FILES:
            cand = ledger[fname].get(cid)
            if cand is not None:
                hit = (fname, cand)
                break
        if hit is None:
            allocations.append(
                {
                    "cultivar_id": cid,
                    "plot": row["plot"],
                    "family": row["family"],
                    "sown": row["sown"],
                    "water": "none",
                    "shade": "none",
                    "source": "none",
                }
            )
            unassigned.append(cid)
        else:
            fname, cand = hit
            allocations.append(
                {
                    "cultivar_id": cid,
                    "plot": row["plot"],
                    "family": row["family"],
                    "sown": row["sown"],
                    "water": cand["water"],
                    "shade": cand["shade"],
                    "source": fname,
                }
            )
            sources_used.add(fname)

    report = {
        "allocations": allocations,
        "sources_used": sorted(sources_used),
        "unassigned": unassigned,
    }
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=2)
        fh.write("\n")


if __name__ == "__main__":
    main()
PY

chmod +x "$SOLVER"
python3 "$SOLVER" /app/data "$OUT"

echo "solve.sh done -> $SOLVER and $OUT"
ls -l "$SOLVER" "$OUT"
