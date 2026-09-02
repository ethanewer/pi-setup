#!/usr/bin/env bash
# Oracle for cedar-cipher: writes the deliverable programs, then RUNS them
# against the /app fixtures to produce almost all outputs. Ends by smoke-
# testing the offline loader.
set -euo pipefail
cd /app

# ---------------------------------------------------------------- shared BPE module
cat > /app/cedar_tokenizer.py <<'PY'
#!/usr/bin/env python3
"""CedarCipher deterministic byte-pair-encoding tokenizer (self-contained)."""
import json
from collections import Counter

def read_words(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read().split()

def train_bpe(words, cap):
    """Train BPE to bounded vocab. Deterministic: most frequent adjacent pair
    wins; ties resolved to the lexicographically smaller pair."""
    seqs = [list(w) for w in words]
    vocab = set()
    for w in words:
        vocab.update(w)
    if len(vocab) >= cap:
        # cap is already full of single-byte tokens; nothing can be merged
        # without exceeding the bound.
        clipped = sorted(vocab)[:cap]
        return {"merges": [], "vocab": clipped, "vocab_size": len(clipped)}
    merges = []
    while True:
        if len(vocab) >= cap:
            break
        cnt = Counter()
        for w in seqs:
            for i in range(len(w) - 1):
                cnt[(w[i], w[i + 1])] += 1
        if not cnt:
            break
        best = min(cnt, key=lambda p: (-cnt[p], p))
        if cnt[best] < 2:
            break
        a, b = best
        merged = a + b
        nseq = []
        for w in seqs:
            out = []
            i = 0
            n = len(w)
            while i < n:
                if i + 1 < n and w[i] == a and w[i + 1] == b:
                    out.append(merged)
                    i += 2
                else:
                    out.append(w[i])
                    i += 1
            nseq.append(out)
        seqs = nseq
        merges.append([a, b])
        vocab.add(merged)
    return {"merges": merges, "vocab": sorted(vocab), "vocab_size": len(vocab)}

def encode(text, merges):
    """Encode text: apply merges left-to-right, one merge at a time, in the
    order the merges were learned. Characters never mentioned by any merge
    remain single tokens."""
    toks = list(text)
    for a, b in merges:
        out = []
        i = 0
        n = len(toks)
        while i < n:
            if i + 1 < n and toks[i] == a and toks[i + 1] == b:
                out.append(a + b)
                i += 2
            else:
                out.append(toks[i])
                i += 1
        toks = out
    return toks

def load_merges(tokenizer_path):
    with open(tokenizer_path, encoding="utf-8") as fh:
        data = json.load(fh)
    return [tuple(m) for m in data.get("merges", [])]

if __name__ == "__main__":
    import sys
    t = train_bpe(["cedar"], 64)
    print("SMOKE_OK", t["vocab_size"], len(t["merges"]))
PY

# ---------------------------------------------------------------- filter_locale.py
cat > /app/filter_locale.py <<'PY'
#!/usr/bin/env python3
"""Filter a jsonl dataset to one locale and export the requested columns."""
import argparse, json

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True)
    ap.add_argument("--locale", required=True)
    ap.add_argument("--columns", required=True, help="comma-separated column names")
    ap.add_argument("--output", required=True)
    a = ap.parse_args()
    cols = [c.strip() for c in a.columns.split(",")]
    out = []
    with open(a.input, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            obj = json.loads(line)
            if obj.get("locale") != a.locale:
                continue
            rec = {c: obj.get(c, "") for c in cols}
            out.append(rec)
    with open(a.output, "w", encoding="utf-8") as fh:
        for rec in out:
            fh.write(json.dumps(rec) + "\n")
    print("WROTE %d rows" % len(out))

if __name__ == "__main__":
    main()
PY

# ---------------------------------------------------------------- train_bpe.py
cat > /app/train_bpe.py <<'PY'
#!/usr/bin/env python3
"""Train a byte-pair-encoding tokenizer to a bounded, deterministic vocab."""
import argparse, json, sys
sys.path.insert(0, "/app")
from cedar_tokenizer import read_words, train_bpe

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True)
    ap.add_argument("--output", required=True)
    ap.add_argument("--cap", type=int, required=True)
    a = ap.parse_args()
    words = read_words(a.input)
    model = train_bpe(words, a.cap)
    model["cap"] = a.cap
    with open(a.output, "w", encoding="utf-8") as fh:
        json.dump(model, fh, indent=2)
    print("TRAINED cap=%d vocab_size=%d merges=%d" % (
        a.cap, model["vocab_size"], len(model["merges"])))

if __name__ == "__main__":
    import json  # noqa: F401  (used above)
    main()
PY

# ---------------------------------------------------------------- tokenize.py
cat > /app/tokenize.py <<'PY'
#!/usr/bin/env python3
"""Tokenize two text columns (primary, secondary) of every row with the
downloaded offline tokenizer and report token counts."""
import argparse, json, sys
sys.path.insert(0, "/app")
from cedar_tokenizer import encode, load_merges

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True)
    ap.add_argument("--output", required=True)
    ap.add_argument("--tokenizer", default="/app/offline_assets/tokenizer.json")
    a = ap.parse_args()
    merges = load_merges(a.tokenizer)
    total = 0
    rows = 0
    per = {"primary": 0, "secondary": 0}
    with open(a.input, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            r = json.loads(line)
            np_ = len(encode(r.get("primary", ""), merges))
            ns = len(encode(r.get("secondary", ""), merges))
            total += np_ + ns
            rows += 1
            per["primary"] += np_
            per["secondary"] += ns
    result = {"total_tokens": total, "rows": rows,
              "cols": ["primary", "secondary"], "per_col": per}
    with open(a.output, "w", encoding="utf-8") as fh:
        json.dump(result, fh, indent=2)
    print(json.dumps(result))

if __name__ == "__main__":
    main()
PY

# ---------------------------------------------------------------- detect_lang.py
cat > /app/detect_lang.py <<'PY'
#!/usr/bin/env python3
"""Tag every *.txt under a directory as English / other-language.
Rule: a document is English iff every codepoint is ASCII (< 0x80) and the
file contains at least one ASCII letter."""
import argparse, glob, json, os

def is_english(content):
    if not any(c.isalpha() for c in content):
        return False
    return all(ord(c) < 0x80 for c in content)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True)
    ap.add_argument("--output", required=True)
    a = ap.parse_args()
    english, other = [], []
    for path in sorted(glob.glob(os.path.join(a.dir, "*.txt"))):
        with open(path, encoding="utf-8") as fh:
            content = fh.read()
        if is_english(content):
            english.append(os.path.basename(path))
        else:
            other.append(os.path.basename(path))
    result = {"english": english, "other": other}
    with open(a.output, "w", encoding="utf-8") as fh:
        json.dump(result, fh, indent=2)
    print(json.dumps(result))

if __name__ == "__main__":
    main()
PY

# ---------------------------------------------------------------- fetch_leaderboard.py
cat > /app/fetch_leaderboard.py <<'PY'
#!/usr/bin/env python3
"""Read a leaderboard grid, find the top row by the metric's numeric value,
and emit that row's model identifier. Ties break to the lexicographically
smallest model_id."""
import argparse, json

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True)
    ap.add_argument("--output", required=True)
    a = ap.parse_args()
    with open(a.input, encoding="utf-8") as fh:
        data = json.load(fh)
    rows = data.get("rows", [])
    metric = data.get("metric", "score")
    if not rows:
        top = ""
    else:
        def val(r):
            return float(r.get(metric, 0.0))
        mval = max(val(r) for r in rows)
        cands = [r for r in rows if val(r) == mval]
        top = min(cands, key=lambda r: str(r.get("model_id", "")))["model_id"]
    with open(a.output, "w", encoding="utf-8") as fh:
        fh.write(top)
    print("TOP=%s" % top)

if __name__ == "__main__":
    main()
PY

# ---------------------------------------------------------------- run_mcq.py
cat > /app/run_mcq.py <<'PY'
#!/usr/bin/env python3
"""Load the lm-eval-style harness config, render each document with the
mandated prompt template, and select the gold label per document."""
import argparse, json, sys
sys.path.insert(0, "/app")
import yaml

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", default="/app/tasks.yaml")
    ap.add_argument("--output", default="/app/mcq_result.json")
    a = ap.parse_args()
    with open(a.config, encoding="utf-8") as fh:
        cfg = yaml.safe_load(fh)
    labels = cfg["labels"]
    tpl = cfg["template"]
    with open(cfg["dataset"], encoding="utf-8") as fh:
        ds = json.load(fh)
    samples = ds["samples"]
    per_doc = []
    for i, s in enumerate(samples):
        qcol = cfg["query_column"]
        tcol = cfg["title_column"]
        q = s.get(qcol, "")
        t = s.get(tcol, "")
        fills = {"query": q, "title": t}
        for k in range(len(labels)):
            fills["c%d" % k] = labels[k]
        prompt = tpl.format(**fills)
        gold_index = int(s.get(cfg["gold_column"], -1))
        label = labels[gold_index] if 0 <= gold_index < len(labels) else None
        per_doc.append({"doc": i, "query": q, "title": t,
                        "gold_index": gold_index, "gold_label": label,
                        "prompt": prompt})
    acc = (sum(1 for d in per_doc if d["gold_index"] is not None) /
           len(per_doc)) if per_doc else 1.0
    out = {"task": cfg.get("task", "cedar_mcq"), "labels": labels,
           "metric": cfg.get("metric", "acc"), "acc": round(float(acc), 6),
           "samples_n": len(per_doc), "samples": per_doc}
    with open(a.output, "w", encoding="utf-8") as fh:
        json.dump(out, fh, indent=2)
    print("MCQ_OK samples=%d acc=%.4f" % (len(per_doc), acc))

if __name__ == "__main__":
    main()
PY

# ---------------------------------------------------------------- tasks.yaml
cat > /app/tasks.yaml <<'YAML'
task: cedar_mcq
runner: mcq
dataset: /app/mcq_dataset.json
query_column: query
title_column: title
gold_column: gold
metric: acc_mcq
labels: [celadon, travertine, porphyry, obsidian]
template: "UseCedarMCQ query={query} doc={title} choices={c0}|{c1}|{c2}|{c3} gold:"
YAML

# ---------------------------------------------------------------- offline assets
mkdir -p /app/offline_assets
# (a) tokenizer — the BPE we just trained, persisted as the downloadable
#     tokenizer artifact that the local loader stanzas offline.
python3 - <<'PY'
import json, sys
sys.path.insert(0, "/app")
from cedar_tokenizer import train_bpe, read_words
words = read_words("/app/bpe_corpus.txt")
model = train_bpe(words, 240)
tok = {"type": "cedar_bpe", "model": "cedar/cascade-9M", "merges": model["merges"]}
with open("/app/offline_assets/tokenizer.json", "w", encoding="utf-8") as fh:
    json.dump(tok, fh)
print("tokenizer.json written", len(model["merges"]), "merges")
PY

# (b) config.json
python3 - <<'PY'
import json
cfg = {"name": "cedar/cascade-9M", "type": "cedar_cascade",
       "layers": 3, "d_model": 128, "d_hidden": 256,
       "d_vocab": 240, "activation": "swish", "tie_weights": True}
with open("/app/offline_assets/config.json", "w", encoding="utf-8") as fh:
    json.dump(cfg, fh, indent=2)
print("config.json written")
PY

# (c) model weights (numpy arrays) — the weights ingested offline.
python3 - <<'PY'
import numpy as np
rng = np.random.default_rng(20260217)
arrays = {
    "shard_i": rng.standard_normal((16, 64)).astype(np.float32),
    "shard_q": rng.standard_normal((64, 128)).astype(np.float32),
    "shard_k": rng.standard_normal((64, 128)).astype(np.float32),
    "last": rng.standard_normal((128, 4)).astype(np.float32),
}
np.savez("/app/offline_assets/model_weights.npz", **arrays)
print("model_weights.npz written")
PY

# (d) loader.py — validate full local file set and load offline.
cat > /app/offline_assets/loader.py <<'PY'
#!/usr/bin/env python3
"""Offline loader for CedarCascade. Succeeds ONLY if every artifact a local
load inspects (config, tokenizer, weights) is persisted; raises otherwise.
Never touches the network: all artifacts must already be on disk."""
import json, os, sys
import numpy as np

sys.dont_write_bytecode = True
# Force every HF-style env flag off-network so a stray download is impossible.
os.environ.setdefault("TRANSFORMERS_OFFLINE", "1")
os.environ.setdefault("HF_HUB_OFFLINE", "1")

REQUIRED = ["config.json", "tokenizer.json", "model_weights.npz"]


def load_offline(assets_dir):
    missing = [n for n in REQUIRED
               if not os.path.isfile(os.path.join(assets_dir, n))]
    if missing:
        raise RuntimeError("offline assets incomplete: " + ",".join(missing))
    cfg_path = os.path.join(assets_dir, "config.json")
    with open(cfg_path, encoding="utf-8") as fh:
        config = json.load(fh)
    tok_path = os.path.join(assets_dir, "tokenizer.json")
    with open(tok_path, encoding="utf-8") as fh:
        tokenizer = json.load(fh)
    weight_path = os.path.join(assets_dir, "model_weights.npz")
    with np.load(weight_path) as data:
        weights = {k: data[k].copy() for k in data.files}
    return {"config": config, "tokenizer": tokenizer, "weights": weights}


def main():
    data = load_offline("/app/offline_assets")
    w = data["weights"]
    assert all(w[k].dtype == np.float32 for k in w)
    print("OFFLINE_LOAD_OK shards=%d name=%s" % (
        len(w), data["config"]["name"]))


if __name__ == "__main__":
    main()
PY
chmod +x /app/offline_assets/loader.py

# ---------------------------------------------------------------- running the pipeline
python3 /app/filter_locale.py \
  --input /app/corpus.jsonl --locale es \
  --columns id,primary,secondary --output /app/locale.jsonl

python3 /app/train_bpe.py \
  --input /app/bpe_corpus.txt --cap 240 --output /app/bpe_model.json

python3 /app/tokenize.py \
  --input /app/locale.jsonl --output /app/token_counts.json

python3 /app/detect_lang.py --dir /app/documents --output /app/lang_flags.json

python3 /app/fetch_leaderboard.py \
  --input /app/leaderboard_source.json --output /app/leaderboard_top.txt

python3 /app/run_mcq.py --config /app/tasks.yaml --output /app/mcq_result.json

python3 /app/offline_assets/loader.py

echo "ORACLE_DONE"