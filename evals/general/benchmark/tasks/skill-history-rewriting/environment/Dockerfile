FROM bench-base:ubuntu-24.04

WORKDIR /app

# Repo with a leaky middle commit (secret.txt) that must be purged from history.
RUN mkdir -p /app/repo && cd /app/repo && \
    git init -q -b main && \
    git config user.email "dev@example.com" && \
    git config user.name "Dev" && \
    printf 'main cfg\n' > readme.md && \
    printf 'seed=1\n' > seed.cfg && \
    git add -A && \
    git commit -q -m "base config" && \
    printf 'TOPSECRET-4646\n' > secret.txt && \
    git add secret.txt && \
    git commit -q -m "leak: add secret file" && \
    printf '2.0\n' > feature.txt && \
    git add feature.txt && \
    git commit -q -m "add feature"