#!/bin/bash
# Oracle for kestrel-bay: write the generic distributed fit program, then RUN
# it on the visible dataset with 4 workers. Never reads /tests.
set -eu

PROG="/app/dtrain.py"

cat > "$PROG" <<'PY'
#!/usr/bin/env python3
"""Kestrel Bay distributed least-squares fit over a gloo process group.

Spawns N workers; row i of the CSV belongs to rank i % N. Each rank
all-reduces its local sufficient statistics; rank 0 writes fit.json and
every rank writes its own marker file.
"""
import argparse
import csv
import json
import os
import tempfile

import torch
import torch.distributed as dist
import torch.multiprocessing as mp


def load_rows(csv_path):
    rows = []
    with open(csv_path, newline="", encoding="utf-8") as fh:
        for row in csv.DictReader(fh):
            rows.append((float(row["x"]), float(row["y"])))
    return rows


def worker(rank, world_size, csv_path, outdir, rdzv_file):
    dist.init_process_group(
        backend="gloo",
        init_method="file://" + rdzv_file,
        rank=rank,
        world_size=world_size,
    )
    try:
        rows = load_rows(csv_path)
        shard = [(x, y) for i, (x, y) in enumerate(rows) if i % world_size == rank]

        # explicit device/dtype movement: float64 python floats -> float32 CPU
        device = torch.device("cpu")
        if shard:
            xs = torch.tensor([p[0] for p in shard], dtype=torch.float32, device=device)
            ys = torch.tensor([p[1] for p in shard], dtype=torch.float32, device=device)
            local = torch.stack([
                torch.tensor(float(len(shard)), dtype=torch.float32, device=device),
                xs.sum(),
                ys.sum(),
                (xs * xs).sum(),
                (xs * ys).sum(),
            ])
        else:
            local = torch.zeros(5, dtype=torch.float32, device=device)

        dist.all_reduce(local, op=dist.ReduceOp.SUM)
        n, sx, sy, sxx, sxy = (float(v) for v in local)

        marker = {
            "rank": rank,
            "world_size": world_size,
            "backend": dist.get_backend(),
            "local_n": len(shard),
        }
        with open(os.path.join(outdir, "rank%d.marker" % rank), "w",
                  encoding="utf-8") as fh:
            json.dump(marker, fh)

        if rank == 0:
            slope = (n * sxy - sx * sy) / (n * sxx - sx * sx)
            intercept = (sy - slope * sx) / n
            fit = {
                "slope": slope,
                "intercept": intercept,
                "n": int(n),
                "world_size": world_size,
                "backend": dist.get_backend(),
            }
            with open(os.path.join(outdir, "fit.json"), "w",
                      encoding="utf-8") as fh:
                json.dump(fit, fh, indent=2)
    finally:
        dist.destroy_process_group()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--procs", type=int, required=True)
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)
    fd, rdzv = tempfile.mkstemp(prefix="kestrel_rdzv_", suffix=".file")
    os.close(fd)
    os.unlink(rdzv)  # file store must not pre-exist
    try:
        mp.spawn(
            worker,
            args=(args.procs, args.data, args.out, rdzv),
            nprocs=args.procs,
            join=True,
        )
    finally:
        if os.path.exists(rdzv):
            os.unlink(rdzv)


if __name__ == "__main__":
    main()
PY
chmod +x "$PROG"

python3 "$PROG" --data /app/data/tide_gauge.csv --out /app/output --procs 4

echo "solve.sh done -> $PROG and /app/output/fit.json"
ls -l "$PROG" /app/output/
cat /app/output/fit.json
