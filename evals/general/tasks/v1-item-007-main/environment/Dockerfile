FROM bench-base:ubuntu-24.04

WORKDIR /app

RUN apt-get update && apt-get install -y make g++ libc6-dev && rm -rf /var/lib/apt/lists/*
RUN mkdir -p /app/run

# Data is pre-generated and shipped under files/data/train.bin
COPY files/ /app/