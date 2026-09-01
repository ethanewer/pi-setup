#!/usr/bin/env python3
"""Independent verifier for task quartz-dial.

Re-runs every deliverable and independently cross-checks each stage against a
hidden suite mounted at /tests/hidden:

  stage 1 filter_locale.py  - re-run on the visible corpus + a hidden corpus,
                              assert exact columns and locale membership.
  stage 2 offline_assets/   - AutoTokenizer + AutoModel must load from the
                              local directory with network disabled.
  stage 3 tokenize.py       - recompute token counts with the same tokenizer;
                              hidden fresh + empty inputs.
  stage 4 bpe.py            - independent recompute of the documented merge
                              priorities; bound, equality, determinism; hidden
                              normal / empty / tiny-bound corpora.
  stage 5 detect_lang.py    - run on a hidden multi-language held set, compare
                              flags to the gold set at per-language + overall
                              accuracy thresholds; consistency on the corpus.
  stage 6 tasks.yaml        - structural contract, registration load, hidden
                              query/title data with golden score windows.
  stage 7 leaderboard_top   - independently parse the mirror; re-run the fetch.

Prints REWARD=0 or REWARD=1 to stdout; the outer test.sh persists it.
"""
import json
import os
import re
import subprocess
import sys
import yaml

APP = "/app"
HALL = "/tests/hidden"
failures = []


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def readj(path):
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def read_jsonl(path):
    rows = []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if line:
                rows.append(json.loads(line))
    return rows


# ---------------------------------------------------------------------------
# stage 1: locale filter
# ---------------------------------------------------------------------------
def stage_filter():
    hcols = "doc_id,title,text,query,gold"
    # (a) visible corpus -> recompute /app/locale.jsonl
    r = run(["python3", "/app/filter_locale.py",
             "--input", "/app/data/news_corpus.jsonl", "--locale", "EN",
             "--columns", hcols,
             "--output", "/tmp/v_locale.jsonl"])
    if r.returncode != 0:
        failures.append("filter: visible recompute rc=%s %s"
                        % (r.returncode, r.stderr[-300:]))
        return
    got = read_jsonl("/tmp/v_locale.jsonl")
    want = read_jsonl("/app/locale.jsonl")
    if got != want:
        failures.append("filter: /app/locale.jsonl != recomputed locale.jsonl")
    if len(got) != 44:
        failures.append("filter: visible locale subset row count %d != 44"
                        % len(got))
    for row in got:
        if list(row.keys()) != hcols.split(","):
            failures.append("filter: visible locale columns %r" % list(row.keys()))

    # (b) hidden corpus with blank/malformed/no-locale rows
    r = run(["python3", "/app/filter_locale.py",
             "--input", os.path.join(HALL, "filter", "input.jsonl"),
             "--locale", "EN", "--columns", hcols,
             "--output", "/tmp/v_hidden_locale.jsonl"])
    if r.returncode != 0:
        failures.append("filter hidden: rc=%s %s"
                        % (r.returncode, (r.stderr or "")[-300:]))
        return
    out = read_jsonl("/tmp/v_hidden_locale.jsonl")
    expect = []
    with open(os.path.join(HALL, "filter", "input.jsonl"), encoding="utf-8") as fh:
        for raw in fh:
            raw = raw.strip()
            if not raw:
                continue
            try:
                row = json.loads(raw)
            except json.JSONDecodeError:
                continue
            if not isinstance(row, dict):
                continue
            if str(row.get("locale", "")).strip().lower() != "en":
                continue
            expect.append({c: row.get(c) for c in hcols.split(",")})
    if out != expect:
        failures.append("filter hidden: agent output != independent recompute")
    for row in out:
        if list(row.keys()) != hcols.split(","):
            failures.append("filter hidden: unexpected columns %r"
                            % list(row.keys()))
    # (c) empty match on a nonexistent locale is a valid empty file
    r = run(["python3", "/app/filter_locale.py",
             "--input", os.path.join(HALL, "filter", "input.jsonl"),
             "--locale", "XX", "--columns", hcols,
             "--output", "/tmp/v_hidden_empty.jsonl"])
    out = read_jsonl("/tmp/v_hidden_empty.jsonl") if os.path.getsize(
        "/tmp/v_hidden_empty.jsonl") or True else []
    if r.returncode != 0:
        failures.append("filter hidden empty: rc=%s" % r.returncode)
    elif out != []:
        failures.append("filter hidden: empty-locale match not empty: %r" % out)


# ---------------------------------------------------------------------------
# stage 2: offline assets
# ---------------------------------------------------------------------------
OFFLINE_ASSET_FILES = ["config.json", "tokenizer_config.json", "vocab.txt",
                       "pytorch_model.bin"]


def stage_offline():
    model_dir = os.path.join(APP, "offline_assets", "model")
    if not os.path.isdir(model_dir):
        failures.append("offline: %s missing" % model_dir)
        return
    for f in OFFLINE_ASSET_FILES:
        if not os.path.isfile(os.path.join(model_dir, f)):
            failures.append("offline: missing %s/%s" % (model_dir, f))
    code = (
        "import os\n"
        "os.environ['HF_HUB_OFFLINE']='1'\n"
        "os.environ['TRANSFORMERS_OFFLINE']='1'\n"
        "os.environ['HF_DATASETS_OFFLINE']='1'\n"
        "from transformers import AutoConfig, AutoTokenizer, AutoModel\n"
        "m=%r\n"
        "c=AutoConfig.from_pretrained(m)\n"
        "assert getattr(c,'model_type','')=='bert'\n"
        "t=AutoTokenizer.from_pretrained(m)\n"
        "assert len(t.tokenize('the mayor approved the transit budget'))>0\n"
        "model=AutoModel.from_pretrained(m)\n"
        "print('OFFLINE_LOAD_OK')\n" % model_dir)
    r = run(["python3", "-c", code])
    if r.returncode != 0 or "OFFLINE_LOAD_OK" not in r.stdout:
        failures.append("offline: AutoTokenizer/AutoModel loading failed "
                        "(rc=%s): %s" % (r.returncode, (r.stderr or "")[-400:]))


# ---------------------------------------------------------------------------
# stage 3: tokenize
# ---------------------------------------------------------------------------
def recompute_token_counts(path):
    import transformers
    tok = transformers.AutoTokenizer.from_pretrained(
        os.path.join(APP, "offline_assets", "model"))
    total = docs = 0
    unique = set()
    with open(path, encoding="utf-8") as fh:
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
            text = row.get("text")
            toks = tok.tokenize(text) if isinstance(text, str) and text else []
            total += len(toks)
            unique.update(toks)
            docs += 1
    return {"total_tokens": total, "documents": docs,
            "unique_tokens": len(unique),
            "avg_tokens_per_doc": int(round(total / docs)) if docs else 0}


def stage_tokenize():
    m = os.path.join(APP, "offline_assets", "model")
    # (a) visible: delivered token_counts.json == fresh run == independent recompute
    r = run(["python3", "/app/tokenize.py",
             "--input", "/app/locale.jsonl", "--output", "/tmp/v_tc.json",
             "--model", m, "--field", "text"])
    if r.returncode != 0:
        failures.append("tokenize: visible run rc=%s %s"
                        % (r.returncode, (r.stderr or "")[-300:]))
    else:
        fresh = readj("/tmp/v_tc.json")
        if fresh != readj("/app/token_counts.json"):
            failures.append("tokenize: /app/token_counts.json != fresh run")
        indep = recompute_token_counts("/app/locale.jsonl")
        if fresh != indep:
            failures.append("tokenize: fresh != independent recompute %r vs %r"
                            % (fresh, indep))

    # (b) hidden fresh input
    hin = os.path.join(HALL, "tokenize", "input.jsonl")
    r = run(["python3", "/app/tokenize.py", "--input", hin,
             "--output", "/tmp/v_h_tok.json", "--model", m, "--field", "text"])
    if r.returncode != 0:
        failures.append("tokenize hidden: rc=%s %s"
                        % (r.returncode, (r.stderr or "")[-300:]))
    else:
        got = readj("/tmp/v_h_tok.json")
        indep = recompute_token_counts(hin)
        if got != indep:
            failures.append("tokenize hidden: output != independent recompute")
        if got["documents"] != 5:
            failures.append("tokenize hidden: expected 5 documents, got %d"
                            % got["documents"])

    # (c) hidden empty input
    r = run(["python3", "/app/tokenize.py",
             "--input", os.path.join(HALL, "tokenize", "empty.jsonl"),
             "--output", "/tmp/v_h_tok_empty.json", "--model", m,
             "--field", "text"])
    if r.returncode != 0:
        failures.append("tokenize hidden empty: rc=%s" % r.returncode)
    else:
        got = readj("/tmp/v_h_tok_empty.json")
        if got != {"total_tokens": 0, "documents": 0, "unique_tokens": 0,
                   "avg_tokens_per_doc": 0}:
            failures.append("tokenize hidden empty: unexpected %r" % got)


# ---------------------------------------------------------------------------
# stage 4: BPE
# ---------------------------------------------------------------------------
def canonical_bpe(corpus, target):
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


def corpus_of(path, field=None):
    if field:
        rows = read_jsonl(path)
        texts = [r[field] for r in rows if isinstance(r, dict) and field in r]
        return "\n".join(texts)
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def stage_bpe():
    # (a) visible: /app/bpe_model.json matches an independent recompute + rerun
    corpus = corpus_of("/app/locale.jsonl", "text")
    exp_merges, exp_vsize, _ = canonical_bpe(corpus, 400)
    try:
        bpe = readj("/app/bpe_model.json")
    except Exception as exc:
        failures.append("bpe: /app/bpe_model.json unreadable %r" % exc)
        return
    r = run(["python3", "/app/bpe.py", "--input", "/app/locale.jsonl",
             "--vocab-size", "400", "--text-field", "text",
             "--output", "/tmp/v_bpe.json"])
    if r.returncode != 0:
        failures.append("bpe: rerun rc=%s %s"
                        % (r.returncode, (r.stderr or "")[-300:]))
    else:
        fresh = readj("/tmp/v_bpe.json")
        if fresh["merges"] != exp_merges:
            failures.append("bpe: rerun merges != independent recompute")
        if fresh != bpe:
            failures.append("bpe: /app/bpe_model.json != rerun")
    if bpe.get("target_vocab_size") != 400:
        failures.append("bpe: target_vocab_size != 400")
    if not (100 <= bpe.get("vocab_size", 0) <= 400):
        failures.append("bpe: vocabulary bound violated: %r"
                        % bpe.get("vocab_size"))
    if bpe["merges"] != exp_merges:
        failures.append("bpe: /app/bpe_model.json merges != independent "
                        "recompute (%d vs %d)" % (len(bpe["merges"]),
                                                  len(exp_merges)))

    # (b) hidden fresh text corpus
    hin = os.path.join(HALL, "bpe", "corpus.txt")
    r1 = run(["python3", "/app/bpe.py", "--input", hin,
              "--vocab-size", "90", "--output", "/tmp/v_h_bpe1.json"])
    r2 = run(["python3", "/app/bpe.py", "--input", hin,
              "--vocab-size", "90", "--output", "/tmp/v_h_bpe2.json"])
    if r1.returncode != 0 or r2.returncode != 0:
        failures.append("bpe hidden: rc %s/%s" % (r1.returncode, r2.returncode))
    else:
        a = readj("/tmp/v_h_bpe1.json")
        b = readj("/tmp/v_h_bpe2.json")
        if a != b:
            failures.append("bpe hidden: not deterministic across two runs")
        if not (0 < a["vocab_size"] <= 90):
            failures.append("bpe hidden: bound violated %r" % a["vocab_size"])
        exp_merges, exp_vsize, _ = canonical_bpe(corpus_of(hin), 90)
        if a["merges"] != exp_merges or a["vocab_size"] != exp_vsize:
            failures.append("bpe hidden: merges != independent recompute")

    # (c) hidden empty + tiny-bound edges
    r = run(["python3", "/app/bpe.py", "--input",
             os.path.join(HALL, "bpe", "empty.txt"),
             "--vocab-size", "50", "--output", "/tmp/v_h_bpe_empty.json"])
    if r.returncode != 0:
        failures.append("bpe hidden empty: rc=%s" % r.returncode)
    else:
        e = readj("/tmp/v_h_bpe_empty.json")
        if e["vocab_size"] != 0 or e["merges"] or e["corpus_chars"] != 0:
            failures.append("bpe hidden empty: unexpected %r" % e)
    r = run(["python3", "/app/bpe.py", "--input",
             os.path.join(HALL, "bpe", "tiny.txt"),
             "--vocab-size", "1", "--output", "/tmp/v_h_bpe_tiny.json"])
    if r.returncode != 0:
        failures.append("bpe hidden tiny: rc=%s" % r.returncode)
    else:
        t = readj("/tmp/v_h_bpe_tiny.json")
        if t["vocab_size"] != 2 or t["merges"]:
            failures.append("bpe hidden tiny: unexpected %r" % t)


# ---------------------------------------------------------------------------
# stage 5: English detection
# ---------------------------------------------------------------------------
def stage_lang():
    # (a) consistency on the visible corpus
    r = run(["python3", "/app/detect_lang.py",
             "--input", "/app/data/news_corpus.jsonl",
             "--output", "/tmp/v_flags.json", "--text-field", "text"])
    if r.returncode != 0:
        failures.append("lang: visible run rc=%s %s"
                        % (r.returncode, (r.stderr or "")[-300:]))
    else:
        fresh = readj("/tmp/v_flags.json")
        try:
            delivered = readj("/app/lang_flags.json")
        except Exception:
            delivered = None
            failures.append("lang: /app/lang_flags.json unreadable")
        if delivered != fresh:
            failures.append("lang: /app/lang_flags.json != fresh run")

    # (b) hidden held-set accuracy, overall + per-language
    hin = os.path.join(HALL, "lang_held", "corpus.jsonl")
    gold = readj(os.path.join(HALL, "lang_held", "gold.json"))
    r = run(["python3", "/app/detect_lang.py", "--input", hin,
             "--output", "/tmp/v_held_flags.json", "--text-field", "text"])
    if r.returncode != 0:
        failures.append("lang hidden: rc=%s %s"
                        % (r.returncode, (r.stderr or "")[-300:]))
        return
    flags = readj("/tmp/v_held_flags.json")
    expected_english = gold
    presented = {d: bool(flags.get(d, False)) for d in gold}
    overall = sum(1 for d in gold if presented[d] == expected_english[d]) / len(gold)
    groups = {}
    for did in gold:
        key = did.split("-")[1] if "-" in did else "held"
        groups.setdefault(key, [0, 0])
        groups[key][0] += int(presented[did] == expected_english[did])
        groups[key][1] += 1
    per_lang = {k: c[0] / c[1] for k, c in groups.items()}
    if overall < 0.90:
        failures.append("lang hidden: overall accuracy %.3f < 0.90" % overall)
    for k, acc in sorted(per_lang.items()):
        if acc < 0.80:
            failures.append("lang hidden: %s accuracy %.3f < 0.80" % (k, acc))
    en_gold = [d for d in gold if gold[d]]
    if en_gold:
        en_acc = sum(1 for d in en_gold if presented[d]) / len(en_gold)
        if en_acc < 0.85:
            failures.append("lang hidden: english recall %.3f < 0.85" % en_acc)

    # (c) edge: rows without doc_id must not crash
    r = run(["python3", "/app/detect_lang.py",
             "--input", os.path.join(HALL, "tokenize", "input.jsonl"),
             "--output", "/tmp/v_edge_flags.json", "--text-field", "text"])
    if r.returncode != 0:
        failures.append("lang edge: rc=%s" % r.returncode)


# ---------------------------------------------------------------------------
# stage 6: harness task config
# ---------------------------------------------------------------------------
MANDATED_PROMPT = ("Assign the document to its explicit section. "
                   "Document query: {query}\n"
                   "Document title: {title}\n\n"
                   "Available sections:\n{options}\n\n"
                   "Provide the single section label.")
FIXED_LABELS = ["Politics", "Science", "Culture", "Sports"]


def stage_harness():
    with open(os.path.join(APP, "tasks.yaml"), encoding="utf-8") as fh:
        raw = yaml.safe_load(fh)
    if not isinstance(raw, dict) or len(raw) != 1:
        failures.append("harness: tasks.yaml must define exactly one task")
        return
    name, cfg = next(iter(raw.items()))
    if name != "quartz-article-sections":
        failures.append("harness: registered task id %r" % name)
    if cfg.get("query_column") != "query" or cfg.get("title_column") != "title":
        failures.append("harness: column mapping wrong %r" % cfg)
    if cfg.get("gold_column") != "gold":
        failures.append("harness: gold_column %r" % cfg.get("gold_column"))
    if cfg.get("label_set") != FIXED_LABELS:
        failures.append("harness: label_set %r" % cfg.get("label_set"))
    if cfg.get("prompt_template") != MANDATED_PROMPT:
        failures.append("harness: prompt_template != mandated template")
    if cfg.get("metric", "") != "multiple_choice_accuracy":
        failures.append("harness: metric %r" % cfg.get("metric"))

    # registration load on the dev set
    r = run(["python3", "/app/harness/eval_harness.py",
             "--task", "/app/tasks.yaml",
             "--data", "/app/data/eval_dev.jsonl",
             "--out", "/tmp/v_reg_res.jsonl"])
    if r.returncode != 0:
        failures.append("harness: registration run rc=%s %s"
                        % (r.returncode, (r.stderr or "")[-300:]))
        return
    if "task 'quartz-article-sections' loaded" not in r.stdout:
        failures.append("harness: registration did not confirm task load")

    # hidden query/title data with prediction scores -> metric windows
    r = run(["python3", "/app/harness/eval_harness.py",
             "--task", "/app/tasks.yaml",
             "--data", os.path.join(HALL, "eval", "data.jsonl"),
             "--predictions", os.path.join(HALL, "eval", "predictions.jsonl"),
             "--out", "/tmp/v_h_eval.jsonl"])
    if r.returncode != 0:
        failures.append("harness hidden: rc=%s %s"
                        % (r.returncode, (r.stderr or "")[-300:]))
        return
    lines = [json.loads(l) for l in open("/tmp/v_h_eval.jsonl", encoding="utf-8")
             if l.strip()]
    metrics = lines[-1]
    docs = lines[:-1]
    data = read_jsonl(os.path.join(HALL, "eval", "data.jsonl"))
    preds = {p["doc_id"]: p["scores"]
             for p in read_jsonl(os.path.join(HALL, "eval", "predictions.jsonl"))}
    n_corr = 0
    per_label = {l: [0, 0] for l in FIXED_LABELS}
    for row in data:
        g = row["gold"]
        gl = FIXED_LABELS[g]
        chosen_i = max(range(4), key=lambda i: preds[row["doc_id"]][i])
        if chosen_i == g:
            n_corr += 1
        per_label[gl][1] += 1
        per_label[gl][0] += int(chosen_i == g)
    exp_overall = n_corr / len(data)
    exp_per = {l: (c[0] / c[1] if c[1] else 0.0) for l, c in per_label.items()}
    exp_macro = sum(exp_per.values()) / len(exp_per)
    if abs(metrics["overall_accuracy"] - exp_overall) > 1e-9:
        failures.append("harness hidden: overall window %.4f != %.4f"
                        % (metrics["overall_accuracy"], exp_overall))
    if abs(metrics["macro_accuracy"] - exp_macro) > 1e-9:
        failures.append("harness hidden: macro window %.4f != %.4f"
                        % (metrics["macro_accuracy"], exp_macro))
    for l in FIXED_LABELS:
        if abs(metrics["per_label_accuracy"].get(l, -1) - exp_per[l]) > 1e-9:
            failures.append("harness hidden: per-label %s window wrong"
                            % l)
    for d, row in zip(docs, data):
        gl = FIXED_LABELS[row["gold"]]
        if d["gold_label"] != gl or d["gold_index"] != row["gold"]:
            failures.append("harness hidden: gold selection wrong %r" % d)
        prompt = d.get("prompt")
        if prompt is None:
            failures.append("harness hidden: no prompt embedded for a doc")
            continue
        if row["query"] not in prompt or row["title"] not in prompt:
            failures.append("harness hidden: prompt misses query/title")
        for lab in FIXED_LABELS:
            if lab not in prompt:
                failures.append("harness hidden: prompt misses a label")


# ---------------------------------------------------------------------------
# stage 7: leaderboard
# ---------------------------------------------------------------------------
def parse_leaderboard(html):
    rows = []
    for m in re.finditer(
            r"<tr>\s*<td[^>]*class=\"model\"[^>]*>([^<]+)</td>\s*"
            r"<td[^>]*class=\"score\"[^>]*>([0-9]+(?:\.[0-9]+)?)</td>\s*</tr>",
            html):
        rows.append((float(m.group(2)), m.group(1).strip()))
    if not rows:
        raise ValueError("no model rows")
    return max(rows)[1]


def stage_leaderboard():
    html = open(os.path.join(APP, "data", "leaderboard.html"),
                encoding="utf-8").read()
    expected = parse_leaderboard(html)
    try:
        top = open(os.path.join(APP, "leaderboard_top.txt"),
                   encoding="utf-8").read().strip()
    except OSError as exc:
        failures.append("leaderboard: missing deliverable %r" % exc)
        return
    if top != expected:
        failures.append("leaderboard: delivered top %r != %r" % (top, expected))
    r = run(["python3", "/app/fetch_leaderboard.py", "--output", "/tmp/v_top.txt"])
    if r.returncode != 0:
        failures.append("leaderboard: fetch rerun rc=%s %s"
                        % (r.returncode, (r.stderr or "")[-300:]))
    else:
        again = open("/tmp/v_top.txt", encoding="utf-8").read().strip()
        if again != expected:
            failures.append("leaderboard: rerun top %r != %r" % (again, expected))
    r = run(["python3", "/app/fetch_leaderboard.py",
             "--url-file", os.path.join(HALL, "leaderboard", "missing-url.txt"),
             "--mirror", os.path.join(HALL, "leaderboard", "leaderboard.html"),
             "--output", "/tmp/v_alt_top.txt"])
    if r.returncode != 0:
        failures.append("leaderboard hidden: rc=%s %s"
                        % (r.returncode, (r.stderr or "")[-200:]))
    else:
        alt_html = open(os.path.join(HALL, "leaderboard", "leaderboard.html"),
                        encoding="utf-8").read()
        alt_exp = parse_leaderboard(alt_html)
        if open("/tmp/v_alt_top.txt", encoding="utf-8").read().strip() != alt_exp:
            failures.append("leaderboard hidden: alternate mirror top wrong")


# ---------------------------------------------------------------------------
MISSING = ["/app/filter_locale.py", "/app/locale.jsonl", "/app/offline_assets/",
           "/app/tokenize.py", "/app/token_counts.json", "/app/bpe.py",
           "/app/bpe_model.json", "/app/detect_lang.py", "/app/lang_flags.json",
           "/app/tasks.yaml", "/app/fetch_leaderboard.py",
           "/app/leaderboard_top.txt"]


def main():
    for p in MISSING:
        if not os.path.exists(p):
            failures.append("missing deliverable %s" % p)

    stage_filter()
    stage_offline()
    stage_tokenize()
    stage_bpe()
    stage_lang()
    stage_harness()
    stage_leaderboard()

    if failures:
        print("REWARD=0")
        for f in failures:
            print("  -", f, file=sys.stderr)
        return 1
    print("REWARD=1")
    return 0


if __name__ == "__main__":
    sys.exit(main())
