#!/bin/bash
# Verifier for elm-anchor: checks the visible deliverables, ENFORCES the
# no-modify rule on the shipped loader/corpus, and EXECUTES the deliverable
# program (/app/emit.py) on the visible corpus and on every hidden corpus under
# /tests/hidden, validating the emitted files with the shipped loader and
# probe tokenizations. Writes 0/1 to /logs/verifier/reward.txt. Never crashes
# on malformed/missing agent output.
set -u

mkdir -p /logs/verifier
reward=0

no_modify_broken=0
for f in merm_loader.py data/corpus.txt; do
    if [ ! -f "/app/$f" ]; then
        echo "no-modify: /app/$f missing" >&2
        no_modify_broken=1
    fi
done
if [ "$no_modify_broken" = "0" ]; then
    for f in merm_loader.py data/corpus.txt; do
        want="$(cat "/tests/expected_visible/$(basename "$f").sha" 2>/dev/null)"
        got="$(sha256sum "/app/$f" | awk '{print $1}')"
        if [ "$got" != "$want" ]; then
            echo "no-modify: /app/$f was modified" >&2
            no_modify_broken=1
        fi
    done
fi

python3 - "$no_modify_broken" <<'PY'
import json, os, shutil, subprocess, sys

EMIT = "/app/emit.py"
no_modify_broken = int(sys.argv[1])
failures = []

if no_modify_broken:
    failures.append("shipped files modified or missing (no-modify rule)")

sys.path.insert(0, "/app")


def run_emit(corpus, outdir):
    if os.path.isdir(outdir):
        shutil.rmtree(outdir)
    try:
        return subprocess.run([sys.executable, EMIT, corpus, outdir],
                              capture_output=True, text=True, timeout=180)
    except Exception as e:
        print("run error:", e)
        return None


def load_with_shipped_loader(vocab_path, merges_path):
    """Returns the tokenizer, or an error string if loading fails."""
    import merm_loader as ml
    try:
        return ml.MermTokenizer(vocab_path, merges_path)
    except Exception as e:
        return "loader rejected files: %s" % e


def check_case(outdir, exp_dir, label):
    vp = os.path.join(outdir, "vocab.txt")
    mp = os.path.join(outdir, "merges.txt")
    for p in (vp, mp):
        if not os.path.isfile(p):
            return "missing %s" % os.path.basename(p)
    try:
        with open(vp, "rb") as fh:
            got_v = fh.read()
        with open(mp, "rb") as fh:
            got_m = fh.read()
        with open(os.path.join(exp_dir, "expected_vocab.txt"), "rb") as fh:
            want_v = fh.read()
        with open(os.path.join(exp_dir, "expected_merges.txt"), "rb") as fh:
            want_m = fh.read()
    except Exception as e:
        return "unreadable files (%s)" % e
    if got_v != want_v:
        return "vocab.txt differs from reference"
    if got_m != want_m:
        return "merges.txt differs from reference"
    tok = load_with_shipped_loader(vp, mp)
    if isinstance(tok, str):
        return tok
    try:
        with open(os.path.join(exp_dir, "probes.json")) as fh:
            probes = json.load(fh)
        for p in probes:
            if tok.encode(p["text"]) != p["ids"]:
                return "probe tokenization mismatch for %r" % p["text"][:40]
    except Exception as e:
        return "probe check failed (%s)" % e
    return None


if not os.path.isfile(EMIT):
    failures.append("missing /app/emit.py")
else:
    # ---- visible corpus: execute the deliverable ---------------------------
    r = run_emit("/app/data/corpus.txt", "/tmp/ea_vis")
    if r is None or r.returncode != 0:
        failures.append("visible run failed (rc=%s)"
                        % (getattr(r, "returncode", None)))
    else:
        err = check_case("/tmp/ea_vis", "/tests/expected_visible", "visible")
        if err:
            failures.append("visible: " + err)
    # ---- visible deliverable files in /app ---------------------------------
    if os.path.isfile("/app/vocab.txt") and os.path.isfile("/app/merges.txt"):
        err = check_case("/app", "/tests/expected_visible", "visible-in-app")
        if err:
            failures.append("/app files: " + err)
    else:
        failures.append("missing /app/vocab.txt or /app/merges.txt")

    # ---- hidden corpora ------------------------------------------------------
    hidden = "/tests/hidden"
    cases = sorted(d for d in os.listdir(hidden)
                   if os.path.isdir(os.path.join(hidden, d))) if os.path.isdir(hidden) else []
    if not cases:
        failures.append("no hidden cases present")
    for c in cases:
        base = os.path.join(hidden, c)
        if not all(os.path.isfile(os.path.join(base, f))
                   for f in ("corpus.txt", "expected_vocab.txt",
                             "expected_merges.txt", "probes.json")):
            failures.append("hidden '%s' malformed" % c)
            continue
        r = run_emit(os.path.join(base, "corpus.txt"), "/tmp/ea_h_" + c)
        if r is None or r.returncode != 0:
            failures.append("hidden '%s': run failed (rc=%s)"
                            % (c, getattr(r, "returncode", None)))
            continue
        err = check_case("/tmp/ea_h_" + c, base, "hidden/" + c)
        if err:
            failures.append("hidden '%s': %s" % (c, err))

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
