#!/bin/bash
# Verifier for glass-mantle: imports the deliverable /app/setpool.py, checks
# the named layers and runs it on the visible fixture (via its CLI, producing
# /app/pooled.json) and on every hidden configuration under /tests/hidden,
# comparing against an independent in-container reference. Writes 0/1 to
# /logs/verifier/reward.txt. Guards every parse; never crashes on bad output.
set -u
mkdir -p /logs/verifier
python3 - <<'PYEOF' >&2
import importlib.util, json, os, subprocess, sys
import numpy as np
import torch

MOD = "/app/setpool.py"
TOL = 1e-4
failures = []


def log(*a):
    print("[verifier]", *a)


def load_mod():
    if not os.path.isfile(MOD):
        return None
    try:
        spec = importlib.util.spec_from_file_location("setpool", MOD)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return mod
    except Exception as e:
        log("import failed:", repr(e))
        return None


def reference(in_dim, attn_dim, out_dim, seed, x):
    """Independent spec-faithful reference (no agent code imported)."""
    torch.manual_seed(seed)
    proj = torch.nn.Linear(in_dim, attn_dim)
    score = torch.nn.Linear(attn_dim, 1)
    head = torch.nn.Linear(in_dim, out_dim)
    if x.dim() == 2:
        bag = x.shape[0]
        if bag == 0:
            w = torch.zeros(0, 1)
            pooled = head(torch.zeros(in_dim))
        else:
            logits = score(torch.tanh(proj(x)))
            w = torch.softmax(logits, dim=0)
            pooled = head((x * w).sum(dim=0))
        return {"pooled": [float(v) for v in pooled.reshape(-1)],
                "weights": [float(v) for v in w.reshape(-1)],
                "bag": int(bag)}
    # rank-3
    b, bag, _ = x.shape
    logits = score(torch.tanh(proj(x)))
    w = torch.softmax(logits, dim=1)
    pooled = head((x * w).sum(dim=1))
    return {"pooled": [float(v) for v in pooled.reshape(-1)],
            "weights": [float(v) for v in w.reshape(-1)],
            "bag": int(bag)}


def close(got, want):
    if not isinstance(got, dict):
        return False
    if set(got.keys()) != {"pooled", "weights", "bag"}:
        return False
    if got.get("bag") != want["bag"]:
        return False
    for key in ("pooled", "weights"):
        g = got.get(key)
        if not isinstance(g, list) or len(g) != len(want[key]):
            return False
        try:
            gv = [float(v) for v in g]
        except (TypeError, ValueError):
            return False
        for a, b in zip(gv, want[key]):
            if a != a or abs(a - b) > TOL:
                return False
    return True


def check_attrs(mod, cfg):
    cls = getattr(mod, "GatedSetPooling", None)
    if cls is None:
        failures.append("no GatedSetPooling class")
        return None
    if not issubclass(cls, torch.nn.Module):
        failures.append("GatedSetPooling is not an nn.Module")
        return None
    try:
        torch.manual_seed(cfg["seed"])
        obj = cls(cfg["in_dim"], cfg["attn_dim"], cfg["out_dim"])
    except Exception as e:
        failures.append("constructor failed: %r" % e)
        return None
    for attr in ("proj", "score", "head"):
        layer = getattr(obj, attr, None)
        if not isinstance(layer, torch.nn.Linear):
            failures.append("attr %r is not an nn.Linear" % attr)
        elif (layer.in_features, layer.out_features) != {
                "proj": (cfg["in_dim"], cfg["attn_dim"]),
                "score": (cfg["attn_dim"], 1),
                "head": (cfg["in_dim"], cfg["out_dim"])}[attr]:
            failures.append("attr %r has wrong shape" % attr)
    for meth in ("attention", "forward"):
        if not callable(getattr(obj, meth, None)):
            failures.append("missing method %r" % meth)
    return obj


def run_cli(cfg_path, npz_path, out_path):
    if os.path.exists(out_path):
        os.remove(out_path)
    r = subprocess.run(
        [sys.executable, MOD, "--config", cfg_path, "--clusters", npz_path,
         "--out", out_path],
        capture_output=True, text=True, timeout=180,
    )
    if r.returncode != 0 or not os.path.exists(out_path):
        log("CLI failed:", r.stderr[-400:])
        return None
    try:
        with open(out_path) as fh:
            return json.load(fh)
    except Exception as e:
        log("unreadable output: %r" % e)
        return None


mod = load_mod()
if mod is None:
    failures.append("cannot import /app/setpool.py")
else:
    # ---- visible fixture: check module attrs + run CLI + check artifact ----
    with open("/app/config.json") as fh:
        vcfg = json.load(fh)
    check_attrs(mod, vcfg)
    got = run_cli("/app/config.json", "/app/clusters.npz",
                  "/tmp/gm_visible_out.json")
    if got is None:
        failures.append("visible CLI run failed")
    else:
        with np.load("/app/clusters.npz") as data:
            X = torch.from_numpy(np.asarray(data["X"], dtype=np.float32))
        want = reference(vcfg["in_dim"], vcfg["attn_dim"], vcfg["out_dim"],
                         vcfg["seed"], X)
        if not close(got, want):
            failures.append("visible CLI output mismatch vs reference")
    if os.path.isfile("/app/pooled.json"):
        try:
            with open("/app/pooled.json") as fh:
                art = json.load(fh)
            if got is not None and not close(art, want):
                failures.append("/app/pooled.json mismatch vs reference")
        except Exception as e:
            failures.append("pooled.json unreadable: %r" % e)
    else:
        failures.append("missing /app/pooled.json")

    # ---- hidden cases ----
    hidden = "/tests/hidden"
    cases = sorted(os.listdir(hidden)) if os.path.isdir(hidden) else []
    if not cases:
        failures.append("no hidden cases present")
    for name in cases:
        ppath = os.path.join(hidden, name, "params.json")
        if not os.path.isfile(ppath):
            failures.append("hidden '%s': missing params.json" % name)
            continue
        try:
            with open(ppath) as fh:
                p = json.load(fh)
        except Exception as e:
            failures.append("hidden '%s': unreadable params (%r)" % (name, e))
            continue
        try:
            obj = check_attrs(mod, p)  # attr names/shapes under hidden dims
            if obj is None:
                continue
            seed, in_dim, out_dim = p["seed"], p["in_dim"], p["out_dim"]
            g = torch.Generator().manual_seed(seed)
            if p["mode"] == "batched":
                x = torch.randn(p["batch"], p["bag"], in_dim, generator=g)
                want = reference(in_dim, p["attn_dim"], out_dim, seed, x)
                torch.manual_seed(seed)  # rebuild agent module under seed
                agent = mod.GatedSetPooling(in_dim, p["attn_dim"], out_dim)
                with torch.no_grad():
                    pooled, weights = agent(x)
                if tuple(pooled.shape) != (p["batch"], out_dim):
                    failures.append("hidden '%s': pooled shape %r"
                                    % (name, tuple(pooled.shape)))
                if tuple(weights.shape) != (p["batch"], p["bag"], 1):
                    failures.append("hidden '%s': weights shape %r"
                                    % (name, tuple(weights.shape)))
                sums = weights.sum(dim=1).reshape(-1)
                if not torch.allclose(sums, torch.ones_like(sums),
                                      atol=TOL):
                    failures.append("hidden '%s': per-set weight sums != 1"
                                    % name)
            else:
                bag = p["bag"]
                x = torch.randn(bag, in_dim, generator=g) if bag > 0 \
                    else torch.zeros(0, in_dim)
                want = reference(in_dim, p["attn_dim"], out_dim, seed, x)
                torch.manual_seed(seed)
                agent = mod.GatedSetPooling(in_dim, p["attn_dim"], out_dim)
                with torch.no_grad():
                    pooled, weights = agent(x)
                if bag == 0:
                    if tuple(weights.shape) != (0, 1):
                        failures.append("hidden '%s': empty weights shape %r"
                                        % (name, tuple(weights.shape)))
                else:
                    if tuple(weights.shape) != (bag, 1):
                        failures.append("hidden '%s': weights shape %r"
                                        % (name, tuple(weights.shape)))
                    if bag == 1 and abs(float(weights[0, 0]) - 1.0) > TOL:
                        failures.append("hidden '%s': single weight != 1.0"
                                        % name)
            # exact numeric equality vs the reference
            got_num = {"pooled": [float(v) for v in pooled.reshape(-1)],
                       "weights": [float(v) for v in weights.reshape(-1)],
                       "bag": int(p["bag"])}
            if not close(got_num, want):
                failures.append("hidden '%s': numeric mismatch vs reference"
                                % name)
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
