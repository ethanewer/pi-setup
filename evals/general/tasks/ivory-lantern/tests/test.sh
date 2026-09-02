#!/bin/bash
# Verifier for ivory-lantern: checks the baked mirror is COMPLETE and servable
# by the shipped offline loader, probes the complete-mirror property (delete an
# artifact -> load must raise), and re-executes the deliverable
# /app/build_mirror.py on hidden upstream trees (fresh / corrupt / missing).
# Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

python3 - <<'PY'
import hashlib, importlib.util, json, os, shutil, subprocess, sys, tempfile

failures = []
CANONICAL = {
    "config": "config.json",
    "weights": "weights.npz",
    "vocab": "vocab.json",
    "merges": "merges.txt",
    "tokenizer_config": "tokenizer_config.json",
    "special_tokens_map": "special_tokens_map.json",
}
BUILD = "/app/build_mirror.py"
LOADER = "/app/load_pretrained.py"


def log(*a):
    print("[verifier]", *a)


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


def load_loader_module():
    spec = importlib.util.spec_from_file_location("load_pretrained", LOADER)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def reference_encode(mirror_dir):
    """Independent tokenizer semantics from the mirror's own artifacts."""
    with open(os.path.join(mirror_dir, "vocab.json")) as fh:
        vocab = json.load(fh)
    with open(os.path.join(mirror_dir, "special_tokens_map.json")) as fh:
        special = json.load(fh)
    unk = special.get("unk_token")

    def encode(text):
        ids = []
        for tok in str(text).split():
            if tok in vocab:
                ids.append(vocab[tok])
            elif unk is not None and unk in vocab:
                ids.append(vocab[unk])
            else:
                raise KeyError(tok)
        return ids
    return encode


def check_mirror(mirror_dir, upstream_dir, label):
    """Six canonical files, byte-identical to the manifest-verified sources."""
    try:
        with open(os.path.join(upstream_dir, "manifest.json")) as fh:
            manifest = json.load(fh)
        by_name = {a["name"]: a for a in manifest.get("artifacts", [])}
    except Exception as e:
        failures.append("%s: cannot read upstream manifest: %r" % (label, e))
        return
    if set(by_name) != set(CANONICAL):
        failures.append("%s: unexpected manifest names %s" % (label, sorted(by_name)))
        return
    for name, fname in CANONICAL.items():
        dst = os.path.join(mirror_dir, fname)
        src = os.path.join(upstream_dir, by_name[name]["path"])
        if not os.path.isfile(dst):
            failures.append("%s: mirror missing %s" % (label, fname))
            continue
        if not os.path.isfile(src):
            failures.append("%s: upstream source missing %s" % (label, fname))
            continue
        if sha256_file(dst) != sha256_file(src):
            failures.append("%s: mirror %s not byte-identical to source" % (label, fname))


def check_loads(mirror_dir, label):
    try:
        mod = load_loader_module()
        bundle = mod.load_pretrained(mirror_dir)
    except Exception as e:
        failures.append("%s: load_pretrained raised: %r" % (label, e))
        return
    cfg = bundle.get("config")
    if not isinstance(cfg, dict) or "model_type" not in cfg or "hidden_size" not in cfg:
        failures.append("%s: config object incomplete" % label)
    weights = bundle.get("weights")
    if not isinstance(weights, dict) or not weights:
        failures.append("%s: weights dict empty" % label)
    else:
        import numpy as np
        for k, v in weights.items():
            if getattr(v, "ndim", 0) != 2:
                failures.append("%s: weight %s not 2-D" % (label, k))
    try:
        enc = reference_encode(mirror_dir)
        tok = bundle.get("tokenizer")
        probe = "alpha beta gamma"
        want = enc(probe)          # likely unk-id mappings
        got = tok.encode(probe)
        if list(got) != list(want):
            failures.append("%s: tokenizer.encode mismatch %r != %r" % (label, got, want))
    except Exception as e:
        failures.append("%s: tokenizer check raised: %r" % (label, e))


def run_build(upstream_dir, mirror_dir):
    try:
        r = subprocess.run([sys.executable, BUILD, upstream_dir, mirror_dir],
                           capture_output=True, text=True, timeout=120)
        return r.returncode
    except Exception as e:
        log("build run crashed: %r" % e)
        return -1


def mirror_complete(mirror_dir):
    return all(os.path.isfile(os.path.join(mirror_dir, f)) for f in CANONICAL.values())


# ---------------- visible mirror ----------------
if not os.path.isdir("/app/mirror"):
    failures.append("missing /app/mirror")
else:
    check_mirror("/app/mirror", "/app/upstream", "visible mirror")
    check_loads("/app/mirror", "visible mirror")

# deliverable: offline_check.txt
if os.path.isfile("/app/offline_check.txt"):
    try:
        with open("/app/offline_check.txt") as fh:
            txt = fh.read()
        if "OFFLINE_LOAD_OK" not in txt:
            failures.append("offline_check.txt lacks OFFLINE_LOAD_OK")
    except Exception as e:
        failures.append("offline_check.txt unreadable: %r" % e)
else:
    failures.append("missing /app/offline_check.txt")

# ---------------- complete-mirror property ----------------
if os.path.isdir("/app/mirror"):
    try:
        tmp = tempfile.mkdtemp(prefix="ivory_probe_")
        probe = os.path.join(tmp, "mirror")
        shutil.copytree("/app/mirror", probe)
        os.remove(os.path.join(probe, "merges.txt"))
        mod = load_loader_module()
        try:
            mod.load_pretrained(probe)
            failures.append("complete-mirror probe: load succeeded with a missing artifact")
        except Exception:
            pass  # expected
    except Exception as e:
        failures.append("complete-mirror probe crashed: %r" % e)

# ---------------- deliverable program present ----------------
if not os.path.isfile(BUILD):
    failures.append("missing /app/build_mirror.py")

# ---------------- hidden cases ----------------
hidden = "/tests/hidden"
if os.path.isdir(hidden):
    # fresh tree: must build and serve
    fresh_src = os.path.join(hidden, "fresh")
    if os.path.isdir(fresh_src):
        tmp = tempfile.mkdtemp(prefix="ivory_h_fresh_")
        up = os.path.join(tmp, "upstream")
        mir = os.path.join(tmp, "mirror")
        shutil.copytree(fresh_src, up)
        rc = run_build(up, mir)
        if rc != 0:
            failures.append("hidden fresh: build exited %s" % rc)
        else:
            check_mirror(mir, up, "hidden fresh")
            check_loads(mir, "hidden fresh")
    else:
        failures.append("hidden fresh: fixture missing")

    # corrupt source (digest mismatch): must fail and not leave a complete mirror
    for case in ("corrupt", "missing"):
        src = os.path.join(hidden, case)
        if not os.path.isdir(src):
            failures.append("hidden %s: fixture missing" % case)
            continue
        tmp = tempfile.mkdtemp(prefix="ivory_h_%s_" % case)
        up = os.path.join(tmp, "upstream")
        mir = os.path.join(tmp, "mirror")
        shutil.copytree(src, up)
        rc = run_build(up, mir)
        if rc == 0:
            failures.append("hidden %s: build unexpectedly succeeded" % case)
        if mirror_complete(mir):
            failures.append("hidden %s: a complete mirror was left behind on failure" % case)
else:
    failures.append("no /tests/hidden")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
