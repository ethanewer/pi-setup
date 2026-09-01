#!/bin/bash
# Clean-room quartz-dial pipeline. Writes every deliverable
# program then RUNS the work to produce all outputs.
set -euo pipefail
# /app/tokenize.py must not shadow the stdlib `tokenize` module,
# so keep /app out of every interpreter's sys.path.
export PYTHONSAFEPATH=1

# --- write filter_locale.py ---
cat > /app/filter_locale.py <<'PYEOF'
#!/usr/bin/env python3
"""filter_locale.py -- clean-room dataset stage 1.

Selects every row of a JSONL dataset whose `locale` column equals a requested
locale and re-emits the selected rows with only the requested columns, in the
requested order. Blank lines, unparseable JSON lines and non-dict rows are
ignored (with a warning). A requested column that is absent from a kept row is
emitted as null. An empty match set still produces a valid (empty) output file.
"""
import argparse
import json
import sys


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True)
    ap.add_argument("--output", required=True)
    ap.add_argument("--locale", required=True)
    ap.add_argument("--columns", required=True)
    a = ap.parse_args()

    cols = [c.strip() for c in a.columns.split(",") if c.strip()]
    want = a.locale.strip().lower()

    kept = []
    with open(a.input, encoding="utf-8") as fh:
        for lineno, line in enumerate(fh, 1):
            line = line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
            except json.JSONDecodeError:
                print("warn: invalid JSON line %d skipped" % lineno, file=sys.stderr)
                continue
            if not isinstance(row, dict):
                print("warn: line %d is not an object, skipped" % lineno, file=sys.stderr)
                continue
            cur = row.get("locale")
            if str(cur).strip().lower() != want:
                continue
            kept.append(row)

    with open(a.output, "w", encoding="utf-8") as fh:
        for row in kept:
            out_row = {c: row.get(c) for c in cols}
            fh.write(json.dumps(out_row, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()

PYEOF
chmod +x /app/filter_locale.py

# --- write tokenize.py ---
cat > /app/tokenize.py <<'PYEOF'
#!/usr/bin/env python3
"""tokenize.py -- clean-room dataset stage 3.

Tokenizes a text field of every row of a JSONL with the offline tokenizer that
lives in a local model directory, and writes aggregated token counts:

    {
      "total_tokens":          sum over rows of len(tokenize(text_field)),
      "documents":             number of dict rows read (rows with empty/absent
                               text count as documents with 0 tokens),
      "unique_tokens":         number of distinct token strings seen,
      "avg_tokens_per_doc":    round(total_tokens / documents)  (0 if empty)
    }

The tokenizer is loaded entirely offline (HF_HUB_OFFLINE / TRANSFORMERS_OFFLINE)
from the given --model directory; no network call is made.  Blank lines and
unparseable JSON lines are skipped.
"""
import argparse
import json
import os
import sys

os.environ.setdefault("HF_HUB_OFFLINE", "1")
os.environ.setdefault("TRANSFORMERS_OFFLINE", "1")
os.environ.setdefault("HF_DATASETS_OFFLINE", "1")

from transformers import AutoTokenizer


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True)
    ap.add_argument("--output", required=True)
    ap.add_argument("--model", required=True)
    ap.add_argument("--field", default="text")
    a = ap.parse_args()

    tokenizer = AutoTokenizer.from_pretrained(a.model)

    total = 0
    docs = 0
    unique = set()
    with open(a.input, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
            except json.JSONDecodeError:
                print("warn: invalid JSON line skipped", file=sys.stderr)
                continue
            if not isinstance(row, dict):
                continue
            text = row.get(a.field)
            tokens = tokenizer.tokenize(text) if isinstance(text, str) and text else []
            total += len(tokens)
            unique.update(tokens)
            docs += 1

    avg = int(round(total / docs)) if docs else 0
    with open(a.output, "w", encoding="utf-8") as fh:
        json.dump({
            "total_tokens": total,
            "documents": docs,
            "unique_tokens": len(unique),
            "avg_tokens_per_doc": avg,
        }, fh, indent=2)


if __name__ == "__main__":
    main()

PYEOF
chmod +x /app/tokenize.py

# --- write detect_lang.py ---
cat > /app/detect_lang.py <<'PYEOF'
#!/usr/bin/env python3
"""detect_lang.py -- clean-room dataset stage 5.

Flags English-language documents in a mixed-language JSONL corpus.  For each
row with a `doc_id`, detects the language of its text field and records
True when the document is English and False otherwise:

    {"<doc_id>": true-or-false, ...}

Detection is performed on the raw text with the `langdetect` heuristic
sampler.  Documents with fewer than 3 non-space characters, non-string text,
or text that cannot be attributed to any language are flagged as NOT English.
"""
import argparse
import json
import sys


def is_english(text):
    if not isinstance(text, str):
        return False
    t = text.strip()
    if len(t) < 3:
        return False
    try:
        from langdetect import detect
        return detect(t) == "en"
    except Exception:
        return False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True)
    ap.add_argument("--output", required=True)
    ap.add_argument("--text-field", default="text")
    a = ap.parse_args()

    flags = {}
    with open(a.input, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
            except json.JSONDecodeError:
                continue
            if not isinstance(row, dict):
                continue
            did = row.get("doc_id")
            if did is None:
                continue
            flags[str(did)] = is_english(row.get(a.text_field))

    with open(a.output, "w", encoding="utf-8") as fh:
        json.dump(flags, fh, indent=2)


if __name__ == "__main__":
    main()

PYEOF
chmod +x /app/detect_lang.py

# --- write bpe.py ---
cat > /app/bpe.py <<'PYEOF'
#!/usr/bin/env python3
"""bpe.py -- clean-room dataset stage 4.

Trains a byte-pair-encoding tokenizer to a bounded vocabulary with fully
deterministic merge priorities, and writes a BPE model description to the
requested output as JSON:

    {
      "vocab_size":         final vocabulary size,
      "target_vocab_size":  requested bound,
      "corpus_chars":       number of characters in the corpus text,
      "num_merges":         number of recorded merge operations,
      "merges":             ordered list of [left, right, merged] triples
    }

Input is either a raw text file or (with --text-field) a JSONL file whose
named column is read row by row; the corpus text is the concatenation of the
documents joined with a newline.

Merge priority (deterministic by construction):
  1. count every adjacent symbol pair across the whole corpus token sequence;
  2. the highest-count pair is merged (all of its occurrences at once);
  3. among pairs tied at the maximum count, the one whose FIRST occurrence in
     the corpus token sequence is earliest wins; a remaining tie is broken by
     the pair's lexicographic order;
  4. merging a chosen pair yields a new symbol equal to the concatenation and
     continues until the vocabulary reaches the bound or no pairs remain.

Edge behaviour: an empty corpus yields zero merges and vocabulary size 0; a
target bound that is already reached by the initial character alphabet yields
an empty merge list and a vocabulary equal to the number of distinct
characters.
"""
import argparse
import json


def run_bpe(corpus, target):
    tokens = list(corpus)
    vocab = set(tokens)
    merges = []
    while len(vocab) < target:
        pairs = {}
        for i in range(len(tokens) - 1):
            p = (tokens[i], tokens[i + 1])
            pairs[p] = pairs.get(p, 0) + 1
        if not pairs:
            break
        maxfreq = max(pairs.values())
        cand = [p for p, f in pairs.items() if f == maxfreq]
        if len(cand) == 1:
            chosen = cand[0]
        else:
            first = {}
            for i in range(len(tokens) - 1):
                p = (tokens[i], tokens[i + 1])
                if p not in first:
                    first[p] = i
            chosen = min(cand, key=lambda p: (first.get(p, 10 ** 9), p))
        a, b = chosen
        new_sym = a + b
        vocab.add(new_sym)
        merges.append([a, b, new_sym])
        newt = []
        i = 0
        while i < len(tokens):
            if i + 1 < len(tokens) and tokens[i] == a and tokens[i + 1] == b:
                newt.append(new_sym)
                i += 2
            else:
                newt.append(tokens[i])
                i += 1
        tokens = newt
    return merges, len(vocab), len(corpus)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True)
    ap.add_argument("--vocab-size", type=int, default=400)
    ap.add_argument("--text-field", default=None)
    ap.add_argument("--output", required=True)
    a = ap.parse_args()

    if a.text_field:
        rows = [json.loads(l) for l in open(a.input, encoding="utf-8") if l.strip()]
        texts = [r[a.text_field] for r in rows
                 if isinstance(r, dict) and a.text_field in r]
        corpus = "\n".join(texts)
    else:
        corpus = open(a.input, encoding="utf-8").read()

    merges, vsize, nchars = run_bpe(corpus, a.vocab_size)
    with open(a.output, "w", encoding="utf-8") as fh:
        json.dump({
            "vocab_size": vsize,
            "target_vocab_size": a.vocab_size,
            "corpus_chars": nchars,
            "num_merges": len(merges),
            "merges": merges,
        }, fh, indent=2)
    print("bpe: vocab_size=%d target=%d merges=%d chars=%d"
          % (vsize, a.vocab_size, len(merges), nchars))


if __name__ == "__main__":
    main()

PYEOF
chmod +x /app/bpe.py

# --- write fetch_leaderboard.py ---
cat > /app/fetch_leaderboard.py <<'PYEOF'
#!/usr/bin/env python3
"""fetch_leaderboard.py -- clean-room dataset stage 7.

Reaches the online leaderboard source at runtime and emits the model
identifier of the top row (highest mean task score) to the output file.

The leaderboard page is referenced by a URL.  The same table is mirrored
locally in :data/leaderboard.html: as an offline snapshot.  The script first
attempts to fetch the live URL (short timeout); if the fetch fails, times out,
or returns no parseable rows, it falls back to the offline mirror.  The table
is an HTML <table> whose body rows look like::

    <tr><td class="model">garnet-7b</td><td class="score">68.4</td></tr>

The top row is the one with the largest numeric mean task score; its model
identifier is written verbatim (trailing newline) to the output file.
"""
import argparse
import os
import re
import sys

DEFAULT_URL_FILE = "/app/data/leaderboard_url.txt"
DEFAULT_MIRROR = "/app/data/leaderboard.html"
DEFAULT_OUT = "/app/leaderboard_top.txt"


def fetch(url):
    import requests
    try:
        r = requests.get(url, timeout=6)
        if r.status_code == 200 and r.text.strip():
            return r.text
    except Exception as exc:  # noqa: BLE001
        print("warn: live fetch failed (%s): %r" % (url, exc), file=sys.stderr)
    return None


def parse_top(html):
    rows = []
    for m in re.finditer(
            r"<tr>\s*<td[^>]*class=\"model\"[^>]*>([^<]+)</td>\s*"
            r"<td[^>]*class=\"score\"[^>]*>([0-9]+(?:\.[0-9]+)?)</td>\s*</tr>",
            html):
        rows.append((float(m.group(2)), m.group(1).strip()))
    if not rows:
        raise ValueError("no model rows parsed from leaderboard table")
    return max(rows)[1]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url-file", default=DEFAULT_URL_FILE)
    ap.add_argument("--mirror", default=DEFAULT_MIRROR)
    ap.add_argument("--output", default=DEFAULT_OUT)
    a = ap.parse_args()

    url = None
    if os.path.exists(a.url_file):
        with open(a.url_file, encoding="utf-8") as fh:
            url = fh.read().strip()

    html = None
    if url:
        html = fetch(url)
    if html is None:
        with open(a.mirror, encoding="utf-8") as fh:
            html = fh.read()

    top = parse_top(html)
    with open(a.output, "w", encoding="utf-8") as fh:
        fh.write(top + "\n")
    print("top model: %s" % top)


if __name__ == "__main__":
    main()

PYEOF
chmod +x /app/fetch_leaderboard.py

# --- write /app/tasks.yaml (multi-choice logprobs task config) ---
cat > /app/tasks.yaml <<'YEOF'
# Task configuration for the clean-room multi-choice logprobs harness.
# Registered so /app/harness/eval_harness.py can load it by this filename.
quartz-article-sections:
  query_column: query
  title_column: title
  gold_column: gold
  label_set: ["Politics", "Science", "Culture", "Sports"]
  prompt_template: "Assign the document to its explicit section. Document query: {query}\nDocument title: {title}\n\nAvailable sections:\n{options}\n\nProvide the single section label."
  metric: multiple_choice_accuracy

YEOF

echo "== stage 1: locale filter =="
python3 /app/filter_locale.py \
    --input /app/data/news_corpus.jsonl \
    --locale EN \
    --columns doc_id,title,text,query,gold \
    --output /app/locale.jsonl

echo "== stage 2: fetch offline model + tokenizer assets =="
python3 - <<'PYEOF'
import json
import os
from huggingface_hub import snapshot_download

model_dir = "/app/offline_assets/model"
os.makedirs(model_dir, exist_ok=True)
snapshot_download("prajjwal1/bert-tiny", local_dir=model_dir)

# The bert-tiny repo ships without explicit model_type / tokenizer_config;
# write minimal standard shims so the offline AutoTokenizer/AutoModel
# loading resolves deterministically with no further download.# resolves deterministically with no further download.
with open(os.path.join(model_dir, "config.json"), encoding="utf-8") as fh:
    cfg = json.load(fh)
cfg["model_type"] = "bert"
with open(os.path.join(model_dir, "config.json"), "w", encoding="utf-8") as fh:
    json.dump(cfg, fh, indent=2)
with open(os.path.join(model_dir, "tokenizer_config.json"), "w", encoding="utf-8") as fh:
    json.dump({
        "tokenizer_class": "BertTokenizer",
        "do_lower_case": True,
        "clean_up_tokenization_spaces": True,
    }, fh, indent=2)
print("offline assets ready at", model_dir)
PYEOF

echo "== stage 3: tokenize with the offline tokenizer =="
python3 /app/tokenize.py \
    --input /app/locale.jsonl \
    --output /app/token_counts.json \
    --model /app/offline_assets/model \
    --field text

echo "== stage 4: deterministic BPE to bounded vocabulary =="
python3 /app/bpe.py \
    --input /app/locale.jsonl \
    --vocab-size 400 \
    --text-field text \
    --output /app/bpe_model.json

echo "== stage 5: English detection flags over the mixed corpus =="
python3 /app/detect_lang.py \
    --input /app/data/news_corpus.jsonl \
    --output /app/lang_flags.json \
    --text-field text

echo "== stage 6: register the multi-choice harness task config =="
python3 /app/harness/eval_harness.py \
    --task /app/tasks.yaml \
    --data /app/data/eval_dev.jsonl \
    --out /app/eval_results.jsonl

echo "== stage 7: reach the live leaderboard source, emit top model =="
python3 /app/fetch_leaderboard.py

echo "== deliverables =="
ls -la /app
echo "quartz-dial build complete"
