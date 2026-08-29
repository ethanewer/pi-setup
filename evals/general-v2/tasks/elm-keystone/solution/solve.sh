#!/bin/bash
# Oracle for elm-keystone: install the real /app/solve.py program, then RUN it
# on the committed input to produce /app/answer.json and the full artifact pack.
# All outputs are produced by executing the program (never cat a precomputed
# answer). This oracle never reads /tests.
set -euo pipefail

install -m 0755 /solution/solve.py /app/solve.py

python3 /app/solve.py --input /opt/keystone/requests.csv --output /app

test -f /app/answer.json && echo "oracle ok: /app/answer.json present"