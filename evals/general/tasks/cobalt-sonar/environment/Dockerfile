# cobalt-sonar task image: fastText ticket-triage classifier under a size
# budget. CPU-only, no network at run/verify time.
FROM bench-base:python-3.12

# [environment] declares cpus = 1, which Docker enforces as a CFS
# quota and not as a CPU-affinity mask: the process still sees every
# host core, so thread pools sized from the core count oversubscribe the
# quota badly. Pin them to the declared budget.
ENV OMP_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1

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
