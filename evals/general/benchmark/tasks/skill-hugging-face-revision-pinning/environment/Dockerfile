FROM bench-base:ubuntu-24.04

WORKDIR /app

# Build a small local git repo with three revisions and two release tags.
RUN git config --global user.email "t@bench" && git config --global user.name "t" && \
    mkdir -p /app/repo && cd /app/repo && \
    git init -q -b main && \
    printf 'alpha\n' > version.txt && \
    git add version.txt && git commit -q -m "v1 content" && git tag v1 && \
    printf 'beta\n' > version.txt && \
    git commit -qam "v2 content" && git tag v2 && \
    printf 'gamma\n' > version.txt && \
    git commit -qam "unreleased"