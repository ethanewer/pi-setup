# moss-quill: triage-model training bench. CPU-only, deterministic synthetic
# labeled ticket corpus; scikit-learn pinned for reproducible holdout scores.
FROM bench-base:python-3.12

WORKDIR /app

RUN pip install --no-cache-dir numpy==1.26.4 scikit-learn==1.6.1

COPY files/ /app/

# Ship the labeled ticket corpus the agent trains on (deterministic).
RUN mkdir -p /app/data && python3 /app/gen_tickets.py --out /app/data/tickets.tsv --seed 11 --count 2400

ENV PYTHONUNBUFFERED=1

CMD ["/bin/bash"]
