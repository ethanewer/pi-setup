#!/bin/bash
# Verifier for coral-dial: imports the deliverable /app/tp_linear.py, checks
# the ColumnParallelLinear contract directly (named params, shard slicing,
# forward equality to the dense layer, sharded gradient reconstruction) on the
# visible config and every hidden configuration, and EXECUTES the validation
# CLI per case (checking the report JSON, including the nondivisible case and
# the --input no-reseed rule). Writes 0/1 to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
python3 - <<'PYEOF' >&2
import importlib.util, json, os, subprocess, sys
import numpy as np
import torch
import torch.nn.functional as F

MOD = "/app/tp_linear.py"
TOL = 1e-5
failures = []


def log(*a):
    print("[verifier]", *a)


def load_mod():
    if not os.path.isfile(MOD):
        return None
    try:
        spec = importlib.util.spec_from_file_location("tp_linear", MOD)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return mod
    except Exception as e:
        log("import failed:", repr(e))
        return None


def check_layer_objectively(cls):
    """Direct contract checks independent of the CLI."""
    try:
        torch.manual_seed(123)
        layer = cls(20, 30, 5)
    except Exception as e:
        failures.append("constructor(20,30,5) failed: %r" % e)
        return
    if layer.weight.shape != (30, 20):
        failures.append("weight shape %r" % (tuple(layer.weight.shape),))
        return
    w_std = float(layer.weight.detach().std())
    if w_std < 1e-4 or w_std > 0.2:
        failures.append("weight init std looks wrong (%.4f, want ~0.02)" % w_std)
    if not torch.allclose(layer.bias.detach(), torch.zeros(30)):
        failures.append("bias not zero-initialized")
    try:
        if layer.shard_size() != 6:
            failures.append("shard_size() != 6")
        w0 = layer.weight_shard(0)
        if w0.shape != (6, 20):
            failures.append("weight_shard(0) shape %r" % (tuple(w0.shape),))
        elif not torch.equal(w0, layer.weight[0:6, :]):
            failures.append("weight_shard(0) is not the row block")
    except Exception as e:
        failures.append("shard accessors failed: %r" % e)
    # forward equality on a fixed input
    torch.manual_seed(7)
    x = torch.randn(4, 20)
    y = layer(x)
    y_ref = F.linear(x, layer.weight, layer.bias)
    if float((y - y_ref).abs().max()) > TOL:
        failures.append("forward != dense linear (%.3g)"
                        % float((y - y_ref).abs().max()))
    # gradients
    g = torch.randn(4, 30)
    dense_gw = g.t() @ x
    sharded = torch.cat([layer.sharded_grad_weight(x, g, r) for r in range(5)],
                        dim=0)
    if sharded.shape != (30, 20):
        failures.append("sharded grad weight shape %r"
                        % (tuple(sharded.shape),))
    elif float((sharded - dense_gw).abs().max()) > TOL:
        failures.append("sharded grad weight != dense grad")
    sharded_b = torch.cat([layer.sharded_grad_bias(g, r) for r in range(5)],
                          dim=0)
    if float((sharded_b - g.sum(dim=0)).abs().max()) > TOL:
        failures.append("sharded grad bias != dense grad")
    # differentiability through the sharded forward
    try:
        xg = x.clone().requires_grad_(True)
        layer(xg).sum().backward()
        if xg.grad is None or xg.grad.shape != x.shape:
            failures.append("sharded forward not differentiable w.r.t. input")
    except Exception as e:
        failures.append("backward through sharded forward failed: %r" % e)
    # divisible guard
    try:
        cls(20, 31, 5)
        failures.append("nondivisible out_features did not raise ValueError")
    except ValueError:
        pass
    except Exception as e:
        failures.append("nondivisible out_features raised %r" % e)
    # bias=False
    try:
        layer_nb = cls(20, 30, 5, bias=False)
        try:
            layer_nb.sharded_grad_bias(torch.randn(4, 30), 0)
            failures.append("bias=False sharded_grad_bias did not raise")
        except RuntimeError:
            pass
    except Exception as e:
        failures.append("bias=False construction failed: %r" % e)


def run_cli(args, out_path):
    if os.path.exists(out_path):
        os.remove(out_path)
    r = subprocess.run([sys.executable, MOD] + args + ["--out", out_path],
                       capture_output=True, text=True, timeout=180)
    if r.returncode != 0 or not os.path.exists(out_path):
        log("CLI failed:", r.stderr[-400:])
        return None
    try:
        with open(out_path) as fh:
            return json.load(fh)
    except Exception as e:
        log("unreadable report: %r" % e)
        return None


def reference_report(cfg, input_path=None):
    """Spec-faithful reference recomputation."""
    in_f, out_f = int(cfg["in_features"]), int(cfg["out_features"])
    world, seed, batch = int(cfg["world_size"]), int(cfg["seed"]), int(cfg["batch"])
    if out_f % world != 0:
        return {"ok": False, "reason": "nondivisible_output",
                "out_features": out_f, "world_size": world}
    torch.manual_seed(seed)
    weight = torch.empty(out_f, in_f)
    torch.nn.init.normal_(weight, std=0.02)
    bias = torch.zeros(out_f)
    if input_path:
        x = torch.from_numpy(np.asarray(np.load(input_path), dtype=np.float32))
    else:
        torch.manual_seed(seed + 1)
        x = torch.randn(batch, in_f)
    torch.manual_seed(seed + 2)
    g = torch.randn(batch, out_f)
    shard = out_f // world
    y = torch.cat([x @ weight[r * shard:(r + 1) * shard, :].t()
                   + bias[r * shard:(r + 1) * shard] for r in range(world)],
                  dim=-1)
    y_ref = F.linear(x, weight, bias)
    dense_gw = g.t() @ x
    dense_gb = g.sum(dim=0)
    return {
        "ok": True, "world_size": world, "in_features": in_f,
        "out_features": out_f, "seed": seed, "batch": batch,
        "forward_max_abs_diff": float((y - y_ref).abs().max()),
        "grad_weight_max_abs_diff": float(
            (torch.cat([dense_gw[r * shard:(r + 1) * shard, :]
                        for r in range(world)], dim=0) - dense_gw).abs().max()),
        "grad_bias_max_abs_diff": float(
            (torch.cat([dense_gb[r * shard:(r + 1) * shard]
                        for r in range(world)], dim=0) - dense_gb).abs().max()),
        "y_col": [round(float(v), 6) for v in y.reshape(-1)],
    }


def report_close(got, want):
    if not isinstance(got, dict):
        return False
    if want.get("ok") is False:
        return (got.get("ok") is False
                and got.get("reason") == want.get("reason"))
    keys = {"ok", "world_size", "in_features", "out_features", "seed",
            "batch", "forward_max_abs_diff", "grad_weight_max_abs_diff",
            "grad_bias_max_abs_diff", "y_col"}
    if set(got.keys()) != keys or got.get("ok") is not True:
        return False
    for k in ("world_size", "in_features", "out_features", "seed", "batch"):
        if got.get(k) != want.get(k):
            return False
    for k in ("forward_max_abs_diff", "grad_weight_max_abs_diff",
              "grad_bias_max_abs_diff"):
        v = got.get(k)
        if not isinstance(v, (int, float)) or v != v or v > TOL:
            return False
    y = got.get("y_col")
    if not isinstance(y, list) or len(y) != len(want["y_col"]):
        return False
    try:
        for a, b in zip(y, want["y_col"]):
            if abs(float(a) - float(b)) > 2e-5:
                return False
    except (TypeError, ValueError):
        return False
    return True


mod = load_mod()
if mod is None:
    failures.append("cannot import /app/tp_linear.py")
else:
    cls = getattr(mod, "ColumnParallelLinear", None)
    if cls is None:
        failures.append("no ColumnParallelLinear class")
    elif not issubclass(cls, torch.nn.Module):
        failures.append("ColumnParallelLinear is not an nn.Module")
    else:
        check_layer_objectively(cls)

    # visible case: run CLI on the shipped config and check artifact
    with open("/app/config.json") as fh:
        vcfg = json.load(fh)
    got = run_cli(["--config", "/app/config.json"], "/tmp/cd_visible_out.json")
    want = reference_report(vcfg)
    if got is None or not report_close(got, want):
        failures.append("visible CLI report mismatch or missing")
    if os.path.isfile("/app/validate.json"):
        try:
            with open("/app/validate.json") as fh:
                art = json.load(fh)
            if not report_close(art, want):
                failures.append("/app/validate.json mismatch")
        except Exception as e:
            failures.append("validate.json unreadable: %r" % e)
    else:
        failures.append("missing /app/validate.json")

    # hidden cases
    hidden = "/tests/hidden"
    cases = sorted(os.listdir(hidden)) if os.path.isdir(hidden) else []
    if not cases:
        failures.append("no hidden cases present")
    for name in cases:
        base = os.path.join(hidden, name)
        cpath = os.path.join(base, "config.json")
        epath = os.path.join(base, "expect.json")
        if not (os.path.isfile(cpath) and os.path.isfile(epath)):
            failures.append("hidden '%s': missing config/expect" % name)
            continue
        try:
            with open(cpath) as fh:
                cfg = json.load(fh)
            with open(epath) as fh:
                exp = json.load(fh)
        except Exception as e:
            failures.append("hidden '%s': unreadable case files (%r)"
                            % (name, e))
            continue
        try:
            input_rel = cfg.get("input")
            input_abs = os.path.join(base, input_rel) if input_rel else None
            args = ["--config", cpath]
            if input_abs:
                args += ["--input", input_abs]
            got = run_cli(args, "/tmp/cd_hidden_out.json")
            if got is None:
                failures.append("hidden '%s': CLI produced no report" % name)
                continue
            want = reference_report(cfg, input_abs)
            if not report_close(got, want):
                failures.append("hidden '%s': report mismatch vs reference"
                                % name)
                continue
            if exp.get("ok") is False:
                if got.get("ok") is not False or \
                        got.get("reason") != exp.get("reason"):
                    failures.append("hidden '%s': expected ok:false/%s"
                                    % (name, exp.get("reason")))
            elif got.get("ok") is not True:
                failures.append("hidden '%s': expected ok:true" % name)
        except Exception as e:
            failures.append("hidden '%s': verifier harness error %r"
                            % (name, e))

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PYEOF
rc=$?
if [ $rc -eq 0 ]; then reward=1; else reward=0; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
