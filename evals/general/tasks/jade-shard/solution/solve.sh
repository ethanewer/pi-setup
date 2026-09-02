#!/bin/bash
# Oracle for the jade-shard task.
#
# REAL solution: it authors the /app/reshard.py tool (shard + join modes) and
# then RUNS it on /app/tensor.json to actually build the three shards, the
# manifest and the reconstructed tensor. It never reads /tests and never emits
# a precomputed answer.
set -eu

cat > /app/reshard.py <<'PYEOF'
#!/usr/bin/env python3
"""Reshard a row-major tensor record into exactly three contiguous shards.

shard:
    python3 reshard.py shard --input <tensor.json> --outdir <dir>
    Reads {"shape": [...], "values": [...]}, splits the values into exactly
    three contiguous, as-even-as-possible shards, writes <dir>/shard-0.json,
    shard-1.json, shard-2.json and <dir>/manifest.json.

join:
    python3 reshard.py join --manifest <dir>/manifest.json --outdir <dir>
    Reassembles the three shards, verifies contiguity, element count, shape and
    the payload checksum, then writes <dir>/reconstructed.json.

The checksum is the lowercase hex SHA-256 of the compact JSON of the values
array: hashlib.sha256(json.dumps(values, separators=(",", ":")).encode()).
"""
import argparse
import hashlib
import json
import os
import sys


def checksum(values):
    compact = json.dumps(values, separators=(",", ":"))
    return hashlib.sha256(compact.encode("utf-8")).hexdigest()


def load_tensor(path):
    with open(path) as f:
        obj = json.load(f)
    if not isinstance(obj, dict):
        raise ValueError("tensor must be a JSON object")
    if "shape" not in obj or "values" not in obj:
        raise ValueError("tensor must contain both 'shape' and 'values'")
    shape = obj["shape"]
    values = obj["values"]
    if not isinstance(shape, list) or not shape:
        raise ValueError("'shape' must be a non-empty list of integers")
    if any(not isinstance(d, int) or isinstance(d, bool) or d < 0 for d in shape):
        raise ValueError("'shape' dimensions must be non-negative integers")
    element_count = 1
    for d in shape:
        element_count *= d
    if not isinstance(values, list):
        raise ValueError("'values' must be a list")
    if any(not isinstance(v, int) or isinstance(v, bool) for v in values):
        raise ValueError("'values' must contain only integers")
    if len(values) != element_count:
        raise ValueError(
            "value count %d does not match shape element_count %d"
            % (len(values), element_count))
    return shape, values, element_count


def split_sizes(n):
    base, rem = divmod(n, 3)
    counts = [base + (1 if i < rem else 0) for i in range(3)]
    offsets = []
    acc = 0
    for c in counts:
        offsets.append(acc)
        acc += c
    return offsets, counts


def cmd_shard(args):
    shape, values, n = load_tensor(args.input)
    offsets, counts = split_sizes(n)
    os.makedirs(args.outdir, exist_ok=True)
    shards = []
    for i in range(3):
        lo = offsets[i]
        hi = lo + counts[i]
        payload = values[lo:hi]
        shard = {"shard_index": i, "offset": lo, "count": counts[i],
                 "values": payload}
        with open(os.path.join(args.outdir, "shard-%d.json" % i), "w") as f:
            json.dump(shard, f)
        shards.append({"index": i, "offset": lo, "count": counts[i]})
    manifest = {
        "shape": shape,
        "element_count": n,
        "num_shards": 3,
        "checksum": checksum(values),
        "shards": shards,
    }
    with open(os.path.join(args.outdir, "manifest.json"), "w") as f:
        json.dump(manifest, f)
    print("sharded %d values into 3 contiguous shards (%s)"
          % (n, ",".join(str(c) for c in counts)))


def cmd_join(args):
    with open(args.manifest) as f:
        man = json.load(f)
    if not isinstance(man, dict):
        raise ValueError("manifest must be a JSON object")
    if man.get("num_shards") != 3:
        raise ValueError("manifest must declare exactly 3 shards")
    shape = man.get("shape")
    element_count = man.get("element_count")
    if not isinstance(shape, list) or not shape:
        raise ValueError("manifest 'shape' is missing or invalid")
    es = 1
    for d in shape:
        es *= d
    if es != element_count:
        raise ValueError("manifest shape is inconsistent with element_count")

    infra = man.get("shards")
    if not isinstance(infra, list) or len(infra) != 3:
        raise ValueError("manifest 'shards' is invalid")

    outdir = os.path.dirname(args.manifest)
    parts = []
    for spec in infra:
        idx = spec.get("index")
        cnt = spec.get("count")
        off = spec.get("offset")
        with open(os.path.join(outdir, "shard-%d.json" % idx)) as f:
            sh = json.load(f)
        if sh.get("shard_index") != idx:
            raise ValueError("shard %d index mismatch" % idx)
        if sh.get("count") != cnt or sh.get("offset") != off:
            raise ValueError("shard %d disagrees with manifest" % idx)
        parts.append((off, sh["values"], cnt))

    parts.sort(key=lambda t: t[0])
    assembled = []
    expected = 0
    for offset, vals, count in parts:
        if offset != expected or count < 0 or len(vals) != count:
            raise ValueError("shards are not contiguous/consistent")
        if count > 0:
            assembled.extend(vals)
        expected += count
    if expected != element_count:
        raise ValueError("shards do not cover the declared element_count")
    if len(assembled) != element_count:
        raise ValueError("reassembled length != element_count")
    if checksum(assembled) != man.get("checksum"):
        raise ValueError("checksum mismatch after reassembly")

    reconstructed = {"shape": shape, "values": assembled}
    with open(os.path.join(outdir, "reconstructed.json"), "w") as f:
        json.dump(reconstructed, f)
    print("joined %d values; checksum verified" % element_count)


def main(argv):
    ap = argparse.ArgumentParser(prog="reshard.py")
    sub = ap.add_subparsers(dest="command", required=True)

    p_shard = sub.add_parser("shard")
    p_shard.add_argument("--input", required=True)
    p_shard.add_argument("--outdir", required=True)

    p_join = sub.add_parser("join")
    p_join.add_argument("--manifest", required=True)
    p_join.add_argument("--outdir", required=True)

    args = ap.parse_args(argv)
    try:
        if args.command == "shard":
            cmd_shard(args)
        else:
            cmd_join(args)
    except (ValueError, OSError, KeyError, IndexError, TypeError) as exc:
        print("reshard error: %s" % exc, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
PYEOF
chmod +x /app/reshard.py

# Produce the visible artifacts by actually RUNNING the tool.
python3 /app/reshard.py shard --input /app/tensor.json --outdir /app
python3 /app/reshard.py join --manifest /app/manifest.json --outdir /app

echo "Oracle completed: /app/reshard.py + shards + manifest + reconstructed.json"