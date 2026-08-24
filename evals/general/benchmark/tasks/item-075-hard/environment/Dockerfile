FROM bench-base:ubuntu-24.04

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends gcc libc6-dev gdb binutils python3 && rm -rf /var/lib/apt/lists/*

COPY files/ /app/

RUN gcc -O0 -g -fno-stack-protector -fcf-protection=none -no-pie -o /app/vuln /app/vuln.c