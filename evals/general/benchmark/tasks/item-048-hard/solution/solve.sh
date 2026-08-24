#!/bin/bash
set -euo pipefail

cat > /app/retrieve.py <<'PYEOF'
#!/usr/bin/env python3
"""Item-048 correct retriever: pinned bge-small-zh-v1.5, deterministic ranking."""
import json
import numpy as np
from sentence_transformers import SentenceTransformer

SHAS = "/app/MODEL_SHA.txt"
MODEL_DIR = "/app/model_cache"
DATA = "/app/data"
QUERY_PREFIX = "为这个句子生成表示以用于检索相关文章："


def read_lines(path):
    txt = open(path, "r", encoding="utf-8").read()
    lines = txt.split("\n")
    if lines and lines[-1] == "":
        lines = lines[:-1]
    return lines


def main():
    pinned = open(SHAS, "r", encoding="utf-8").read().strip()
    if pinned.startswith("sha="):
        pinned = pinned[len("sha="):]
    # Local offline snapshot is pinned; this script embeds the pinned revision id
    # into its output so audits can confirm which revision produced the rankings.
    docs = read_lines(f"{DATA}/docs.txt")
    queries = read_lines(f"{DATA}/queries.txt")
    truth = json.load(open(f"{DATA}/ground_truth.json", encoding="utf-8"))

    model = SentenceTransformer(MODEL_DIR)
    doc_embs = model.encode(docs, normalize_embeddings=True, batch_size=16)
    q_embs = model.encode(
        [QUERY_PREFIX + q for q in queries], normalize_embeddings=True, batch_size=16
    )
    sims = q_embs @ doc_embs.T  # cosine similarity of normalized embeddings

    out_lines = []
    for qi, scores in enumerate(sims):
        qid = qi + 1
        order = sorted(range(len(docs)), key=lambda di: (-float(scores[di]), di))
        relevant = int(truth[str(qid)])
        rank = order.index(relevant - 1) + 1  # doc id -> 0-based -> 1-based rank
        top_doc_id = order[0] + 1
        out_lines.append(
            json.dumps(
                {
                    "query_id": qid,
                    "relevant_doc_id": relevant,
                    "rank_of_relevant": rank,
                    "top_doc_id": top_doc_id,
                    "pinned_sha": f"sha={pinned}",
                },
                ensure_ascii=False,
            )
        )

    with open("/app/ranks.jsonl", "w", encoding="utf-8") as f:
        f.write("\n".join(out_lines) + "\n")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # noqa: BLE001
        with open("/app/error.txt", "w", encoding="utf-8") as f:
            f.write(repr(exc))
        raise
PYEOF

python3 /app/retrieve.py