FROM bench-base:ubuntu-24.04

WORKDIR /app

# Build a small local git repo with three revisions and two release tags.
# A later RUN in this file builds a git repository, so it is root-owned, and git
# refuses to operate on a repository owned by another user: it exits 128 with
# "detected dubious ownership". Whether the trial works then depends on which
# user the harness runs it as. Record the exception in /etc/gitconfig rather
# than root's ~/.gitconfig so it holds for every user, and use the wildcard
# because agents also clone into directories of their own.
RUN git config --system --add safe.directory '*'
RUN git config --global user.email "t@bench" && git config --global user.name "t" && \
    mkdir -p /app/repo && cd /app/repo && \
    git init -q -b main && \
    printf 'alpha\n' > version.txt && \
    git add version.txt && git commit -q -m "v1 content" && git tag v1 && \
    printf 'beta\n' > version.txt && \
    git commit -qam "v2 content" && git tag v2 && \
    printf 'gamma\n' > version.txt && \
    git commit -qam "unreleased"