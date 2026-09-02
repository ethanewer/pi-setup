FROM bench-base:python-3.12
RUN apt-get update && \
    apt-get install -y --no-install-recommends jq && \
    rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY files/ /app/