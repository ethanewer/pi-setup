FROM bench-base:ubuntu-24.04

# gcc for authoring/compiling the recovery program; python3 for the artifacts.
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        python3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY files/ /app/
