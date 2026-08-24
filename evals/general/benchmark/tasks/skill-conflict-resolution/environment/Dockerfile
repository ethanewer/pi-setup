FROM bench-base:ubuntu-24.04

WORKDIR /app

RUN mkdir -p /app/repo
RUN cd /app/repo && \
    git init -b main && \
    git config user.email "dev@example.com" && \
    git config user.name "Dev" && \
    printf 'resolution=duplicate\n' > config.txt && \
    git add config.txt && git commit -m base && \
    git checkout -b feature && \
    printf 'resolution=feature\n' > config.txt && git commit -am feature && \
    git checkout main && \
    printf 'resolution=main\n' > config.txt && git commit -am main2 && \
    (git merge feature 2>/dev/null || true)