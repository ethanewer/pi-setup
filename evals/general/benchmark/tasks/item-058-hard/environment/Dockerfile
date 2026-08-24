FROM bench-base:ubuntu-24.04

RUN apt-get update && apt-get install -y coq && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY files/ /app/