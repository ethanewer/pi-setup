FROM bench-base:python-3.12

# tar and gzip are used to inspect the bundle archive.
RUN apt-get update -y \
 && apt-get install -y --no-install-recommends tar gzip \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY files/ /app/
