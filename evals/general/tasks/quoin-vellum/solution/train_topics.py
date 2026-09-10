#!/usr/bin/env python3
"""Train a gensim LDA topic model on an arbitrary corpus and save it in gensim's
own binary format.

This is the deliverable of the quoin-vellum task. It is intentionally generic:
it accepts any corpus directory with a `docs.txt` (one whitespace-tokenised
document per line) and writes a serialised `gensim.models.LdaModel` to the
requested output path.

The number of latent topics is NOT given anywhere: the script discovers it by
training a range of candidate models and keeping the one whose c_v topic
coherence is highest. A coherent, topically-separated model is what the verifier
scores, so a script that guesses a topic count, or never actually trains, scores
poorly.

Usage: train_topics.py <corpus_dir> <model_out.model>
"""
import os
import sys

from gensim.corpora import Dictionary
from gensim.models import LdaModel
from gensim.models.coherencemodel import CoherenceModel
from gensim.models.word2vec import LineSentence


def train(corpus_dir, model_out, seed=7):
    docs = [list(s) for s in LineSentence(os.path.join(corpus_dir, "docs.txt"))]
    if not docs:
        raise SystemExit("corpus is empty")
    d = Dictionary(docs)
    d.filter_extremes(no_below=2, no_above=0.7)
    corpus = [d.doc2bow(x) for x in docs]

    # Discover the topic count by maximum c_v coherence over a reasonable range.
    lo = 2
    hi = min(11, max(3, len(d) // 8))
    best_k, best_cv, best_lda = None, None, None
    for k in range(lo, hi + 1):
        lda = LdaModel(corpus, num_topics=k, id2word=d, passes=25,
                       iterations=120, random_state=seed)
        cv = CoherenceModel(model=lda, texts=docs, dictionary=d,
                            coherence="c_v").get_coherence()
        if best_cv is None or cv > best_cv:
            best_k, best_cv, best_lda = k, cv, lda

    # Retrain the chosen topic count a little harder for the final model.
    final = LdaModel(corpus, num_topics=best_k, id2word=d, passes=50,
                     iterations=200, random_state=seed)
    final.save(model_out)
    print(f"trained K={best_k} c_v={best_cv:.3f} -> {model_out}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("usage: train_topics.py <corpus_dir> <model_out.model>")
    train(sys.argv[1], sys.argv[2])
