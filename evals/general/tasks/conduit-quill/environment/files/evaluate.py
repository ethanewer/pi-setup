#!/usr/bin/env python3
"""conduit-quill visible-dev evaluator.

Runs /app/rag.py over the visible dev query set (/app/dev/queries.json) and
reports the quality gates the verifier enforces on the hidden sets:

  * mean recall@5        - for every dev query, whether the relevant documents
                           are among the top-5 documents the retriever returned.
  * cross-wording hit    - the fraction of queries whose ``narrow_doc`` (the
                           relevant document written with different wording,
                           sharing no query vocabulary) is among the top-5.
  * citation precision   - the fraction of [@doc_xxxxx] answer citations whose
                           cited sentence actually appears verbatim (up to case
                           and punctuation) in the cited document.

This helper never touches /tests; it is a convenience so you can measure your
pipeline against the shipped dev queries before the verifier re-runs it on the
unseen hidden query sets.

Usage:  python3 /app/evaluate.py
"""
import json
import re
import subprocess
import sys

CORPUS = "/app/corpus.json"
QUERIES = "/app/dev/queries.json"
INDEX = "/tmp/conduit-index"
TOP_K = 5

# The declared thresholds the verifier enforces.
RECALL_THRESHOLD = 0.85
NARROW_THRESHOLD = 0.85
CIT_PRECISION_THRESHOLD = 0.90
MIN_CITATIONS_PER_ANSWER = 2

ANCHOR_RE = re.compile(r"\[@([a-z0-9_]+)\]")


def normalize(text):
    return re.sub(r"[^a-z0-9 ]+", " ", text.lower())


def citation_precision(answer, docs):
    """Compute fraction of grounded citations in an answer string.

    A citation anchor [@doc_xxxxx] asserts that the sentence ending
    immediately before it is supported by the cited document. The citation is
    valid iff a normalized form of that sentence is a substring of the
    normalized cited document body.
    """
    anchors = list(ANCHOR_RE.finditer(answer))
    if not anchors:
        return 0.0, 0
    valid = 0
    prev_end = 0
    for m in anchors:
        cited = m.group(1)
        segment = normalize(answer[prev_end:m.start()]).strip()
        prev_end = m.end()
        if not segment or cited not in docs:
            continue
        if segment in docs[cited]:
            valid += 1
    return valid / len(anchors), len(anchors)


def run_query(query):
    out = "/tmp/conduit-result.json"
    r = subprocess.run(
        [sys.executable, "/app/rag.py", "query",
         "--query", query, "--top-k", str(TOP_K),
         "--corpus", CORPUS, "--index", INDEX, "--out", out],
        capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError("rag.py query failed: " + r.stderr.strip())
    return json.load(open(out))


def main():
    corpus = json.load(open(CORPUS))
    docs = {d["doc_id"]: normalize(d["body"]) for d in corpus}
    queries = json.load(open(QUERIES))

    # Build the index once.
    r = subprocess.run([sys.executable, "/app/rag.py", "build",
                        "--corpus", CORPUS, "--index", INDEX],
                       capture_output=True, text=True)
    if r.returncode != 0:
        print("build failed:", r.stderr.strip())
        sys.exit(2)

    recalls = []
    narrows = []
    precisions = []
    cit_counts = []
    for q in queries:
        res = run_query(q["query"])
        rel = set(q["relevant_doc_ids"])
        got = res["retrieved_docs"]
        recalls.append(len(rel & set(got)) / len(rel))
        if q.get("narrow_doc"):
            narrows.append(1 if q["narrow_doc"] in got[:TOP_K] else 0)
        prec, ncit = citation_precision(res["answer"], docs)
        precisions.append(prec)
        cit_counts.append(ncit)

    mean_recall = sum(recalls) / len(recalls)
    narrow_rate = (sum(narrows) / len(narrows) if narrows else 1.0)
    mean_prec = sum(precisions) / len(precisions)
    mean_cit = sum(cit_counts) / len(cit_counts)

    print("dev queries:", len(queries))
    print("mean recall@%d     = %.3f   (need >= %.2f)" %
          (TOP_K, mean_recall, RECALL_THRESHOLD))
    print("cross-wording hit  = %.3f   (need >= %.2f)" %
          (narrow_rate, NARROW_THRESHOLD))
    print("citation precision  = %.3f   (need >= %.2f)" %
          (mean_prec, CIT_PRECISION_THRESHOLD))
    print("citations / answer  = %.2f   (need >= %d)" %
          (mean_cit, MIN_CITATIONS_PER_ANSWER))

    ok = (mean_recall >= RECALL_THRESHOLD
          and narrow_rate >= NARROW_THRESHOLD
          and mean_prec >= CIT_PRECISION_THRESHOLD
          and mean_cit >= MIN_CITATIONS_PER_ANSWER)
    print("RESULT:", "PASS" if ok else "FAIL")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()