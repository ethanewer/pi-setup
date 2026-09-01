FROM bench-base:ubuntu-24.04

WORKDIR /app

# Build a git repository with a branch whose branch is force-deleted, leaving
# its secret commit (containing secret.txt) as a dangling/unreachable object.
RUN git init -b master /app/repo && \
    cd /app/repo && \
    git config user.email "dev@example.com" && git config user.name "Dev" && \
    printf "alpha\n" > a.txt && git add a.txt && git commit -q -m "initial" && \
    git checkout -q -b feature && \
    printf "CLASSIFIED-31415\n" > secret.txt && git add secret.txt && git commit -q -m "add secret" && \
    printf "feature note\n" > feat.txt && git add feat.txt && git commit -q -m "feature note" && \
    git checkout -q master && \
    git branch -D feature && \
    printf "beta\n" > b.txt && git add b.txt && git commit -q -m "master work"