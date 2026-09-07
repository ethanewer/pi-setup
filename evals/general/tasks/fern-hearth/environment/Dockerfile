FROM bench-base:ubuntu-24.04

RUN apt-get update -y && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        git curl ca-certificates python3 python3-bs4 && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY files/ /app/

# Seed the served repository (a bare repo named repo.git) with one main branch.
# A later RUN in this file builds a git repository, so it is root-owned, and git
# refuses to operate on a repository owned by another user: it exits 128 with
# "detected dubious ownership". Whether the trial works then depends on which
# user the harness runs it as. Record the exception in /etc/gitconfig rather
# than root's ~/.gitconfig so it holds for every user, and use the wildcard
# because agents also clone into directories of their own.
RUN git config --system --add safe.directory '*'
RUN git init --bare -q /app/repo.git && \
    rm -rf /tmp/seed && mkdir -p /tmp/seed && cd /tmp/seed && \
    git init -q . && \
    git config user.email build@local && \
    git config user.name builder && \
    echo "# Fast Serve" > README.md && \
    mkdir -p assets && \
    printf 'body{color:#222}\n' > assets/site.css && \
    echo "<html><body>index</body></html>" > index.html && \
    git add -A && git commit -q -m init && \
    git remote add origin /app/repo.git && \
    git push -q origin HEAD:refs/heads/main && \
    git --git-dir=/app/repo.git symbolic-ref HEAD refs/heads/main && \
    cd / && rm -rf /tmp/seed

# Generate the paper index fixture.
RUN python3 /app/make_papers.py && rm -f /app/make_papers.py

CMD ["/bin/bash"]