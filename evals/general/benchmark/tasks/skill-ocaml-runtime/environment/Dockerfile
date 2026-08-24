FROM bench-base:ubuntu-24.04

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends ocaml && rm -rf /var/lib/apt/lists/*

RUN printf '13\n27\n8\n44\n19\n' > /app/input.txt