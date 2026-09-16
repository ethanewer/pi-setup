#!/bin/bash
# Oracle for conduit-quill. Installs the reference RAG solver as /app/rag.py,
# then proves the whole pipeline works end-to-end: builds the index over the
# shipped corpus and answers a dev query. Does the real work; it never reads
# /tests and never hardcodes a hidden answer.
set -eu

cp /solution/rag_solver.py /app/rag.py
chmod +x /app/rag.py

python3 /app/rag.py build --corpus /app/corpus.json --index /tmp/oracle-idx

# Sanity: answer one dev query through the delivered CLI.
q=$(python3 - <<'PY'
import json
queries = json.load(open("/app/dev/queries.json"))
print(queries[0]["query"])
PY
)
python3 /app/rag.py query --query "$q" --top-k 5 \
    --corpus /app/corpus.json --index /tmp/oracle-idx --out /tmp/oracle-out.json

echo "oracle produced /app/rag.py and a working index"
