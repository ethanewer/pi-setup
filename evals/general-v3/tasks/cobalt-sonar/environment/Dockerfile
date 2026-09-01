# cobalt-sonar task image: fastText ticket-triage classifier under a size
# budget. CPU-only, no network at run/verify time.
FROM bench-base:python-3.12

WORKDIR /app

RUN pip install --no-cache-dir \
    numpy==1.26.4 \
    fasttext-wheel==0.9.2

# shared corpus generator fixture
COPY files/ /app/

# ship the labeled corpus for the agent (deterministic)
RUN mkdir -p /app/data && \
    python3 /app/gen_corpus.py --out /app/data/tickets.tsv --seed 11 --count 3000

ENV PYTHONUNBUFFERED=1

CMD ["/bin/bash"]
