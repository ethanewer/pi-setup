FROM bench-base:ubuntu-24.04

WORKDIR /app

RUN apt-get update && apt-get install -y r-base && rm -rf /var/lib/apt/lists/*

COPY files/stats.csv /app/stats.csv
