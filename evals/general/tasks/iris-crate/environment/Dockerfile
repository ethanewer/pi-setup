FROM bench-base:python-3.12

WORKDIR /app

COPY files/ /app/

# deterministic depot corpus for the agent (seed 7)
RUN python3 /app/gen_tickets.py \
    --train /app/data/train.tsv \
    --holdout /app/data/holdout.tsv \
    --seed 7 --count 4000 --holdout-count 1000

ENV PYTHONUNBUFFERED=1
