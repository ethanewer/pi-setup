#!/usr/bin/env python3
"""Cedar-cipher verifier. Independent re-derivation of every deliverable and
hidden case. Exits 0 iff every check passes; prints a summary."""
import glob, importlib.util, json, os, shutil, subprocess, sys
from collections import Counter

FAIL = []
HALL = "/tests/hidden"


def fail(msg):
    FAIL.append(msg)
    print("  FAIL:", msg)


def check(cond, msg):
    if not cond:
        fail(msg)
    return bool(cond)


def show(msg):
    print("  ok:", msg)


# ----------------------------------------------------------------- helpers
def read_json(p):
    with open(p, encoding="utf-8") as f:
        return json.load(f)


def run(cmd, timeout=180):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)


# ---- independent BPE (mirrors the task contract, NOT the oracle code)
def train_bpe(words, cap):
    seqs = [list(w) for w in words]
    vocab = set()
    for w in words:
        vocab.update(w)
    if len(vocab) >= cap:
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
            out, i = [], 0
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
    toks = list(text)
    for a, b in merges:
        out, i, n = [], 0, len(toks)
        while i < n:
            if i + 1 < n and toks[i] == a and toks[i + 1] == b:
                out.append(a + b)
                i += 2
            else:
                out.append(toks[i])
                i += 1
        toks = out
    return toks


def load_merges_only(path):
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    return [tuple(m) for m in data.get("merges", [])]

# aliases so later prose reads naturally
read_json1 = read_json
enc = encode


# ------------------------------------------------------- deliverable presence
REQ = [
    "/app/filter_locale.py",
    "/app/locale.jsonl",
    "/app/cedar_tokenizer.py",
    "/app/train_bpe.py",
    "/app/bpe_model.json",
    "/app/tokenize.py",
    "/app/token_counts.json",
    "/app/detect_lang.py",
    "/app/lang_flags.json",
    "/app/offline_assets/loader.py",
    "/app/offline_assets/config.json",
    "/app/offline_assets/tokenizer.json",
    "/app/offline_assets/model_weights.npz",
    "/app/tasks.yaml",
    "/app/run_mcq.py",
    "/app/mcq_result.json",
    "/app/fetch_leaderboard.py",
    "/app/leaderboard_top.txt",
]
absent = [p for p in REQ if not os.path.isfile(p)]
sys.exitcode = 0
rc = 0
# (placeholder; we report via rc at end; fail() accumulates)

# Early abort: missing deliverables -> reward 0
if absent:
    for p in absent:
        print("  MISSING DELIVERABLE:", p)
    print("VERDICT 0 (missing deliverables)")
    rc = 1
else:
    print("deliverables present: %d files" % len(REQ))

if absent:
    sys.exit(rc)

# ===================================================================== 1. locale
print("== 1. locale filter (C-6dcccfe8) ==")
# main deliverable vs independent read of /app/corpus.jsonl
F_LOC = {"locale": "es", "cols": ["id", "primary", "secondary"]}
exp_cols = set(F_LOC["cols"])
got = []
with open("/app/locale.jsonl", encoding="utf-8") as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        got.append(json.loads(line))
src = []
with open("/app/corpus.jsonl", encoding="utf-8") as f:
    for line in f:
        if line.strip():
            src.append(json.loads(line))
exp_rows = [r for r in src if r.get("locale") == "es"]
check(len(got) == len(exp_rows),
      "locale.jsonl row count %d != expected %d" % (len(got), len(exp_rows)))
cols_ok = all(set(g.keys()) == exp_cols for g in got)
check(cols_ok, "locale.jsonl columns must be exactly {id,primary,secondary}")
ids_ok = set(g["id"] for g in got) == set(r["id"] for r in exp_rows)
check(ids_ok, "locale.jsonl membership (id set) mismatch")
# execute filter deliverable on a live fresh slice and re-verify the script
tmp = "/tmp/v_loc.jsonl"
r = run(["python3", "/app/filter_locale.py",
         "--input", "/app/corpus.jsonl", "--locale", "es",
         "--columns", "id,primary,secondary", "--output", tmp])
check(r.returncode == 0, "filter_locale.py live run failed")
got2 = [json.loads(l) for l in open(tmp, encoding="utf-8") if l.strip()]
check(len(got2) == len(exp_rows), "filter live re-derivation row mismatch")

# ------------------------------------------------------------------ hidden
h = os.path.join(HALL, "filter_hp.jsonl")
if os.path.isfile(h):
    hp = [json.loads(l) for l in open(h, encoding="utf-8") if l.strip()]
    out = "/tmp/hp.jsonl"
    r = run(["python3", "/app/filter_locale.py", "--input", h,
             "--locale", "de", "--columns", "id,primary", "--output", out])
    want = [x for x in hp if x.get("locale") == "de"]
    has = [json.loads(l) for l in open(out, encoding="utf-8") if l.strip()]
    check(len(has) == len(want), "hidden filter rows %d != %d" % (len(has), len(want)))
    check(all(set(x.keys()) == {"id", "primary"} for x in has),
          "hidden filter columns wrong")
    check(set(x["id"] for x in has) == set(x["id"] for x in want),
          "hidden filter membership wrong")
    # edge: a requested column missing in some row yields "" not a crash
    for x in has:
        check(isinstance(x["primary"], str), "missing column must be '' compatible")
    # empty dataset
    eh = os.path.join(HALL, "filter_empty.jsonl")
    if os.path.isfile(eh):
        r = run(["python3", "/app/filter_locale.py", "--input", eh,
                 "--locale", "de", "--columns", "id,primary", "--output", "/tmp/em.txt"])
        n = sum(1 for l in open("/tmp/em.txt", encoding="utf-8") if l.strip())
        check(n == 0, "filter on empty dataset must emit 0 lines")

# ===================================================================== 2. offline
print("== 2. offline assets (C-4f563c9d) ==")
os.environ["TRANSFORMERS_OFFLINE"] = "1"
os.environ["HF_HUB_OFFLINE"] = "1"
os.environ["HF_DATASETS_OFFLINE"] = "1"
spec = importlib.util.spec_from_file_location(
    "cedar_loader", "/app/offline_assets/loader.py")
loader = importlib.util.module_from_spec(spec)
spec.loader.exec_module(loader)
off = "/app/offline_assets"
data = loader.load_offline(off)
check(isinstance(data, dict) and set(data) == {"config", "tokenizer", "weights"},
      "loader.load_offline must return {config,tokenizer,weights}")
check(data["config"].get("name"), "config.json must carry a name/architecture")
check(data["tokenizer"].get("merges") is not None, "tokenizer.json must expose merges")
w = data["weights"]
check(len(w) > 0 and all(len(x.shape) == 2 for x in w.values()),
      "model_weights.npz must be a dict of 2-D shards")
# partial mirror must FAIL
stage = "/tmp/off_stage"
shutil.rmtree(stage, ignore_errors=True)
shutil.copytree(off, stage)
os.remove(os.path.join(stage, "model_weights.npz"))
try:
    loader.load_offline(stage)
    fail("loader must reject a partial mirror (missing model_weights.npz)")
except Exception:
    show("partial mirror (model_weights.npz) rejected")
shutil.rmtree(stage, ignore_errors=True)
# tokenizer.load() must be offline-capable: guaranteed by loader, but also smoke
r = run(["python3", "/app/offline_assets/loader.py"])
check(r.returncode == 0 and "OFFLINE_LOAD_OK" in r.stdout,
      "offline_assets/loader.py executable must load offline")

# ===================================================================== 3. tokenize
print("== 3. tokenize (C-5ce284f7) ==")
merges = load_merges_only("/app/offline_assets/tokenizer.json")
# main deliverable: recompute over /app/locale.jsonl
tot = rows = psum = ssum = 0
for g in got:
    tot += len(encode(g.get("primary", ""), merges)) + len(
        encode(g.get("secondary", ""), merges))
    psum += len(encode(g.get("primary", ""), merges))
    ssum += len(encode(g.get("secondary", ""), merges))
    rows += 1
tc = read_json1("/app/token_counts.json")
check(tc["total_tokens"] == tot,
      "token_counts.total_tokens %s != independent %d" % (tc.get("total_tokens"), tot))
check(tc["rows"] == len(got), "token_counts.rows != filtered rows")
check(tc.get("cols") == ["primary", "secondary"], "token_counts.cols wrong")
check(tc["per_col"]["primary"] == psum and tc["per_col"]["secondary"] == ssum,
      "token_counts.per_col mismatch")
# live re-run of the tokenize deliverable
r = run(["python3", "/app/tokenize.py", "--input", "/app/locale.jsonl",
         "--output", "/tmp/tc2.json"])
check(r.returncode == 0 and read_json1("/tmp/tc2.json")["total_tokens"] == tot,
      "tokenize.py live re-run disagrees")
# hidden token rows (different columns/content)
th = os.path.join(HALL, "token_h.jsonl")
if os.path.isfile(th):
    hrows = [json.loads(l) for l in open(th, encoding="utf-8") if l.strip()]
    htot = sum(
        len(encode(x.get("primary", ""), merges)) +
        len(encode(x.get("secondary", ""), merges)) for x in hrows)
    r = run(["python3", "/app/tokenize.py", "--input", th,
             "--output", "/tmp/ht.json"])
    got_h = read_json1("/tmp/ht.json")
    check(r.returncode == 0, "hidden tokenize.py failed to run")
    check(got_h["total_tokens"] == htot,
          "hidden tokenize total_tokens mismatch (got %s want %d)" % (
              got_h.get("total_tokens"), htot))
    check(got_h["rows"] == len(hrows), "hidden tokenize row count mismatch")

# ===================================================================== 4. BPE
print("== 4. train BPE (C-440b0d41) ==")
bpe = read_json1("/app/bpe_model.json")
check(isinstance(bpe.get("cap"), int), "bpe_model.json requires a cap")
check(bpe["vocab_size"] <= bpe["cap"],
      "bpe vocab_size %s exceeds cap %s" % (bpe.get("vocab_size"), bpe.get("cap")))
wc = open("/app/bpe_corpus.txt", encoding="utf-8").read().split()
ref = train_bpe(wc, bpe["cap"])
check(ref["merges"] == bpe["merges"],
      "bpe_model merges diverge from independent deterministic training")
check(ref["vocab_size"] == bpe["vocab_size"], "bpe vocab_size mismatches reference")
# hidden: generalizes to a fresh corpus & a fresh cap
hb = os.path.join(HALL, "bpe_h.txt")
r = run(["python3", "/app/train_bpe.py", "--input", hb,
         "--cap", "40", "--output", "/tmp/bh.json"])
outm = read_json1("/tmp/bh.json")
wref = train_bpe(open(hb, encoding="utf-8").read().split(), 40)
check(r.returncode == 0 and outm["merges"] == wref["merges"],
      "hidden BPE merges disagree with independent reference")
check(outm["vocab_size"] <= 40, "hidden BPE exceeds cap 40")
# hidden edge: cap below single-char distinct count -> bounded, no merges
hb2 = os.path.join(HALL, "bpe_edge.txt")
r = run(["python3", "/app/train_bpe.py", "--input", hb2,
         "--cap", "3", "--output", "/tmp/bpe_e2.json"])
cm_out = read_json1("/tmp/bpe_e2.json")
check(r.returncode == 0 and cm_out["vocab_size"] <= 3 and cm_out["merges"] == [],
      "hidden edge bpe (cap under distinct) must stay bounded with 0 merges")

# ===================================================================== 5. english
print("== 5. english detection (C-29ba058c) ==")
def is_english(content):
    if not any(c.isalpha() for c in content):
        return False
    return all(ord(c) < 0x80 for c in content)

en, ot = [], []
for p in sorted(glob.glob("/app/documents/*.txt")):
    (en if is_english(open(p, encoding="utf-8").read()) else ot).append(
        os.path.basename(p))
lang = read_json1("/app/lang_flags.json")
en.sort(); ot.sort()
check(lang.get("english") == en, "lang_flags.english set mismatch")
check(lang.get("other") == ot, "lang_flags.other set mismatch")
# hidden dir
hd = os.path.join(HALL, "docs")
if os.path.isdir(hd):
    res = run(["python3", "/app/detect_lang.py", "--dir", hd,
               "--output", "/tmp/langh.json"])
    rj = read_json1("/tmp/langh.json")
    hen, hot = [], []
    for p in sorted(glob.glob(os.path.join(hd, "*.txt"))):
        t = open(p, encoding="utf-8").read()
        (hen if is_english(t) else hot).append(os.path.basename(p))
    hen.sort(); hot.sort()
    check(res.returncode == 0 and rj.get("english") == hen and rj.get("other") == hot,
          "hidden english set mismatch")
# empty dir edge
hed = os.path.join(HALL, "docs_empty")
if os.path.isdir(hed):
    res = run(["python3", "/app/detect_lang.py", "--dir", hed,
               "--output", "/tmp/dem.json"])
    check(res.returncode == 0 and read_json1("/tmp/dem.json") == {"english": [], "other": []},
          "detect on empty dir must give empty sets")

# ===================================================================== 6. mcq harness
print("== 6. mcq harness (tasks.yaml / run_mcq) ==")
import yaml
cfg = yaml.safe_load(open("/app/tasks.yaml", encoding="utf-8"))
check(set(cfg) >= {"task", "dataset", "labels", "template", "query_column",
                   "title_column", "gold_column", "metric"}.difference({}),
      "tasks.yaml must expose harness fields")
labels = cfg["labels"]
check(isinstance(labels, list) and len(labels) == 4, "tasks.yaml labels must be the fixed 4-label set")
ds = read_json1("/app/mcq_dataset.json")
check(ds["labels"] == cfg["labels"], "tasks.yaml labels must match dataset fixed set")
mres = read_json1("/app/mcq_result.json")
check(mres.get("samples_n") == len(ds["samples"]), "mcq_result sample count mismatch")
check(abs(mres.get("acc", -1) - 1.0) < 1e-6, "mcq acc must be 1.0")
samp = ds["samples"]
gold_labels = [cfg["labels"][s["gold"]] for s in samp]
per = {d["doc"]: d for d in mres["samples"]}
check(all(per[i]["gold_index"] == samp[i]["gold"] for i in range(len(samp))),
      "mcq gold_index must equal dataset gold per doc")
check(all(per[i]["gold_label"] == cfg["labels"][samp[i]["gold"]]
          for i in range(len(samp))), "mcq gold_label wrong for some doc")
# prompt actually embeds query/title and fixed label set
check(all(("gold" in p["prompt"]) and (p["query"] in p["prompt"]) and
          (p["title"] in p["prompt"]) for p in mres["samples"]),
      "mcq prompt must embed template + query/title")
# hidden dataset generalizes
hcfg = os.path.join(HALL, "mcq_cfg.yaml")
if os.path.isfile(hcfg):
    res = run(["python3", "/app/run_mcq.py", "--config", hcfg,
               "--output", "/tmp/mcq_h.json"])
    hds = read_json("/tests/hidden/mcq_h.json")
    hres = read_json1("/tmp/mcq_h.json")
    hlabels = yaml.safe_load(open(hcfg, encoding="utf-8"))["labels"]
    total_ok = 0
    for i, s in enumerate(hds["samples"]):
        if hres["samples"][i]["gold_index"] == s["gold"] and \
           hres["samples"][i]["gold_label"] == hlabels[s["gold"]]:
            total_ok += 1
    check(res.returncode == 0 and total_ok == len(hds["samples"]) and
          abs(hres.get("acc", 0) - 1.0) < 1e-6, "hidden mcq gold selection wrong")

# ===================================================================== 7. leaderboard
print("== 7. leaderboard (deliverable) ==")
lb = read_json("/app/leaderboard_source.json")
rows = lb["rows"]; metric = lb["metric"]
def topid(rows, metric):
    if not rows:
        return ""
    mval = max(float(r.get(metric, 0.0)) for r in rows)
    cands = [r for r in rows if abs(float(r.get(metric, 0.0)) - mval) < 1e-12]
    return min(cands, key=lambda r: r.get("model_id", ""))["model_id"]
want_top = topid(rows, metric)
got_top = open("/app/leaderboard_top.txt", encoding="utf-8").read().strip()
check(got_top == want_top, "leaderboard_top.txt %r != %r" % (got_top, want_top))
hlb = os.path.join(HALL, "lb_h.json")
if os.path.isfile(hlb):
    hb2 = read_json(hlb)
    r = run(["python3", "/app/fetch_leaderboard.py", "--input", hlb,
             "--output", "/tmp/lb2.txt"])
    got_h = open("/tmp/lb2.txt", encoding="utf-8").read().strip()
    check(r.returncode == 0 and got_h == topid(hb2["rows"], hb2["metric"]),
          "hidden leaderboard top mismatch")
    # tie-break + empty edge
helb = os.path.join(HALL, "lb_tie.json")
if os.path.isfile(helb):
    r = run(["python3", "/app/fetch_leaderboard.py", "--input", helb,
             "--output", "/tmp/lbt.txt"])
    t_ = read_json(helb)
    check(r.returncode == 0 and
          open("/tmp/lbt.txt", encoding="utf-8").read().strip() == topid(t_["rows"], t_["metric"]),
          "hidden leaderboard tie-break mismatch")
be = os.path.join(HALL, "lb_empty.json")
if os.path.isfile(be):
    r = run(["python3", "/app/fetch_leaderboard.py", "--input", be,
             "--output", "/tmp/lbe.txt"])
    check(r.returncode == 0 and
          open("/tmp/lbe.txt", encoding="utf-8").read().strip() == "",
          "empty leaderboard must emit empty string")

# ===================================================================== summary
rc = 0 if not FAIL else 1
print("----")
print("CHECKS_FAIL=%d" % len(FAIL))
print("VERDICT=%d" % (0 if rc == 1 else 1))
sys.exit(rc)