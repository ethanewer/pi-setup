FROM bench-base:python-3.12
WORKDIR /app
COPY files/ /app/
# Build the dev workload (5000 records + config) deterministically.
RUN python3 /app/tools/gen_records.py --out /app/data/dev \
        --count 5000 --seed 41 --budget 700000 --floor 0.95