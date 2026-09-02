#!/bin/bash
# Verifier for opal-lexicon (executes-deliverable).
# Executes /app/build_vocab.py on the visible corpus and on every hidden
# corpus under /tests/hidden, checks the pickled Vocab (module path, exact
# inverse maps, size == embedding rows), determinism, and the shipped
# artifacts. Writes 1/0 to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
reward=0

PRISTINE_CORPUS_SHA="cf2b7473dcf5dd3be76de92e5520fb058ff3a14b98be2ff06b320630cc89c65a"

no_modify_broken=0
if [ ! -f /app/data/corpus.txt ]; then
    echo "no-modify: /app/data/corpus.txt missing" >&2
    no_modify_broken=1
else
    actual="$(sha256sum /app/data/corpus.txt | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_CORPUS_SHA" ]; then
        echo "no-modify: /app/data/corpus.txt was modified" >&2
        no_modify_broken=1
    fi
fi

python3 - "$no_modify_broken" <<'PY'
import json, os, pickle, subprocess, sys

APP = "/app"
BUILDER = "/app/build_vocab.py"
VOCAB_LIB = "/app/vocab_lib.py"
VOCAB_TXT = "/app/vocab.txt"
EMBEDDINGS_CSV = "/app/embeddings.csv"
VOCAB_PKL = "/app/vocab.pkl"
no_modify_broken = int(sys.argv[1])
DIM = 16


def expected_order(corpus_path):
    freq = {}
    with open(corpus_path, "r", encoding="utf-8") as fh:
        for line in fh:
            for tok in line.split():
                freq[tok] = freq.get(tok, 0) + 1
    return sorted(freq, key=lambda t: (-freq[t], t))


def build(tmpdir, corpus_path):
    if os.path.isdir(tmpdir):
        import shutil
        shutil.rmtree(tmpdir)
    r = subprocess.run([sys.executable, BUILDER, corpus_path, tmpdir],
                       capture_output=True, text=True, timeout=120, cwd=APP)
    return r


def read_text(p):
    with open(p, "rb") as fh:
        return fh.read()


def check_artifacts(outdir, corpus_path, expected_tokens):
    """All structural checks for one build. Returns list of failure strings."""
    bad = []
    vtxt = os.path.join(outdir, "vocab.txt")
    ecsv = os.path.join(outdir, "embeddings.csv")
    vpkl = os.path.join(outdir, "vocab.pkl")
    # the container module must live at the required path /app/vocab_lib.py
    if not os.path.isfile(VOCAB_LIB):
        bad.append("missing /app/vocab_lib.py")
    elif "class Vocab" not in open(VOCAB_LIB, encoding="utf-8", errors="replace").read():
        bad.append("/app/vocab_lib.py does not define class Vocab")
    for p in (vtxt, ecsv, vpkl):
        if not os.path.isfile(p):
            bad.append("missing %s" % p)
            return bad

    # vocab.txt content = exact expected order
    lines = read_text(vtxt).decode("utf-8").split("\n")
    if lines and lines[-1] == "":
        lines = lines[:-1]
    if lines != expected_tokens:
        bad.append("vocab.txt does not match expected ordering (%d vs %d lines)"
                   % (len(lines), len(expected_tokens)))

    # embeddings.csv: one line per token, 16 finite floats, nonzero row
    rows = read_text(ecsv).decode("utf-8").splitlines()
    if len(rows) != len(expected_tokens):
        bad.append("embeddings.csv has %d rows, expected %d"
                   % (len(rows), len(expected_tokens)))
    else:
        for i, row in enumerate(rows):
            try:
                vals = [float(x) for x in row.split(",")]
            except Exception:
                bad.append("embeddings.csv row %d unparseable" % i)
                break
            if len(vals) != DIM or any(v != v or v in (float("inf"), float("-inf")) for v in vals):
                bad.append("embeddings.csv row %d bad values" % i)
                break
            if all(v == 0.0 for v in vals):
                bad.append("embeddings.csv row %d all-zero" % i)
                break

    # vocab.pkl: unpickles inside the checker (module path /app), exact inverses
    try:
        import importlib
        if APP not in sys.path:
            sys.path.insert(0, APP)
        importlib.invalidate_caches()
        with open(vpkl, "rb") as fh:
            v = pickle.load(fh)
    except Exception as exc:
        bad.append("vocab.pkl failed to unpickle: %r" % (exc,))
        return bad
    w2i = getattr(v, "word2idx", None)
    i2w = getattr(v, "idx2word", None)
    if not isinstance(w2i, dict) or not isinstance(i2w, list):
        bad.append("vocab.pkl lacks word2idx dict / idx2word list")
        return bad
    if w2i != {tok: i for i, tok in enumerate(expected_tokens)}:
        bad.append("word2idx does not match expected mapping")
    if i2w != list(expected_tokens):
        bad.append("idx2word does not match expected ordering")
    inv_ok = all(i2w[i] == t for t, i in w2i.items()) and \
        len(w2i) == len(i2w) == len(set(w2i.values())) and \
        set(w2i.values()) == set(range(len(i2w)))
    if not inv_ok:
        bad.append("word2idx / idx2word are not exact inverses")
    try:
        if hasattr(v, "check_inverse") and not v.check_inverse():
            bad.append("check_inverse() returned False")
    except Exception as exc:
        bad.append("check_inverse() raised: %r" % (exc,))
    if hasattr(v, "size"):
        try:
            if v.size() != len(expected_tokens):
                bad.append("size() != number of embedding rows")
        except Exception:
            pass
    return bad


failures = []
if no_modify_broken:
    failures.append("visible corpus modified or missing (no-modify rule)")

if not os.path.isfile(BUILDER):
    failures.append("missing /app/build_vocab.py")
else:
    # --- visible corpus: rebuild into a temp dir and check everything ---
    if os.path.isfile("/app/data/corpus.txt"):
        exp_visible = expected_order("/app/data/corpus.txt")
        r1 = build("/tmp/opal_vis_1", "/app/data/corpus.txt")
        if r1.returncode != 0:
            failures.append("builder failed on visible corpus: %s" % r1.stderr[:300])
        else:
            failures.extend("visible: " + b for b in
                            check_artifacts("/tmp/opal_vis_1", "/app/data/corpus.txt", exp_visible))
            # determinism: second run byte-identical
            r2 = build("/tmp/opal_vis_2", "/app/data/corpus.txt")
            if r2.returncode != 0:
                failures.append("builder second run failed on visible corpus")
            else:
                for name in ("vocab.txt", "embeddings.csv", "vocab.pkl"):
                    if read_text(os.path.join("/tmp/opal_vis_1", name)) != \
                       read_text(os.path.join("/tmp/opal_vis_2", name)):
                        failures.append("visible rerun not byte-identical: %s" % name)
            # shipped artifacts must match a fresh build of the visible corpus
            for name, p in (("vocab.txt", VOCAB_TXT),
                            ("embeddings.csv", EMBEDDINGS_CSV),
                            ("vocab.pkl", VOCAB_PKL)):
                if not os.path.isfile(p):
                    failures.append("missing shipped %s" % p)
                elif read_text(p) != read_text(os.path.join("/tmp/opal_vis_1", name)):
                    failures.append("shipped %s differs from fresh build" % p)

    # --- hidden corpora ---
    hidden_dir = "/tests/hidden"
    if not os.path.isdir(hidden_dir):
        failures.append("no hidden cases present")
    else:
        cases = sorted(d for d in os.listdir(hidden_dir)
                       if os.path.isdir(os.path.join(hidden_dir, d)))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden_dir, c)
            corpus = os.path.join(base, "corpus.txt")
            exp_path = os.path.join(base, "expected.json")
            if not (os.path.isfile(corpus) and os.path.isfile(exp_path)):
                failures.append("hidden '%s' malformed" % c)
                continue
            try:
                with open(exp_path) as fh:
                    exp = json.load(fh)
                expected_tokens = exp["tokens"]
            except Exception:
                failures.append("hidden '%s' expected.json unreadable" % c)
                continue
            r1 = build("/tmp/opal_h_1", corpus)
            if r1.returncode != 0:
                failures.append("hidden '%s': builder failed: %s" % (c, r1.stderr[:200]))
                continue
            bad = check_artifacts("/tmp/opal_h_1", corpus, expected_tokens)
            failures.extend("hidden %s: %s" % (c, b) for b in bad)
            r2 = build("/tmp/opal_h_2", corpus)
            if r2.returncode != 0:
                failures.append("hidden '%s': second run failed" % c)
            else:
                for name in ("vocab.txt", "embeddings.csv", "vocab.pkl"):
                    if read_text(os.path.join("/tmp/opal_h_1", name)) != \
                       read_text(os.path.join("/tmp/opal_h_2", name)):
                        failures.append("hidden '%s' rerun not byte-identical: %s" % (c, name))

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
