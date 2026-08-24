FROM bench-base:ubuntu-24.04

RUN apt-get update && apt-get install -y p7zip-full && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY files/archive.7z /app/archive.7z