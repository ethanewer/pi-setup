FROM bench-base:ubuntu-24.04

WORKDIR /app

# Build a git repository with a branch whose branch is force-deleted, leaving
# its secret commit (containing secret.txt) as a dangling/unreachable object.
# A later RUN in this file builds a git repository, so it is root-owned, and git
# refuses to operate on a repository owned by another user: it exits 128 with
# "detected dubious ownership". Whether the trial works then depends on which
# user the harness runs it as. Record the exception in /etc/gitconfig rather
# than root's ~/.gitconfig so it holds for every user, and use the wildcard
# because agents also clone into directories of their own.
RUN git config --system --add safe.directory '*'
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