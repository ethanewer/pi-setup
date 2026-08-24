FROM bench-base:ubuntu-24.04

WORKDIR /app

# A shared bare repository (no working tree), on default branch 'main'.
RUN mkdir -p /app && git init -b main --bare /app/team.git