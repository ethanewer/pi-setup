FROM bench-base:python-3.12

# conduit-quill: RAG over a local corpus. The only third-party dependency we
# bake in is numpy (optional for agents; the reference solver is pure-stdlib).
ENV OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1

RUN pip install --no-cache-dir numpy==2.1.3

WORKDIR /app
COPY files/ /app/

# Generate the deterministic corpus and the visible dev query set at build
# time so /app/corpus.json and /app/dev/queries.json exist when the agent
# arrives. The generator itself is then removed from the image: from the
# agent's point of view the corpus is plain data (no construction recipe), and
# the hidden query sets live under /tests (separate from /app). evaluate.py is
# a readiness driver and stays.
RUN python3 /app/generate_corpus.py /app \
    && rm -f /app/generate_corpus.py \
    && rm -rf /app/__pycache__

CMD ["/bin/bash"]