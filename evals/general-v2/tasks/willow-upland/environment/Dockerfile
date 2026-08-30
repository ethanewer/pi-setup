FROM bench-base:python-3.12

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends gcc make libc6-dev \
    && rm -rf /var/lib/apt/lists/*

COPY files/ /app/