#!/bin/bash
# Verifier for mica-fjord: checks the pickled vocabulary deliverables, ENFORCES
# the no-modify rule on the supplied /app fixtures, and EXECUTES
# /app/build_vocab.py on the visible case and on every hidden case in
# /tests/hidden. Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

PRISTINE_CORPUS_SHA="4bc9980d7069524852106f876afa4d639d9445e268d47ca0fd053d82c6b4a96f"
PRISTINE_EMB_SHA="b10039465a6118eca90e658b4b75e451f776c9c53ce8c23d68ad9a84392d3ee9"

no_modify_broken=0
if [ ! -f /app/data/telemetry_corpus.txt ]; then
    echo "no-modify: /app/data/telemetry_corpus.txt missing" >&2
    no_modify_broken=1
else
    actual="$(sha256sum /app/data/telemetry_corpus.txt | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_CORPUS_SHA" ]; then
        echo "no-modify: telemetry corpus was modified" >&2
        no_modify_broken=1
    fi
fi
if [ ! -f /app/embeddings.npy ]; then
    echo "no-modify: /app/embeddings.npy missing" >&2
    no_modify_broken=1
else
    actual="$(sha256sum /app/embeddings.npy | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_EMB_SHA" ]; then
        echo "no-modify: /app/embeddings.npy was modified" >&2
        no_modify_broken=1
    fi
fi

python3 - "$no_modify_broken" <<'PY'
import collections
import json
import os
import pickle
import re
import subprocess
import sys

sys.path.insert(0, "/app")
import station_vocab  # noqa: E402  (the only class path that may unpickle)

BUILD = "/app/build_vocab.py"
no_modify_broken = int(sys.argv[1])


def reference_vocab(corpus_path, emb_path):
    """Independent recomputation of the documented vocabulary rule."""
    text = open(corpus_path, "r", encoding="utf-8").read()
    toks = re.findall(r"[a-z0-9]+", text.lower())
    freq = collections.Counter(toks)
    cands = sorted((w for w, c in freq.items() if c >= 2),
                   key=lambda w: (-freq[w], w))
    rows = int(emb_shape(emb_path))
    if len(cands) < rows - 2:
        return None, None
    regular = cands[: rows - 2]
    word2idx = {"<pad>": 0, "<unk>": 1}
    for j, tok in enumerate(regular):
        word2idx[tok] = 2 + j
    regular_sorted = regular
    report = {
        "vocab_size": len(word2idx),
        "embedding_rows": rows,
        "inverse_ok": True,
        "special_tokens": ["<pad>", "<unk>"],
        "first_regular": regular_sorted[0] if regular_sorted else None,
        "last_regular": regular_sorted[-1] if regular_sorted else None,
    }
    return word2idx, report


def emb_shape(path):
    import numpy as np
    return np.load(path).shape[0]


def load_vocab(path):
    """Unpickle guarded; returns (vocab, err)."""
    try:
        with open(path, "rb") as fh:
            obj = pickle.load(fh)
    except Exception as exc:  # unpickling failure (e.g. wrong module path)
        return None, "unpickle failed: %r" % (exc,)
    if not isinstance(obj, station_vocab.Vocab):
        return None, "not a station_vocab.Vocab instance (got %r)" % type(obj)
    return obj, None


def check_vocab_obj(v, emb_path, word2idx_expected):
    rows = int(emb_shape(emb_path))
    if not isinstance(v.word2idx, dict) or not isinstance(v.idx2word, dict):
        return "word2idx/idx2word must be dicts"
    if not v.check_inverse():
        return "maps are not exact inverses"
    if v.size() != rows:
        return "vocab size %d != embedding rows %d" % (v.size(), rows)
    if dict(v.word2idx) != dict(word2idx_expected):
        return "word2idx does not match the documented rule"
    return None


def run_build(corpus, emb, pkl_out, rep_out):
    for p in (pkl_out, rep_out):
        if os.path.exists(p):
            os.remove(p)
    r = subprocess.run(
        [sys.executable, BUILD, corpus, emb, pkl_out, rep_out],
        capture_output=True, text=True, timeout=180, cwd="/app",
    )
    return r


failures = []
if no_modify_broken:
    failures.append("visible inputs modified or missing (no-modify rule)")

if not os.path.isfile(BUILD):
    failures.append("missing /app/build_vocab.py")
else:
    # --- visible-case deliverables ---
    vis_corpus = "/app/data/telemetry_corpus.txt"
    vis_emb = "/app/embeddings.npy"
    ref_w2i, ref_report = reference_vocab(vis_corpus, vis_emb)
    if ref_w2i is None:
        failures.append("visible fixture unexpectedly infeasible (verifier bug)")
    if os.path.isfile("/app/vocab.pkl"):
        v, err = load_vocab("/app/vocab.pkl")
        if err:
            failures.append("vocab.pkl: %s" % err)
        else:
            err = check_vocab_obj(v, vis_emb, ref_w2i)
            if err:
                failures.append("vocab.pkl: %s" % err)
    else:
        failures.append("missing /app/vocab.pkl")

    if os.path.isfile("/app/vocab_report.json"):
        try:
            got = json.load(open("/app/vocab_report.json"))
            if got != ref_report:
                failures.append("vocab_report.json mismatch: %r vs %r" % (got, ref_report))
        except Exception as exc:
            failures.append("vocab_report.json unreadable: %r" % (exc,))
    else:
        failures.append("missing /app/vocab_report.json")

    # --- EXECUTE the deliverable on the visible case ---
    r = run_build(vis_corpus, vis_emb, "/tmp/mica_vis.pkl", "/tmp/mica_vis.json")
    if r.returncode != 0:
        failures.append("build_vocab.py failed on visible case: %s" % r.stderr[-300:])
    else:
        v2, err = load_vocab("/tmp/mica_vis.pkl")
        if err:
            failures.append("visible rerun pickle: %s" % err)
        else:
            err = check_vocab_obj(v2, vis_emb, ref_w2i)
            if err:
                failures.append("visible rerun pickle: %s" % err)
        try:
            if json.load(open("/tmp/mica_vis.json")) != ref_report:
                failures.append("visible rerun report mismatch")
        except Exception as exc:
            failures.append("visible rerun report unreadable: %r" % (exc,))

    # --- hidden cases ---
    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        for case in sorted(os.listdir(hidden_dir)):
            base = os.path.join(hidden_dir, case)
            corpus = os.path.join(base, "corpus.txt")
            emb = os.path.join(base, "embeddings.npy")
            exp_path = os.path.join(base, "expected.json")
            if not all(os.path.isfile(p) for p in (corpus, emb, exp_path)):
                failures.append("hidden '%s' malformed" % case)
                continue
            try:
                exp = json.load(open(exp_path))
            except Exception:
                failures.append("hidden '%s' expected.json unreadable" % case)
                continue
            pkl_out = "/tmp/mica_%s.pkl" % case
            rep_out = "/tmp/mica_%s.json" % case
            r = run_build(corpus, emb, pkl_out, rep_out)
            if exp.get("expect_failure"):
                if r.returncode == 0:
                    failures.append("hidden '%s': expected non-zero exit" % case)
                elif os.path.exists(pkl_out) or os.path.exists(rep_out):
                    failures.append("hidden '%s': outputs must not exist on failure" % case)
                elif not r.stderr.strip():
                    failures.append("hidden '%s': expected an stderr message" % case)
                continue
            if r.returncode != 0:
                failures.append("hidden '%s': build failed: %s" % (case, r.stderr[-300:]))
                continue
            v3, err = load_vocab(pkl_out)
            if err:
                failures.append("hidden '%s': %s" % (case, err))
                continue
            err = check_vocab_obj(v3, emb, exp.get("word2idx", {}))
            if err:
                failures.append("hidden '%s': %s" % (case, err))
                continue
            try:
                if json.load(open(rep_out)) != exp.get("report"):
                    failures.append("hidden '%s': report mismatch" % case)
            except Exception as exc:
                failures.append("hidden '%s': report unreadable: %r" % (case, exc))
    else:
        failures.append("no hidden cases present")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
