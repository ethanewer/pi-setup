# kite-helix: release-archive triage environment
FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 zip genisoimage acl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY files/ /app/