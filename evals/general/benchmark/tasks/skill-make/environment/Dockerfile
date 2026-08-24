FROM bench-base:ubuntu-24.04

RUN apt-get update && apt-get install -y --no-install-recommends gcc libc6-dev make \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY files/src /app/src