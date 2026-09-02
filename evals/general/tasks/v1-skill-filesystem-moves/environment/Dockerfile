FROM bench-base:python-3.12
WORKDIR /app
RUN mkdir -p /app/loose /app/organized && \
    for f in alpha.py beta.py gamma.py; do printf 'x' > /app/loose/$f; done && \
    for f in delta.csv epsilon.csv zeta.csv; do printf 'y' > /app/loose/$f; done && \
    for f in theta.txt iota.txt kappa.txt; do printf 'z' > /app/loose/$f; done