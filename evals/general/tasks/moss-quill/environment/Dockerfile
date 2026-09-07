# moss-quill: triage-model training bench. CPU-only, deterministic synthetic
# labeled ticket corpus; scikit-learn pinned for reproducible holdout scores.
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

RUN pip install --no-cache-dir numpy==1.26.4 scikit-learn==1.6.1

COPY files/ /app/

# Ship the labeled ticket corpus the agent trains on (deterministic).
RUN mkdir -p /app/data && python3 /app/gen_tickets.py --out /app/data/tickets.tsv --seed 11 --count 2400

ENV PYTHONUNBUFFERED=1

CMD ["/bin/bash"]
