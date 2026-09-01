#!/bin/bash
# Verifier for opal-basin: checks the pinned torch/transformers toolchain is
# intact at the baseline versions, the vendor script is untouched, EXECUTES
# /app/refresh.sh and validates its runtime-derived manifest, and EXECUTES
# /app/score.py on the visible inputs and hidden text files against a
# reference computed from the local model assets. Writes 1/0 to
# /logs/verifier/reward.txt. Never crashes on malformed agent output.
set -u

mkdir -p /logs/verifier
REWARD=0
VENDOR_SHA="5a8236e5ab8393a0d166726246457143f13b08facf2922162b4b8de9edf77514"

vendor_ok=1
if [ ! -f /app/vendor/refresh_toolchain.sh ]; then
    echo "vendor script missing" >&2
    vendor_ok=0
else
    actual="$(sha256sum /app/vendor/refresh_toolchain.sh | awk '{print $1}')"
    if [ "$actual" != "$VENDOR_SHA" ]; then
        echo "vendor script was modified" >&2
        vendor_ok=0
    fi
fi

python3 - "$vendor_ok" <<'PY' && REWARD=1
import hashlib
import importlib.metadata as im
import json
import os
import subprocess
import sys

MODEL_DIR = "/app/assets/tiny-bert"
failures = []
vendor_ok = int(sys.argv[1]) == 1


def baseline():
    with open("/app/baseline.json", "r", encoding="utf-8") as fh:
        return json.load(fh)


# --- 1. pinned toolchain intact -------------------------------------------
try:
    base = baseline()
except Exception as e:
    failures.append("baseline.json unreadable: %s" % e)
else:
    for pkg in ("torch", "transformers", "numpy"):
        try:
            dist = im.version(pkg)
        except Exception as e:
            failures.append("pinned package %s not importable/installed: %s" % (pkg, e))
            continue
        if dist != base[pkg]["dist_version"]:
            failures.append("pinned package %s drifted: %s != %s"
                            % (pkg, dist, base[pkg]["dist_version"]))
    try:
        import torch
        if torch.__version__ != base["torch"]["import_version"]:
            failures.append("torch import version drifted: %s != %s"
                            % (torch.__version__, base["torch"]["import_version"]))
    except Exception as e:
        failures.append("torch import failed: %s" % e)
    try:
        import transformers
        if transformers.__version__ != base["transformers"]["import_version"]:
            failures.append("transformers import version drifted")
    except Exception as e:
        failures.append("transformers import failed: %s" % e)
    try:
        weights = os.path.join(MODEL_DIR, "model.safetensors")
        sha = hashlib.sha256(open(weights, "rb").read()).hexdigest()
        if sha != base["weights_sha256"]:
            failures.append("model assets were modified")
    except Exception as e:
        failures.append("could not hash model assets: %s" % e)

if vendor_ok is False:
    failures.append("vendor/refresh_toolchain.sh missing or modified")

# --- reference embeddings from the live local assets -----------------------
ref_texts = ref_embeds = None
try:
    import torch
    from transformers import AutoModel, AutoTokenizer
    tok = AutoTokenizer.from_pretrained(MODEL_DIR, local_files_only=True)
    model = AutoModel.from_pretrained(MODEL_DIR, local_files_only=True)
    model.eval()

    def read_texts(path):
        with open(path, "r", encoding="utf-8") as fh:
            lines = fh.read().split("\n")
        if lines and lines[-1] == "":
            lines.pop()
        return lines

    def reference(path):
        texts = read_texts(path)
        embeds = []
        with torch.no_grad():
            for text in texts:
                enc = tok(text, return_tensors="pt", truncation=True, max_length=32)
                out = model(**enc)
                embeds.append(out.last_hidden_state[0].mean(dim=0).tolist())
        return texts, embeds
except Exception as e:
    failures.append("offline load path broken (reference unavailable): %s" % e)


def check_output(obj, texts, embeds, tag):
    if not isinstance(obj, dict) or set(obj.keys()) != {"texts", "embeddings"}:
        raise AssertionError("%s: bad output keys" % tag)
    if obj["texts"] != texts:
        raise AssertionError("%s: texts mismatch" % tag)
    got = obj["embeddings"]
    if not isinstance(got, list) or len(got) != len(embeds):
        raise AssertionError("%s: embeddings shape mismatch" % tag)
    for i, (g, w) in enumerate(zip(got, embeds)):
        if not isinstance(g, list) or len(g) != len(w):
            raise AssertionError("%s: embedding %d width mismatch" % (tag, i))
        for gv, wv in zip(g, w):
            try:
                fv = float(gv)
            except Exception:
                raise AssertionError("%s: embedding %d non-numeric" % (tag, i))
            if abs(fv - wv) > 2e-3:
                raise AssertionError("%s: embedding %d value drift" % (tag, i))


def run_scorer(texts_path, tag):
    out = "/tmp/opal_scores_%s.json" % tag
    if os.path.exists(out):
        os.remove(out)
    try:
        r = subprocess.run([sys.executable, "/app/score.py", MODEL_DIR,
                            texts_path, out],
                           capture_output=True, text=True, timeout=240)
    except Exception as e:
        failures.append("%s: scorer crashed: %s" % (tag, e))
        return
    if r.returncode != 0:
        failures.append("%s: scorer non-zero exit: %s" % (tag, r.stderr[-300:]))
        return
    if ref_texts is None:
        return
    texts, embeds = reference(texts_path)
    try:
        with open(out, "r", encoding="utf-8") as fh:
            check_output(json.load(fh), texts, embeds, tag)
    except AssertionError as e:
        failures.append(str(e))
    except Exception as e:
        failures.append("%s: unreadable output: %s" % (tag, e))


if ref_texts is not None and not failures:
    # --- 2. refresh.sh executes cleanly with runtime-derived manifest -------
    if not os.path.isfile("/app/refresh.sh"):
        failures.append("missing /app/refresh.sh")
    elif not os.access("/app/refresh.sh", os.X_OK):
        failures.append("/app/refresh.sh not executable")
    else:
        for flag in ("/app/run/refresh_manifest.json", "/app/run/ready.flag"):
            p = "/app/run/" + os.path.basename(flag)
            if os.path.exists(p):
                try:
                    os.remove(p)
                except OSError:
                    pass
        try:
            r = subprocess.run(["/app/refresh.sh"], capture_output=True,
                               text=True, timeout=120)
        except Exception as e:
            failures.append("refresh.sh crashed: %s" % e)
        else:
            if r.returncode != 0:
                failures.append("refresh.sh non-zero exit: %s" % r.stderr[-300:])
            elif "REFRESH OK" not in r.stdout:
                failures.append("refresh.sh did not print REFRESH OK")
            else:
                try:
                    with open("/app/run/refresh_manifest.json") as fh:
                        man = json.load(fh)
                    if man.get("refreshed") is not True:
                        failures.append("manifest refreshed flag wrong")
                    versions = man.get("versions")
                    if not isinstance(versions, dict):
                        failures.append("manifest versions missing")
                    else:
                        for pkg in ("torch", "transformers", "numpy"):
                            if versions.get(pkg) != im.version(pkg):
                                failures.append("manifest %s version wrong "
                                                "(not runtime-derived)" % pkg)
                except Exception as e:
                    failures.append("manifest unreadable: %s" % e)
                if not (os.path.isfile("/app/run/ready.flag")
                        and os.path.getsize("/app/run/ready.flag") > 0):
                    failures.append("ready.flag missing or empty")

    # --- 3. scorer on visible inputs + deliverable scores.json --------------
    run_scorer("/app/input_texts.txt", "visible")
    try:
        with open("/app/scores.json", "r", encoding="utf-8") as fh:
            texts, embeds = reference("/app/input_texts.txt")
            check_output(json.load(fh), texts, embeds, "scores.json")
    except AssertionError as e:
        failures.append(str(e))
    except Exception as e:
        failures.append("scores.json unreadable: %s" % e)

    # --- 4. hidden text files ------------------------------------------------
    hidden = "/tests/hidden"
    if os.path.isdir(hidden):
        cases = sorted(f for f in os.listdir(hidden) if f.endswith(".txt"))
        if not cases:
            failures.append("no hidden cases present")
        for f in cases:
            run_scorer(os.path.join(hidden, f), f)
    else:
        failures.append("no hidden case dir")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

echo "$REWARD" > /logs/verifier/reward.txt
exit 0
