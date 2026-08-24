FROM bench-base:ubuntu-24.04

WORKDIR /app

RUN apt-get update && apt-get install -y g++ libc6-dev && rm -rf /var/lib/apt/lists/*

RUN printf '4\n8\n15\n16\n23\n42\n' > /app/data.txt