#!/bin/bash
# Verifier for conduit-quill (executes-deliverable).
# Builds the agent's /app/rag.py index over /app/corpus.json, then runs the
# agent's query command over the visible dev set and the three hidden query
# sets, asserting the declared retrieval-quality gates on every set:
#   - mean recall@5              >= 0.85 (relevance judgements)
#   - cross-wording doc hit rate >= 0.85 (the relevant doc marked `narrow_doc`
#     must be in the top-5: the retriever must find documents that state the
#     information with different wording than the query)
#   - citation precision         >= 0.90 (every cited span appears verbatim,
#     up to case/punctuation, in the cited document)
#   - mean citations/answer      >= 2
# Writes /logs/verifier/reward.txt (1 iff all gates hold on all sets, else 0).
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier

if [ ! -f /app/rag.py ]; then
  echo "missing deliverable /app/rag.py" >&2
  echo "0" > /logs/verifier/reward.txt
  exit 0
fi

python3 - <<'PY'
import json
import os
import re
import subprocess
import sys

CORPUS = "/app/corpus.json"
INDEX = "/tmp/conduit-verify-index"
TOP_K = 5
RECALL_THRESHOLD = 0.85
NARROW_THRESHOLD = 0.85
CIT_THRESHOLD = 0.90
MIN_CIT = 2.0

failures = []
ANCHOR_RE = re.compile(r"\[@([a-z0-9_]+)\]")


def normalize(t):
    return re.sub(r"[^a-z0-9 ]+", " ", t.lower())


def citation_metrics(answer, docs):
    anchors = list(ANCHOR_RE.finditer(answer))
    if not anchors:
        return 0.0, 0
    valid = 0
    prev = 0
    for m in anchors:
        cited = m.group(1)
        seg = normalize(answer[prev:m.start()]).strip()
        prev = m.end()
        if not seg or cited not in docs:
            continue
        if seg in docs[cited]:
            valid += 1
    return valid / len(anchors), len(anchors)


def run_query(query):
    out = "/tmp/conduit-res.json"
    r = subprocess.run(
        [sys.executable, "/app/rag.py", "query",
         "--query", query, "--top-k", str(TOP_K),
         "--corpus", CORPUS, "--index", INDEX, "--out", out],
        capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError("rag.py query failed: " + (r.stderr or "").strip())
    return json.load(open(out))


# ---- load corpus + resources ----
if not os.path.exists(CORPUS):
    failures.append("corpus missing: %s" % CORPUS)
else:
    corpus = json.load(open(CORPUS))
    docs = {d["doc_id"]: normalize(d["body"]) for d in corpus}

    # ---- build the index through the deliverable ----
    b = subprocess.run([sys.executable, "/app/rag.py", "build",
                        "--corpus", CORPUS, "--index", INDEX],
                       capture_output=True, text=True)
    if b.returncode != 0:
        failures.append("rag.py build failed: " + (b.stderr or "").strip())
    else:
        if not os.path.isdir(INDEX) or not os.listdir(INDEX):
            failures.append("rag.py build produced no index artifacts")

        # ---- evaluate each query set ----
        sets = {"dev": "/app/dev/queries.json"}
        hroot = "/tests/hidden"
        if os.path.isdir(hroot):
            for name in sorted(os.listdir(hroot)):
                p = os.path.join(hroot, name, "queries.json")
                if os.path.exists(p):
                    sets[name] = p

        per_set_recall = {}
        per_set_narrow = {}
        per_set_cit = {}
        per_set_citcount = {}
        for sname, qpath in sorted(sets.items()):
            if not os.path.exists(qpath):
                failures.append("query set %s missing: %s" % (sname, qpath))
                continue
            queries = json.load(open(qpath))
            recalls = []
            narrows = []
            precs = []
            citcounts = []
            for q in queries:
                try:
                    res = run_query(q["query"])
                except RuntimeError as e:
                    failures.append("%s: %s" % (sname, e))
                    break
                rel = set(q["relevant_doc_ids"])
                got = res.get("retrieved_docs", [])
                recalls.append(len(rel & set(got)) / len(rel))
                if q.get("narrow_doc"):
                    narrows.append(1 if q["narrow_doc"] in got[:TOP_K] else 0)
                prec, nc = citation_metrics(res.get("answer", ""), docs)
                precs.append(prec)
                citcounts.append(nc)
            if not recalls:
                continue
            if not narrows:
                failures.append("%s: query set carries no narrow_doc markers" % sname)
                continue
            per_set_recall[sname] = sum(recalls) / len(recalls)
            per_set_narrow[sname] = (sum(narrows) / len(narrows)
                                     if narrows else 1.0)
            per_set_cit[sname] = sum(precs) / len(precs)
            per_set_citcount[sname] = sum(citcounts) / len(citcounts)

        for sname in sorted(per_set_recall):
            r = per_set_recall[sname]
            nr = per_set_narrow[sname]
            c = per_set_cit[sname]
            cc = per_set_citcount[sname]
            print("%-6s recall@%d=%.3f (>=%.2f)  narrow=%.3f (>=%.2f)  "
                  "cit_prec=%.3f (>=%.2f)  cit/ans=%.2f (>=%.1f)" %
                  (sname, TOP_K, r, RECALL_THRESHOLD, nr, NARROW_THRESHOLD,
                   c, CIT_THRESHOLD, cc, MIN_CIT))
            if r < RECALL_THRESHOLD:
                failures.append("%s: recall@%d %.3f < %.2f (naive / partial "
                                "retrieval)" % (sname, TOP_K, r,
                                                RECALL_THRESHOLD))
            if nr < NARROW_THRESHOLD:
                failures.append("%s: cross-wording doc hit rate %.3f < %.2f "
                                "(retriever misses documents written with "
                                "different wording)" % (sname, nr,
                                                        NARROW_THRESHOLD))
            if c < CIT_THRESHOLD:
                failures.append("%s: citation precision %.3f < %.2f "
                                "(ungrounded citations)" % (sname, c,
                                                            CIT_THRESHOLD))
        if per_set_citcount:
            overall_cc = sum(per_set_citcount.values()) / \
                len(per_set_citcount)
            if overall_cc < MIN_CIT:
                failures.append("mean citations/answer %.2f < %.1f "
                                "(assembler produced no citations)"
                                % (overall_cc, MIN_CIT))

# ---- verdict ----
if failures:
    print("FAILURES:")
    for m in failures:
        print("  - " + m)
    open("/logs/verifier/reward.txt", "w").write("0")
    sys.exit(0)
print("ALL GATES PASS")
open("/logs/verifier/reward.txt", "w").write("1")
sys.exit(0)
PY