FROM bench-base:python-3.12

WORKDIR /app

RUN mkdir -p /app/repo && cd /app/repo && \
    git init -q -b main && \
    git config user.email "dev@example.com" && \
    git config user.name "Dev" && \
    printf 'alpha\n' > data.txt && \
    git add data.txt && \
    git commit -q -m "alpha commit" && \
    printf 'omega\n' > data.txt && \
    git add data.txt && \
    git commit -q -m "omega commit"