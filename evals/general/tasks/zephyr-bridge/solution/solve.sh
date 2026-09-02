#!/usr/bin/env bash
# zephyr-bridge oracle: author the deliverable runner + pipeline engine, then
# run the real pipeline (tokenizer -> 300-d embeddings -> fasttext-style
# classifier + metrics -> vocab serialization) to produce every /app artifact.
set -euo pipefail
cd /app

cat > /app/run.sh <<'EOF_RUN'
#!/usr/bin/env bash
# zephyr-bridge deliverable: reproduce the full shipping bundle for a labeled
# corpus.  usage:  bash /app/run.sh [CORPUS_TSV] [OUTDIR]
#   CORPUS_TSV  default /app/data/reviews.tsv
#   OUTDIR      default /app
# Writes OUTDIR/vocab.txt OUTDIR/merges.txt OUTDIR/embeddings.npy
#         OUTDIR/model.pkl OUTDIR/metrics.csv OUTDIR/vocab.pkl
set -euo pipefail
exec python3 /app/zephyr_pipeline.py "$@"

EOF_RUN
chmod +x /app/run.sh

cat > /app/zephyr_pipeline.py <<'EOF_PY'
import os, pickle, sys
sys.path.insert(0, "/app")
from collections import Counter
import numpy as np
import zeph_loader as ZL

from gensim.models import Word2Vec
from sklearn.linear_model import LogisticRegression
from sklearn.decomposition import TruncatedSVD

EMB_DIM = 300
BUDGET_BYTES = 8 * 1024 * 1024
NUM_MERGES = 1200


def learn_merges(words, num_symbols):
    counts = Counter()
    for w in words:
        if len(w) >= 2:
            for i in range(len(w) - 1):
                counts[(w[i], w[i + 1])] += 1
    merges = []
    while len(merges) < num_symbols and counts:
        (a, b), _ = counts.most_common(1)[0]
        if counts[(a, b)] < 2:
            break
        merges.append((a, b))
        combined = a + b
        del counts[(a, b)]
        for w in words:
            wl = list(w)
            while True:
                replaced = False
                i = 0
                while i < len(wl) - 1:
                    if wl[i] == a and wl[i + 1] == b:
                        wl[i:i + 2] = [combined]
                        replaced = True
                    i += 1
                if not replaced:
                    break
            for i in range(len(wl) - 1):
                counts[(wl[i], wl[i + 1])] += 1
    return merges


def pmi_embeddings(seqs, vocab_order, dim=EMB_DIM, window=3):
    from scipy import sparse
    n = len(vocab_order)
    idx = {w: i for i, w in enumerate(vocab_order)}
    rows, cols, vals = [], [], []
    for s in seqs:
        ids = [idx[t] for t in s if t in idx]
        for j in range(len(ids)):
            for d in range(1, min(window, len(ids) - j)):
                rows.append(ids[j]); cols.append(ids[j + d]); vals.append(1.0)
                rows.append(ids[j + d]); cols.append(ids[j]); vals.append(1.0)
    C = sparse.coo_matrix((vals, (rows, cols)), shape=(n, n)).tocsr()
    rs = np.asarray(C.sum(axis=1)).ravel() + 1e-9
    cs_ = np.asarray(C.sum(axis=0)).ravel() + 1e-9
    total = rs.sum()
    C = C.astype(np.float64)
    data = C.data / total
    r, c = C.nonzero()
    den = rs[r] * cs_[c]
    C.data = np.maximum(np.log(data / (den + 1e-9)), 0.0)
    svd = TruncatedSVD(n_components=dim, random_state=7)
    return svd.fit_transform(C).astype(np.float32)


def intrinsic_dim(M):
    Mc = M - M.mean(axis=0)
    s = np.linalg.svd(Mc, compute_uv=False)
    return max(1, int((s >= s[0] * 0.05).sum())) if len(s) else 1


def corr_obj(a, b):
    sims = []
    for x, y in zip(a, b):
        nx, ny = np.linalg.norm(x), np.linalg.norm(y)
        sims.append(1.0 if nx * ny == 0 else float(np.dot(x, y) / (nx * ny)))
    return float(np.mean(sims))


def main():
    corpus = sys.argv[1] if len(sys.argv) > 1 else "/app/data/reviews.tsv"
    out = sys.argv[2] if len(sys.argv) > 2 else "/app"
    os.makedirs(out, exist_ok=True)
    rows = ZL.read_corpus(corpus)
    assert rows, "empty corpus %s" % corpus
    train_rows, test_rows = ZL.split_corpus(rows)
    train_txt = [t for _, t in train_rows]
    test_txt = [t for _, t in test_rows]
    train_lab = [l for l, _ in train_rows]
    test_lab = [l for l, _ in test_rows]

    texts = [t for _, t in rows]
    seqs = [ZL.tokens_of(t) for t in texts]
    wf = [ZL.tokens_of(t) for t in texts]
    words = sorted({w for s in seqs for w in s})
    vocab = ZL.Vocab({w: i for i, w in enumerate(words)},
                     {i: w for i, w in enumerate(words)})
    merges = learn_merges([[c for c in w] for w in words], NUM_MERGES)

    g = Word2Vec(wf, vector_size=EMB_DIM, window=5, min_count=1, sg=0,
                 workers=8, seed=7, epochs=14)
    E = np.stack([g.wv[w] for w in words]).astype(np.float32)
    gs = Word2Vec(wf, vector_size=EMB_DIM, window=5, min_count=1, sg=1,
                  workers=8, seed=7, epochs=12)
    Es = np.stack([gs.wv[w] for w in words]).astype(np.float32)
    Ep = pmi_embeddings(seqs, words, dim=EMB_DIM)

    sample = train_txt[:300]
    ref = ZL.vectorize(sample, vocab, E)
    corr_p = corr_obj(ZL.vectorize(sample, vocab, Ep), ref)
    corr_s = corr_obj(ZL.vectorize(sample, vocab, Es), ref)
    corr_e = corr_obj(ref, ref)
    metrics_rows = [
        ("pmi", corr_p, 1.0 - corr_p, E.nbytes / BUDGET_BYTES, intrinsic_dim(Ep)),
        ("cbow", corr_e, 1.0 - corr_e, E.nbytes / BUDGET_BYTES, intrinsic_dim(E)),
        ("skipgram", corr_s, 1.0 - corr_s, E.nbytes / BUDGET_BYTES, intrinsic_dim(Es)),
    ]

    X = ZL.vectorize(train_txt, vocab, E)
    Xt = ZL.vectorize(test_txt, vocab, E)
    classes = sorted(set(train_lab))
    y = np.asarray([classes.index(l) for l in train_lab])
    yt = np.asarray([classes.index(l) for l in test_lab])
    clf = LogisticRegression(max_iter=2000, C=10.0, solver="lbfgs")
    clf.fit(X, y)
    acc = float((clf.predict(Xt) == yt).mean())
    with open(os.path.join(out, "model.pkl"), "wb") as fh:
        pickle.dump({"clf": clf, "classes": classes}, fh)

    with open(os.path.join(out, "vocab.txt"), "w") as fh:
        for w in words:
            fh.write(w + "\n")
    with open(os.path.join(out, "merges.txt"), "w") as fh:
        for a, b in merges:
            fh.write("%s %s\n" % (a, b))
    np.save(os.path.join(out, "embeddings.npy"), E)
    with open(os.path.join(out, "vocab.pkl"), "wb") as fh:
        pickle.dump(vocab, fh)
    with open(os.path.join(out, "metrics.csv"), "w") as fh:
        fh.write("model,correlation,error,penalty,dof\n")
        for m, co, er, pe, dn in metrics_rows:
            fh.write("%s,%.6f,%.6f,%.6f,%d\n" % (m, co, er, pe, dn))
    print("ACCURACY=%.4f vocab=%d merges=%d" % (acc, len(words), len(merges)))


if __name__ == "__main__":
    main()

EOF_PY

# Run the actual pipeline against the shipped corpus -> creates the deliverables.
bash /app/run.sh /app/data/reviews.tsv /app

# Confirm every declared /app deliverable was produced (literal paths).
for f in /app/run.sh /app/vocab.txt /app/merges.txt /app/embeddings.npy \
         /app/metrics.csv /app/vocab.pkl /app/model.pkl; do
  test -s "$f" || { echo "oracle: missing deliverable $f" >&2; exit 1; }
done
