FROM bench-base:ubuntu-24.04

WORKDIR /app

RUN mkdir -p /app/repo/seed && cd /app/repo && \
    git init -q -b main && \
    git config user.email "dev@example.com" && \
    git config user.name "Dev" && \
    printf 'object-db-probe-42\n' > seed/input.txt && \
    git add seed/input.txt && \
    git commit -q -m "add seed input"