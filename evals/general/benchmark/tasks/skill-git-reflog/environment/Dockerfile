FROM bench-base:ubuntu-24.04

WORKDIR /app

# Build a repo whose HEAD is reset backwards so a secret commit (adding
# secret.txt) survives only in the reflog.
RUN mkdir -p /app/repo && cd /app/repo && \
    git init -q -b main && \
    git config user.email "dev@example.com" && \
    git config user.name "Dev" && \
    printf 'stage-1\n' > page.txt && \
    git add page.txt && \
    git commit -q -m "stage one" && \
    C1=$(git rev-parse HEAD) && \
    printf 'REFLOG-SECRET-4771\n' > secret.txt && \
    git add secret.txt && \
    git commit -q -m "stage two leak" && \
    C2=$(git rev-parse HEAD) && \
    printf 'stage-3\n' > page.txt && \
    git add page.txt && \
    git commit -q -m "stage three" && \
    git reset -q --hard "$C1"