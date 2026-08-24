FROM bench-base:ubuntu-24.04

WORKDIR /app

RUN apt-get update && apt-get install -y vim && rm -rf /var/lib/apt/lists/*

COPY files/data.csv /app/data.csv