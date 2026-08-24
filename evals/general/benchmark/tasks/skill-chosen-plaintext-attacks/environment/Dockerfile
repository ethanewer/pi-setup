FROM bench-base:python-3.12

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends gcc libc6-dev && rm -rf /var/lib/apt/lists/*

COPY files/oracle.c /app/oracle.c
RUN gcc -O2 -o /app/oracle /app/oracle.c && rm /app/oracle.c