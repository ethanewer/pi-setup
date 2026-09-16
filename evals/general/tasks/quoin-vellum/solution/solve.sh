#!/bin/bash
# Oracle for quoin-vellum: install the generic gensim LDA trainer as the
# deliverable, then run it on the visible corpus to prove the pipeline works.
# (The /tests hidden corpora are exercised by the verifier, not read here.)
set -eu

cp /solution/train_topics.py /app/train_topics.py
chmod +x /app/train_topics.py

python3 /app/train_topics.py /app/corpus /app/oracle_demo.model

echo "solve.sh done -> /app/train_topics.py"
ls -l /app/train_topics.py /app/oracle_demo.model
