#!/bin/bash
# Oracle for coral-dial: write the deliverable module /app/tp_linear.py, then
# RUN the validation CLI on the visible config to produce
# /app/validate.json, and sanity import it. Never reads /tests.
set -eu

MOD="/app/tp_linear.py"
OUT="/app/validate.json"

cat > "$MOD" <<'PY'
"""ColumnParallelLinear: tensor-parallel linear layer (coral-dial)."""
import argparse
import json

import numpy as np
import torch


class ColumnParallelLinear(torch.nn.Module):
    """Linear layer whose output dimension is sharded across virtual ranks."""

    def __init__(self, in_features: int, out_features: int, world_size: int,
                 bias: bool = True):
        super().__init__()
        if out_features % world_size != 0:
            raise ValueError(
                "out_features (%d) must be divisible by world_size (%d)"
                % (out_features, world_size))
        self.in_features = in_features
        self.out_features = out_features
        self.world_size = world_size
        self.shard = out_features // world_size
        self.weight = torch.nn.Parameter(
            torch.empty(out_features, in_features))
        torch.nn.init.normal_(self.weight, std=0.02)
        if bias:
            self.bias = torch.nn.Parameter(torch.zeros(out_features))
        else:
            self.register_parameter("bias", None)

    def shard_size(self) -> int:
        return self.shard

    def weight_shard(self, rank: int) -> torch.Tensor:
        lo = rank * self.shard
        return self.weight[lo:lo + self.shard, :]

    def bias_shard(self, rank: int) -> torch.Tensor:
        if self.bias is None:
            raise RuntimeError("layer has no bias")
        lo = rank * self.shard
        return self.bias[lo:lo + self.shard]

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        locals_ = []
        for r in range(self.world_size):
            w_r = self.weight_shard(r)
            local = x @ w_r.t()
            if self.bias is not None:
                local = local + self.bias_shard(r)
            locals_.append(local)
        return torch.cat(locals_, dim=-1)  # all-gather along output dim

    def sharded_grad_weight(self, x: torch.Tensor, grad_output: torch.Tensor,
                            rank: int) -> torch.Tensor:
        dense = grad_output.t() @ x
        lo = rank * self.shard
        return dense[lo:lo + self.shard, :]

    def sharded_grad_bias(self, grad_output: torch.Tensor,
                          rank: int) -> torch.Tensor:
        if self.bias is None:
            raise RuntimeError("layer has no bias")
        dense = grad_output.sum(dim=0)
        lo = rank * self.shard
        return dense[lo:lo + self.shard]


def _validate(cfg, out_path, input_path=None) -> int:
    in_f = int(cfg["in_features"])
    out_f = int(cfg["out_features"])
    world = int(cfg["world_size"])
    seed = int(cfg["seed"])
    batch = int(cfg["batch"])

    if out_f % world != 0:
        report = {"ok": False, "reason": "nondivisible_output",
                  "out_features": out_f, "world_size": world}
        with open(out_path, "w") as fh:
            json.dump(report, fh, indent=2)
        return 0

    torch.manual_seed(seed)
    layer = ColumnParallelLinear(in_f, out_f, world)
    if input_path:
        x = torch.from_numpy(np.asarray(np.load(input_path), dtype=np.float32))
    else:
        torch.manual_seed(seed + 1)
        x = torch.randn(batch, in_f)
    torch.manual_seed(seed + 2)
    g = torch.randn(batch, out_f)

    y = layer(x)
    y_ref = torch.nn.functional.linear(x, layer.weight, layer.bias)
    fwd_diff = float((y - y_ref).abs().max())

    dense_gw = g.t() @ x
    sharded_gw = torch.cat(
        [layer.sharded_grad_weight(x, g, r) for r in range(world)], dim=0)
    gw_diff = float((sharded_gw - dense_gw).abs().max())

    dense_gb = g.sum(dim=0)
    sharded_gb = torch.cat(
        [layer.sharded_grad_bias(g, r) for r in range(world)], dim=0)
    gb_diff = float((sharded_gb - dense_gb).abs().max())

    report = {
        "ok": True,
        "world_size": world,
        "in_features": in_f,
        "out_features": out_f,
        "seed": seed,
        "batch": batch,
        "forward_max_abs_diff": fwd_diff,
        "grad_weight_max_abs_diff": gw_diff,
        "grad_bias_max_abs_diff": gb_diff,
        "y_col": [round(float(v), 6) for v in y.detach().reshape(-1)],
    }
    with open(out_path, "w") as fh:
        json.dump(report, fh, indent=2)
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--config")
    ap.add_argument("--validate", action="store_true")
    ap.add_argument("--in-features", type=int)
    ap.add_argument("--out-features", type=int)
    ap.add_argument("--world-size", type=int)
    ap.add_argument("--seed", type=int)
    ap.add_argument("--batch", type=int)
    ap.add_argument("--input")
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    if args.validate:
        if None in (args.in_features, args.out_features, args.world_size,
                    args.seed, args.batch):
            ap.error("--validate requires all geometry flags")
        cfg = {"in_features": args.in_features,
               "out_features": args.out_features,
               "world_size": args.world_size,
               "seed": args.seed, "batch": args.batch}
    else:
        if not args.config:
            ap.error("either --config or --validate is required")
        with open(args.config) as fh:
            cfg = json.load(fh)
    return _validate(cfg, args.out, args.input)


if __name__ == "__main__":
    raise SystemExit(main())
PY

chmod +x "$MOD"

# Sanity import, then produce the visible deliverable by executing the CLI.
python3 -c "import importlib.util; s=importlib.util.spec_from_file_location('tp_linear','/app/tp_linear.py'); m=importlib.util.module_from_spec(s); s.loader.exec_module(m); assert hasattr(m,'ColumnParallelLinear')"
python3 "$MOD" --config /app/config.json --out "$OUT"

echo "solve.sh done -> $MOD and $OUT"
ls -l "$MOD" "$OUT"
