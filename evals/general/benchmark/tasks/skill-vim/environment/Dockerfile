FROM bench-base:ubuntu-24.04

WORKDIR /app

RUN apt-get update && apt-get install -y vim && rm -rf /var/lib/apt/lists/*

RUN printf 'alpha\nbeta\ngamma\n' > /app/lines.txt