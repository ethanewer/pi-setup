FROM bench-base:python-3.12

WORKDIR /app

# Read-only fixtures: the orchard dataset and the shipped config.
COPY files/ /app/
RUN mkdir -p /app/data && mv /app/orchard.csv /app/data/orchard.csv
