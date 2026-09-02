FROM bench-base:python-3.12

WORKDIR /app

# CLI tooling under test: vim (for the headless macro pass).
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        vim \
    && rm -rf /var/lib/apt/lists/*

COPY files/ /app/
