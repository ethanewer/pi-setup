FROM bench-base:ubuntu-24.04

WORKDIR /app

RUN apt-get update \
 && apt-get install -y --no-install-recommends r-base python3-pytest \
 && rm -rf /var/lib/apt/lists/*

COPY files/ /app/

RUN mkdir -p /app/tests