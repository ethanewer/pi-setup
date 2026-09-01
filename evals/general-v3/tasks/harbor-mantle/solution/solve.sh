#!/bin/bash
# Oracle for harbor-mantle: install the real authoring deliverables and RUN them
# so the deliverable actually executes in Triton CPU-interpreter mode and the
# check proves it matches the torch reference and fits under the cap.
# This oracle never reads /tests.
set -euo pipefail

install -m 0755 /solution/kernels.py /app/kernels.py
install -m 0755 /solution/check.py /app/check.py

# Run the deliverable end-to-end under the Triton interpreter (no GPU needed).
TRITON_INTERPRET=1 python3 /app/check.py

echo "oracle ok"