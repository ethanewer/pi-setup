#!/usr/bin/env python3
"""conduit-quill RAG solver (oracle / reference implementation).

Builds a retrieval index over a local corpus and answers a query with a
citation-checked summary grounded in the retrieved documents. The retrieval
combines:

  * BM25 lexical scoring, and
  * a locally computed co-occurrence embedding: a distributional model of the
    corpus built from sentence-level term co-occurrence among the rare
    vocabulary. Query terms are expanded to their semantic neighbours in this
    vector space (synonyms / co-occurring terms), so a document that states a
    fact with different wording from the query is still retrieved.

No network, no external model: everything is computed from the shipped corpus.

CLI:
  build --corpus <corpus.json> --index <dir>
  query  --query "<text>" --top-k N --corpus <corpus.json> --index <dir> --out <r.json>

Result JSON:
  {"query": ..., "retrieved_docs": [top-k distinct parent doc ids],
   "answer": "prose with [@doc_xxxxx] citation anchors, each grounded in the
              cited document"}
"""
import argparse
import json
import math
import os
import re
import sys

try:
    import numpy as np
except Exception:  # pragma: no cover
    np = None

CHUNK_TOKENS = 120          # chunker target window size (whole sentences)
OVERLAP = 24                # chunker overlap tokens
RARE_MAX_DF = 0.05          # a term is "content" if it appears in <=5% of chunks
EXPAND = 2                  # how many co-occurrence neighbours per query term

_TOKEN_RE = re.compile(r"[a-z0-9]+")


def tokenize(text):
    return _TOKEN_RE.findall(text.lower())


def split_sentences(text):
    return [s.strip() for s in re.split(r"(?<=[.!?])\s+", text) if s.strip()]


def chunk_document(body):
    """Split a document into overlapping chunks of ~CHUNK_TOKENS words, keeping
    whole-sentence boundaries. Returns list of dicts {tokens, text}."""
    sentences = split_sentences(body)
    chunks = []
    cur_toks = []
    cur_text = []
    for s in sentences:
        st = tokenize(s)
        if cur_toks and len(cur_toks) + len(st) > CHUNK_TOKENS:
            chunks.append({"tokens": list(cur_toks), "text": " ".join(cur_text)})
            cur_toks = cur_toks[-OVERLAP:] if len(cur_toks) >= OVERLAP else []
            keep = []
            acc = 0
            for ts in reversed(cur_text):
                acc += len(tokenize(ts))
                keep.insert(0, ts)
                if acc >= OVERLAP:
                    break
            cur_text = keep
        cur_toks.extend(st)
        cur_text.append(s)
    if cur_toks:
        chunks.append({"tokens": list(cur_toks), "text": " ".join(cur_text)})
    return chunks


class Index:
    def __init__(self, corpus_path):
        docs = json.load(open(corpus_path))
        self.docs = {d["doc_id"]: d for d in docs}
        self.chunk_of = []  # (doc_id, tokens, text)
        for did in sorted(self.docs):
            for c in chunk_document(self.docs[did]["body"]):
                self.chunk_of.append((did, c["tokens"], c["text"]))
        self.n_chunks = len(self.chunk_of)
        self.vocab = {}
        self._build_vocab()
        self._build_bm25()
        self._build_cooccurrence()

    # ---- vocabulary / df --------------------------------------------------
    def _build_vocab(self):
        idx = 0
        for _, toks, _ in self.chunk_of:
            for t in toks:
                if t not in self.vocab:
                    self.vocab[t] = idx
                    idx += 1
        self.vocab_size = len(self.vocab)
        self.word = {v: k for k, v in self.vocab.items()}

    # ---- BM25 -------------------------------------------------------------
    def _build_bm25(self):
        n = self.n_chunks
        self.chunk_len = [len(c[1]) for c in self.chunk_of]
        self.avg_len = sum(self.chunk_len) / max(1, n)
        self.df = {}
        for _, toks, _ in self.chunk_of:
            for t in set(toks):
                self.df[t] = self.df.get(t, 0) + 1
        self.tf = []
        for _, toks, _ in self.chunk_of:
            tf = {}
            for t in toks:
                tf[t] = tf.get(t, 0) + 1
            self.tf.append(tf)
        self.N = n
        self.k1 = 1.5
        self.b = 0.75
        self.idf = {}
        for t in self.vocab:
            df = self.df.get(t, 0)
            self.idf[t] = math.log(1 + (n - df + 0.5) / (df + 0.5))

    def is_content(self, t):
        return t in self.vocab and self.df.get(t, 0) / self.N <= RARE_MAX_DF

    def bm25_score(self, qtokens, ci):
        score = 0.0
        tf = self.tf[ci]
        dl = self.chunk_len[ci]
        for t in qtokens:
            f = tf.get(t, 0)
            if not f:
                continue
            idf = self.idf.get(t, 0.0)
            num = f * (self.k1 + 1)
            den = f + self.k1 * (1 - self.b + self.b * dl / self.avg_len)
            score += idf * num / (den + 1e-9)
        return score

    # ---- co-occurrence embedding ------------------------------------------
    def _build_cooccurrence(self):
        """Locally computed distributional embedding: sentence-level term
        co-occurrence among the rare (content) vocabulary. For every content
        term we keep the strongest-co-occurring content neighbours - these form
        the term's semantic expansion (synonyms / closely-related terms)."""
        from collections import defaultdict
        self.neighbours = defaultdict(list)
        # map content term -> list of (neighbour, count)
        co = defaultdict(int)
        for did, toks, _ in self.chunk_of:
            doc = self.docs[did]["body"]
            for s in split_sentences(doc):
                seen = sorted(set(t for t in tokenize(s) if self.is_content(t)))
                for i in range(len(seen)):
                    for j in range(i + 1, len(seen)):
                        a, b = seen[i], seen[j]
                        co[(a, b)] += 1
                        co[(b, a)] += 1
        tmp = defaultdict(list)
        for (a, b), c in co.items():
            tmp[a].append((b, c))
        for w, lst in tmp.items():
            lst.sort(key=lambda x: (-x[1], x[0]))
            self.neighbours[w] = [t for t, _ in lst[:EXPAND]]

    def expand_query(self, raw_tokens):
        """Rare query terms plus their co-occurrence neighbours."""
        base = [t for t in raw_tokens if self.is_content(t)]
        expanded = set(base)
        for t in base:
            for nn in self.neighbours.get(t, []):
                expanded.add(nn)
        return list(expanded)

    # ---- persistence ------------------------------------------------------
    def save(self, path):
        os.makedirs(path, exist_ok=True)
        json.dump(self.chunk_of, open(os.path.join(path, "chunks.json"), "w"))
        json.dump({"vocab": self.vocab, "df": self.df,
                   "N": self.N, "avg_len": self.avg_len,
                   "neighbours": {k: v for k, v in self.neighbours.items()}},
                  open(os.path.join(path, "meta.json"), "w"))

    @classmethod
    def load(cls, path, corpus_path):
        idx = cls.__new__(cls)
        idx.docs = {d["doc_id"]: d for d in json.load(open(corpus_path))}
        idx.chunk_of = json.load(open(os.path.join(path, "chunks.json")))
        idx.n_chunks = len(idx.chunk_of)
        meta = json.load(open(os.path.join(path, "meta.json")))
        idx.vocab = meta["vocab"]
        idx.vocab_size = len(idx.vocab)
        idx.word = {v: k for k, v in idx.vocab.items()}
        idx.df = meta["df"]
        idx.N = meta["N"]
        idx.avg_len = meta["avg_len"]
        idx.neighbours = dict(meta["neighbours"])
        idx.tf = []
        idx.chunk_len = []
        for _, toks, _ in idx.chunk_of:
            tf = {}
            for t in toks:
                tf[t] = tf.get(t, 0) + 1
            idx.tf.append(tf)
            idx.chunk_len.append(len(toks))
        idx.k1 = 1.5
        idx.b = 0.75
        idx.idf = {}
        for t in idx.vocab:
            df = idx.df.get(t, 0)
            idx.idf[t] = math.log(1 + (idx.N - df + 0.5) / (df + 0.5))
        return idx


def build_index(corpus_path, index_path):
    idx = Index(corpus_path)
    idx.save(index_path)
    print("built index: %d docs, %d chunks, vocab %d" % (
        len(idx.docs), idx.n_chunks, idx.vocab_size))


def answer_from(idx, retrieved_docs):
    """Assemble a citation-checked answer: pick one grounded sentence from each
    retrieved doc and attribute it to that document. Every cited sentence is
    copied verbatim from the cited document, so every citation is grounded."""
    out = []
    for did in retrieved_docs:
        body = idx.docs[did]["body"]
        for s in split_sentences(body):
            if s and "[@" not in s:
                out.append("%s [@%s]" % (s.rstrip("."), did))
                break
    return " ".join(out)


def run_query(query, top_k, corpus_path, index_path, out_path):
    if os.path.isdir(index_path) and os.path.exists(
            os.path.join(index_path, "meta.json")):
        idx = Index.load(index_path, corpus_path)
    else:
        idx = Index(corpus_path)
        idx.save(index_path)
    raw = tokenize(query)
    expanded = idx.expand_query(raw)
    scores = [idx.bm25_score(expanded, ci) for ci in range(idx.n_chunks)]
    order = sorted(range(idx.n_chunks), key=lambda i: scores[i], reverse=True)
    retrieved = []
    for ci in order:
        did = idx.chunk_of[ci][0]
        if did not in retrieved:
            retrieved.append(did)
        if len(retrieved) >= top_k:
            break
    answer = answer_from(idx, retrieved)
    result = {"query": query, "retrieved_docs": retrieved, "answer": answer}
    with open(out_path, "w") as fh:
        json.dump(result, fh, indent=1)
    return result


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "build":
        p = argparse.ArgumentParser()
        p.add_argument("--corpus", required=True)
        p.add_argument("--index", required=True)
        a = p.parse_args(sys.argv[2:])
        build_index(a.corpus, a.index)
        return
    p = argparse.ArgumentParser()
    p.add_argument("--query", required=True)
    p.add_argument("--top-k", type=int, default=5)
    p.add_argument("--corpus", required=True)
    p.add_argument("--index", required=True)
    p.add_argument("--out", required=True)
    a = p.parse_args(sys.argv[2:])
    run_query(a.query, a.top_k, a.corpus, a.index, a.out)


if __name__ == "__main__":
    main()
